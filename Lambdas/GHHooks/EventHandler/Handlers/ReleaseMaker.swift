import AsyncHTTPClient
import DiscordBM
import GitHubAPI
import Logging
import Markdown
import NIOCore
import NIOFoundationCompat
import SwiftSemver

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct ReleaseMaker {

    enum Configuration {
        /// The postgres-nio repository ID.
        static let repositoryIDDenyList: Set<Int64> = [150_622_661]
        /// Needs the Penny installation to be installed on the org,
        /// which is not possible without making Penny app public.
        /// The Vapor organization ID.
        static let organizationIDAllowList: Set<Int64> = [17_364_220]
        static let releaseNoticePrefix = "**These changes are now available in"
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
            let mergedBy = pr.mergedBy,
            pr.base.ref.isPrimaryOrReleaseBranch(repo: repo),
            let bump = pr.knownLabels.semVerBump()
        else { return }

        let prereleaseRequested = pr.knownLabels.contains(.prerelease)
        let previousRelease = try await getLastRelease(prerelease: prereleaseRequested)

        let previousTag = previousRelease.tagName
        guard let (tagPrefix, previousVersion) = SemanticVersion.fromGitHubTag(previousTag) else {
            throw PRErrors.tagDoesNotFollowSemVer(release: previousRelease, tag: previousTag)
        }

        guard let version = previousVersion.next(bump, forcePrerelease: prereleaseRequested) else {
            throw PRErrors.cantBumpSemVer(version: previousVersion, bump: bump)
        }
        let versionDescription = tagPrefix + version.description

        let release = try await makeNewRelease(
            previousVersion: previousTag,
            newVersion: versionDescription,
            mergedBy: mergedBy,
            isPrerelease: !version.prereleaseIdentifiers.isEmpty
        )

        try await updatePRBodyWithReleaseNotice(release: release)
    }

    func getLastRelease(prerelease: Bool) async throws -> Release {
        let releases = try await self.getRelatedReleases()

        let latest = try await self.getLatestRelease(from: releases, prerelease: prerelease)

        let filteredReleases: [Release] = releases.filter { release, version -> Bool in
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
            throw PRErrors.cantFindAnyRelease(latest: latest, releases: releases.map(\.0))
        }

        return release
    }

    private func getRelatedReleases() async throws -> [(Release, SemanticVersion)] {
        let releases = try await context.githubClient.reposListReleases(
            path: .init(
                owner: repo.owner.login,
                repo: repo.name
            )
        ).ok.body.json

        /// These release are already sorted by `created_at` in descending order by GitHub.
        return releases.filter {
            /// Only include releases that are targeting the same branch as the PR.
            $0.targetCommitish == pr.base.ref
        }.compactMap { release -> (Release, SemanticVersion)? in
            if let (_, version) = SemanticVersion.fromGitHubTag(release.tagName) {
                return (release, version)
            }
            logger.warning("Could not parse tag", metadata: ["tag": .string(release.tagName)])
            return nil
        }
    }

    private func getTheReleaseMarkAsLatest() async throws -> Release? {
        let response = try await context.githubClient.reposGetLatestRelease(
            path: .init(
                owner: repo.owner.login,
                repo: repo.name
            )
        )

        if case let .ok(ok) = response,
            case let .json(json) = ok.body
        {
            return json
        }

        logger.warning(
            "Could not find a 'latest' release",
            metadata: [
                "owner": .string(repo.owner.login),
                "name": .string(repo.name),
                "response": "\(response)",
            ]
        )

        return nil
    }

    private func getLatestRelease(
        from releases: [(Release, SemanticVersion)],
        prerelease: Bool
    ) async throws -> Release? {
        if prerelease {
            return releases.filter { _, version in
                !version.prereleaseIdentifiers.isEmpty
            }.sorted {
                $0.1 > $1.1
            }.first?.0
        } else {
            if let markedAsLatest = try await self.getTheReleaseMarkAsLatest(),
                /// Only include releases that are targeting the same branch as the PR.
                markedAsLatest.targetCommitish == pr.base.ref
            {
                return markedAsLatest
            } else {
                return releases.first(where: { !$0.0.prerelease })?.0
            }
        }
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
        return try await context.githubClient.reposCreateRelease(
            path: .init(
                owner: repo.owner.login,
                repo: repo.name
            ),
            body: .json(
                .init(
                    tagName: newVersion,
                    targetCommitish: pr.base.ref,
                    name: "\(newVersion) - \(pr.title)",
                    body: body,
                    draft: false,
                    prerelease: isPrerelease,
                    makeLatest: isPrerelease ? ._false : ._true
                )
            )
        ).created.body.json
    }

    func updatePRBodyWithReleaseNotice(release: Release) async throws {
        let current = try await context.githubClient.pullsGet(
            path: .init(
                owner: repo.owner.login,
                repo: repo.name,
                pullNumber: number
            )
        ).ok.body.json
        if (current.body ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .hasPrefix(Configuration.releaseNoticePrefix)
        {
            logger.debug(
                "Pull request doesn't need to be updated with release notice",
                metadata: [
                    "current": "\(current)"
                ]
            )
            return
        }
        let updated = try await context.githubClient.pullsUpdate(
            path: .init(
                owner: repo.owner.login,
                repo: repo.name,
                pullNumber: number
            ),
            body: .json(
                .init(
                    body: """
                        \(Configuration.releaseNoticePrefix) [\(release.tagName)](\(release.htmlUrl))**


                        \(current.body ?? "")
                        """
                )
            )
        ).ok.body.json
        logger.debug(
            "Updated a pull request with a release notice",
            metadata: [
                "before": "\(current)",
                "after": "\(updated)",
            ]
        )
    }

    /// - A user who appears in a given repo's code owners file should NOT be credited as either an author or reviewer for a release in that repo (but can still be credited for releasing it).
    /// - The user who authored the PR should be credited unless they are a code owner. Such a credit should be prominent and - as the GitHub changelog generator does - include a notation if it's that user's first merged PR.
    /// - Any users who reviewed the PR (even if they requested changes or did a comments-only review without approving) should also be credited unless they are code owners. Such a credit should be less prominent than the author credit, something like a "thanks to ... for helping to review this release"
    /// - The release author (user who merged the PR) should always be credited in a release, even if they're a code owner. This credit should be the least prominent, maybe even just a footnote (since it will pretty much always be a owner/maintainer).
    func makeReleaseBody(
        mergedBy: NullableUser,
        previousVersion: String,
        newVersion: String
    ) async throws -> String {
        let codeOwners = try await context.requester.getCodeOwners(
            repoFullName: repo.fullName,
            branch: pr.base.ref
        )
        let contributors = try await getExistingContributorIDs()
        let isNewContributor = isNewContributor(
            codeOwners: codeOwners,
            existingContributors: contributors
        )
        let reviewers = try await getReviewersToCredit(codeOwners: codeOwners).map(\.uiName)

        let bodyNoReleaseNotice = pr.body.map { $0.trimmingReleaseNoticeFromBody() } ?? ""
        let body = bodyNoReleaseNotice.formatMarkdown(
            maxVisualLength: 1_024,
            hardLimit: 2_048,
            trailingTextMinLength: 128
        ).quotedMarkdown()

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
                repo: .init(fullName: repo.fullName),
                release: .init(
                    oldTag: previousVersion,
                    newTag: newVersion
                )
            )
        )
    }

    func getReviewersToCredit(codeOwners: CodeOwners) async throws -> [NullableUser] {
        let noCreditUsers = codeOwners.union([pr.user.login])
        let reviews = try await getReviews()
        let reviewers = reviews.compactMap(\.user).filter { user in
            !(noCreditUsers.contains(user: user) || user.isBot)
        }
        let groupedReviewers = Dictionary(grouping: reviewers, by: \.id)
        let sorted = groupedReviewers.values.sorted(by: { $0.count > $1.count }).map(\.[0])
        return sorted
    }

    func isNewContributor(codeOwners: CodeOwners, existingContributors: Set<Int64>) -> Bool {
        pr.authorAssociation != .owner
            && !pr.user.isBot
            && !codeOwners.contains(user: pr.user)
            && !existingContributors.contains(pr.user.id)
    }

    func getReviews() async throws -> [PullRequestReview] {
        let response = try await context.githubClient.pullsListReviews(
            .init(
                path: .init(
                    owner: repo.owner.login,
                    repo: repo.name,
                    pullNumber: number
                )
            )
        )

        do {
            return try response.ok.body.json
        } catch {
            logger.warning(
                "Could not find reviews",
                metadata: [
                    "response": "\(response)",
                    "error": "\(String(reflecting: error))",
                ]
            )
            return []
        }
    }

    func getExistingContributorIDs() async throws -> Set<Int64> {
        var page = 1
        var contributorIds: [Int64] = []
        /// Hack: Vapor has around this amount of contributors and we know it, so better
        /// to reserve enough capacity for it up-front.
        contributorIds.reserveCapacity(250)
        while true {
            let (ids, hasNext) = try await self.getExistingContributorIDs(page: page)
            if ids.isEmpty {
                break
            }
            contributorIds.append(contentsOf: consume ids)
            guard hasNext else { break }
            page += 1
        }
        return Set(contributorIds)
    }

    func getExistingContributorIDs(page: Int) async throws -> (ids: [Int64], hasNext: Bool) {
        logger.debug(
            "Will fetch current contributors",
            metadata: [
                "page": .stringConvertible(page)
            ]
        )

        let response = try await context.githubClient.reposListContributors(
            path: .init(
                owner: repo.owner.login,
                repo: repo.name
            ),
            query: .init(
                perPage: 100,
                page: page
            )
        )

        do {
            let ok = try response.ok
            let json = try ok.body.json
            /// Example of a `link` header: `<https://api.github.com/repositories/49910095/contributors?page=6>; rel="prev", <https://api.github.com/repositories/49910095/contributors?page=8>; rel="next", <https://api.github.com/repositories/49910095/contributors?page=8>; rel="last", <https://api.github.com/repositories/49910095/contributors?page=1>; rel="first"`
            /// If the header contains `rel="next"` then we'll have a next page to fetch.
            let hasNext =
                switch ok.headers.link {
                case let .some(string):
                    string.contains(#"rel="next""#)
                case .none:
                    false
                }
            let ids = json.compactMap(\.id).map(Int64.init)
            logger.debug(
                "Fetched some contributors",
                metadata: [
                    "page": .stringConvertible(page),
                    "count": .stringConvertible(ids.count),
                ]
            )
            return (ids, hasNext)
        } catch {
            logger.error(
                "Error when fetching contributors but will continue",
                metadata: [
                    "page": .stringConvertible(page),
                    "response": "\(response)",
                    "error": "\(String(reflecting: error))",
                ]
            )
            return ([], false)
        }
    }
}

extension String {
    func trimmingReleaseNoticeFromBody() -> String {
        let trimmedBody = self.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.hasPrefix(ReleaseMaker.Configuration.releaseNoticePrefix) {
            return trimmedBody.split(
                separator: "\n",
                omittingEmptySubsequences: false
            )
            .dropFirst()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return trimmedBody
        }
    }
}
