import DiscordBM
import GithubAPI
import SwiftSemver
import Markdown

struct PRHandler {

    enum Errors: Error, CustomStringConvertible {
        case httpRequestFailed(response: Any, file: String = #filePath, line: UInt = #line)
        case tagDoesNotFollowSemVer(release: Release, tag: String)
        case cantBumpSemVer(version: SemanticVersion, bump: SemVerBump)
        case cantFindAnyRelease(latest: Release?, releases: [Release])

        var description: String {
            switch self {
            case let .httpRequestFailed(response, file, line):
                return "httpRequestFailed(response: \(response), file: \(file), line: \(line))"
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
    var event: GHEvent {
        context.event
    }
    var repo: Repository {
        event.repository
    }

    init(context: HandlerContext) throws {
        self.context = context
        self.pr = try context.event.pull_request.requireValue()
        self.number = try context.event.number.requireValue()
    }

    func handle() async throws {
        let action = context.event.action.map({ PullRequest.Action(rawValue: $0) })
        switch action {
        case .opened:
            try await onOpened()
        case .closed:
            try await onClosed()
        case .edited:
            try await onEdited()
        default: break
        }
    }

    func onEdited() async throws {
        try await editPRReport()
    }

    func onOpened() async throws {
        let embed = createReportEmbed()
        let reporter = Reporter(context: context)
        try await reporter.reportNew(embed: embed)
    }

    func onClosed() async throws {
        try await makeReleaseForMergedPR()
        try await editPRReport()
    }

    func makeReleaseForMergedPR() async throws {
        guard pr.base.ref == "main",
              let mergedBy = pr.merged_by,
              let bump = pr.knownLabels.first?.toBump()
        else { return }

        let previousRelease = try await getLastRelease()

        let tag = previousRelease.tag_name
        guard let (tagPrefix, previousVersion) = SemanticVersion.fromGithubTag(tag) else {
            throw Errors.tagDoesNotFollowSemVer(release: previousRelease, tag: tag)
        }

        guard let version = previousVersion.next(bump) else {
            throw Errors.cantBumpSemVer(version: previousVersion, bump: bump)
        }
        let versionDescription = tagPrefix + version.description

        let acknowledgment: String
        if pr.user.login == mergedBy.login {
            acknowledgment = "This patch was authored and released by @\(pr.user.login)."
        } else {
            acknowledgment = "This patch was authored by @\(pr.user.login) and released by @\(mergedBy.login)."
        }

        let release = try await makeNewRelease(
            version: versionDescription,
            isPrerelease: !version.prereleaseIdentifiers.isEmpty,
            acknowledgment: acknowledgment
        )

        try await sendComment(release: release)

        try await context.discordClient.createMessage(
            channelId: Constants.Channels.release.id,
            payload: .init(
                content: """
                [\(repo.uiName)] \(version.description): \(pr.title)
                \(release.html_url)
                """
            )
        ).guardSuccess()
    }

    func editPRReport() async throws {
        let embed = createReportEmbed()
        let reporter = Reporter(context: context)
        try await reporter.reportEdit(embed: embed)
    }

    func createReportEmbed() -> Embed {
        let authorName = pr.user.login
        let authorAvatarLink = pr.user.avatar_url

        let prLink = pr.html_url

        let body = pr.body.map { body -> String in
            let formatted = Document(parsing: body)
                .removeHTMLBlocks()?
                .format() ?? ""
            return formatted.isEmpty ? "" : ">>> \(formatted)".unicodesPrefix(260)
        } ?? ""

        let description = """
        ### \(pr.title)

        \(body)
        """

        let status = Status(pr: pr)
        let statusString = status.titleDescription.map { " - \($0)" } ?? ""
        let maxCount = 256 - statusString.unicodeScalars.count
        let title = "[\(repo.uiName)] PR #\(number)".unicodesPrefix(maxCount) + statusString

        let embed = Embed(
            title: title,
            description: description,
            url: prLink,
            color: status.color,
            footer: .init(
                text: "By \(authorName)",
                icon_url: .exact(authorAvatarLink)
            )
        )

        return embed
    }
}

private extension PRHandler {
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
            if let (_, version) = SemanticVersion.fromGithubTag(release.tag_name) {
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
            throw Errors.cantFindAnyRelease(latest: latest, releases: releases)
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

        context.logger.warning("Could not find a 'latest' release", metadata: [
            "owner": .string(repo.owner.login),
            "name": .string(repo.name),
            "response": "\(response)",
        ])

        return nil
    }

    func makeNewRelease(
        version: String,
        isPrerelease: Bool,
        acknowledgment: String
    ) async throws -> Release {
        let response = try await context.githubClient.repos_create_release(.init(
            path: .init(
                owner: repo.owner.login,
                repo: repo.name
            ),
            body: .json(.init(
                tag_name: version,
                target_commitish: pr.base.ref,
                name: "\(version) - \(pr.title)",
                body: """
                ###### _\(acknowledgment)_

                \(pr.body ?? "Pull Request"); in \(pr.html_url)
                """,
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
}

private enum Status: String {
    case merged = "Merged"
    case closed = "Closed"
    case draft = "Draft"
    case opened = "Opened"

    var color: DiscordColor {
        switch self {
        case .merged:
            return .purple
        case .closed:
            return .red
        case .draft:
            return .gray
        case .opened:
            return .green
        }
    }

    var titleDescription: String? {
        switch self {
        case .opened:
            return nil
        case .merged, .closed, .draft:
            return self.rawValue
        }
    }

    init(pr: PullRequest) {
        if pr.merged_by != nil {
            self = .merged
        } else if pr.closed_at != nil {
            self = .closed
        } else if pr.draft == true {
            self = .draft
        } else {
            self = .opened
        }
    }
}
