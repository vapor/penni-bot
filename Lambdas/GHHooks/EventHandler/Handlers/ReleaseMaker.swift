import DiscordBM
import AsyncHTTPClient
import NIOCore
import NIOFoundationCompat
import GitHubAPI
import SwiftSemver
import Markdown
import Logging
import Foundation

struct ReleaseMaker {

    enum Configuration {
        static let repositoryIDDenyList: Set<Int> = [/*postgres-nio:*/ 150622661]
        /// Needs the Penny installation to be installed on the org,
        /// which is not possible without making Penny app public.
        static let organizationIDAllowList: Set<Int> = [/*vapor:*/ 17364220]
    }

    enum PRErrors: Error, CustomStringConvertible {
        case tagDoesNotFollowSemVer(release: Release, tag: String)
        case cantBumpSemVer(version: SemanticVersion, bump: SemVerBump)
        case cantFindAnyRelease(latest: Release?, releases: [Release])

        var description: String {
            switch self {
            case let .tagDoesNotFollowSemVer(release, tag):
                return "tagDoesNotFollowSemVer(release: \(release), tag: \(tag))"
            case let .cantBumpSemVer(version, bump):
                return "cantBumpSemVer(version: \(version), bump: \(bump))"
            case let .cantFindAnyRelease(latest, releases):
                return "cantFindAnyRelease(latest: \(String(describing: latest)), releases: \(releases))"
            }
        }
    }

    let context: HandlerContext
    let pr: PullRequest
    let number: Int
    let repo: Repository
    var event: GHEvent {
        context.event
    }
    var logger: Logger {
        context.logger
    }

    init(context: HandlerContext, pr: PullRequest, number: Int) throws {
        self.context = context
        self.pr = pr
        self.number = number
        self.repo = try context.event.repository.requireValue()
    }

    func handle() async throws {
        guard !Configuration.repositoryIDDenyList.contains(repo.id),
              Configuration.organizationIDAllowList.contains(repo.owner.id),
              let mergedBy = pr.merged_by,
              pr.base.ref == "main",
              let bump = pr.knownLabels.first?.toBump()
        else { return }

        let previousRelease = try await getLastRelease()

        let previousTag = previousRelease.tag_name
        guard let (tagPrefix, previousVersion) = SemanticVersion.fromGitHubTag(previousTag) else {
            throw PRErrors.tagDoesNotFollowSemVer(release: previousRelease, tag: previousTag)
        }

        guard let version = previousVersion.next(bump) else {
            throw PRErrors.cantBumpSemVer(version: previousVersion, bump: bump)
        }
        let versionDescription = tagPrefix + version.description

        let release = try await makeNewRelease(
            previousVersion: previousTag,
            newVersion: versionDescription,
            mergedBy: mergedBy,
            isPrerelease: !version.prereleaseIdentifiers.isEmpty
        )

        try await sendComment(release: release)
    }

    func getLastRelease() async throws -> Release {
        let latest = try await self.getLatestRelease()

        let response = try await context.githubClient.repos_list_releases(.init(
            path: .init(
                owner: repo.owner.login,
                repo: repo.name
            )
        ))

        guard case let .ok(ok) = response,
              case let .json(releases) = ok.body
        else {
            throw Errors.httpRequestFailed(response: response)
        }

        let filteredReleases: [Release] = releases.compactMap {
            release -> (Release, SemanticVersion)? in
            if let (_, version) = SemanticVersion.fromGitHubTag(release.tag_name) {
                return (release, version)
            }
            return nil
        }.filter { release, version -> Bool in
            if let majorVersion = Int(pr.base.ref) {
                /// If the branch name is an integer, only include releases
                /// for that major version.
                return version.major == majorVersion
            }
            return true
        }.sorted {
            $0.1 > $1.1
        }.sorted { (lhs, rhs) in
            if let latest {
                return latest.id == lhs.0.id
            }
            return true
        }.map(\.0)

        guard let release = filteredReleases.first else {
            throw PRErrors.cantFindAnyRelease(latest: latest, releases: releases)
        }

        return release
    }

    private func getLatestRelease() async throws -> Release? {
        let response = try await context.githubClient.repos_get_latest_release(.init(
            path: .init(
                owner: repo.owner.login,
                repo: repo.name
            )
        ))

        switch response {
        case let .ok(ok):
            switch ok.body {
            case let .json(json):
                return json
            }
        default: break
        }

        logger.warning("Could not find a 'latest' release", metadata: [
            "owner": .string(repo.owner.login),
            "name": .string(repo.name),
            "response": "\(response)",
        ])

        return nil
    }

    func makeNewRelease(
        previousVersion: String,
        newVersion: String,
        mergedBy: NullableUser,
        isPrerelease: Bool
    ) async throws -> Release {
        let body = try await makeReleaseBody(
            mergedBy: mergedBy,
            previousVersion: previousVersion,
            newVersion: newVersion
        )
        let response = try await context.githubClient.repos_create_release(.init(
            path: .init(
                owner: repo.owner.login,
                repo: repo.name
            ),
            body: .json(.init(
                tag_name: newVersion,
                target_commitish: pr.base.ref,
                name: "\(newVersion) - \(pr.title)",
                body: body,
                draft: false,
                prerelease: isPrerelease,
                make_latest: isPrerelease ? ._false : ._true
            ))
        ))

        switch response {
        case let .created(created):
            switch created.body {
            case let .json(release):
                return release
            }
        default: break
        }

        throw Errors.httpRequestFailed(response: response)
    }

    func sendComment(release: Release) async throws {
        /// `"Issues" create comment`, but works for PRs too. Didn't find an endpoint for PRs.
        let response = try await context.githubClient.issues_create_comment(.init(
            path: .init(
                owner: repo.owner.login,
                repo: repo.name,
                issue_number: number
            ),
            body: .json(.init(
                body: """
                These changes are now available in [\(release.tag_name)](\(release.html_url))
                """
            ))
        ))

        switch response {
        case .created: return
        default:
            throw Errors.httpRequestFailed(response: response)
        }
    }

    /**
     - A user who appears in a given repo's code owners file should NOT be credited as either an author or reviewer for a release in that repo (but can still be credited for releasing it).
     - The user who authored the PR should be credited unless they are a code owner. Such a credit should be prominent and - as the GitHub changelog generator does - include a notation if it's that user's first merged PR.
     - Any users who reviewed the PR (even if they requested changes or did a comments-only review without approving) should also be credited unless they are code owners. Such a credit should be less prominent than the author credit, something like a "thanks to ... for helping to review this release"
     - The release author (user who merged the PR) should always be credited in a release, even if they're a code owner. This credit should be the least prominent, maybe even just a footnote (since it will pretty much always be a owner/maintainer).
     */
    func makeReleaseBody(
        mergedBy: NullableUser,
        previousVersion: String,
        newVersion: String
    ) async throws -> String {
        let codeOwners = try await context.requester.getCodeOwners(
            repoFullName: repo.full_name,
            primaryBranch: repo.primaryBranch
        )
        let contributors = try await getExistingContributorIDs()
        let isNewContributor = isNewContributor(
            codeOwners: codeOwners,
            existingContributors: contributors
        )
        let reviewers = try await getReviewersToCredit(codeOwners: codeOwners).map(\.uiName)

        let body = pr.body.map {
            $0.formatMarkdown(
                maxLength: 512,
                trailingTextMinLength: 96
            ).quotedMarkdown()
        } ?? ""

        return try await context.renderClient.newReleaseDescription(
            context: .init(
                pr: .init(
                    title: pr.title,
                    body: body,
                    author: pr.user.uiName,
                    number: number
                ),
                isNewContributor: isNewContributor,
                reviewers: reviewers,
                merged_by: mergedBy.uiName,
                repo: .init(fullName: repo.full_name),
                release: .init(
                    oldTag: previousVersion,
                    newTag: newVersion
                )
            )
        )
    }

    func getReviewersToCredit(codeOwners: CodeOwners) async throws -> [User] {
        let usernames = codeOwners.union([pr.user.login])
        let reviewComments = try await getReviewComments()
        let reviewers = reviewComments.map(\.user).filter { user in
            !(usernames.contains(user: user) || user.isBot)
        }
        let groupedReviewers = Dictionary(grouping: reviewers, by: \.id)
        let sorted = groupedReviewers.values.sorted(by: { $0.count > $1.count }).map(\.[0])
        return sorted
    }

    func isNewContributor(codeOwners: CodeOwners, existingContributors: Set<Int>) -> Bool {
        if pr.author_association == .OWNER ||
            pr.user.isBot ||
            codeOwners.contains(user: pr.user) {
            return false
        }
        return !existingContributors.contains(pr.user.id)
    }

    func getReviewComments() async throws -> [PullRequestReviewComment] {
        let response = try await context.githubClient.pulls_list_review_comments(
            .init(path: .init(
                owner: repo.owner.login,
                repo: repo.name,
                pull_number: number
            ))
        )

        guard case let .ok(ok) = response,
              case let .json(json) = ok.body
        else {
            logger.warning("Could not find review comments", metadata: [
                "response": "\(response)"
            ])
            return []
        }

        return json
    }

    func getExistingContributorIDs() async throws -> Set<Int> {
        let response = try await context.githubClient.repos_list_contributors(
            .init(path: .init(
                owner: repo.owner.login,
                repo: repo.name
            ))
        )

        guard case let .ok(ok) = response,
              case let .json(json) = ok.body
        else {
            logger.warning("Could not find current contributors", metadata: [
                "response": "\(response)"
            ])
            return []
        }

        return Set(json.compactMap(\.id))
    }
}
