import Algorithms
import AsyncHTTPClient
import DiscordBM
import GitHubAPI
import Logging

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct ReleaseReporter {
    let context: HandlerContext
    let release: Release
    let repo: Repository
    var logger: Logger {
        context.logger
    }

    init(context: HandlerContext) throws {
        self.context = context
        self.release = try context.event.release.requireValue()
        self.repo = try context.event.repository.requireValue()
    }

    func handle() async throws {
        let action = try context.event.action
            .flatMap({ Release.Action(rawValue: $0) })
            .requireValue()
        switch action {
        case .published:
            try await handleReleasePublished()
        default:
            break
        }
    }

    func handleReleasePublished() async throws {
        let (commitCount, relatedPRs) = try await self.getPRsRelatedToRelease()
        if relatedPRs.isEmpty {
            try await self.sendToDiscordWithRelease()
        } else if relatedPRs.count == 1 || release.author.id == Constants.GitHub.userID {
            /// If there is only 1 PR or if Penny released this, then just mention the last PR.
            try await self.sendToDiscord(pr: relatedPRs[0])
        } else {
            try await self.sendToDiscord(prs: relatedPRs, commitCount: commitCount)
        }
    }

    func getPRsRelatedToRelease() async throws -> (Int, [SimplePullRequest]) {
        let commits: [Commit] =
            if let comparisonRange = self.findComparisonRange() {
                try await self.getCommitsInRelease(
                    comparisonRange: comparisonRange
                )
            } else if let tagBefore = try await self.getTagBefore() {
                try await self.getCommitsInRelease(
                    comparisonRange: "\(tagBefore)...\(release.tagName)"
                )
            } else {
                try await self.getAllCommits()
            }

        let maxCommits = 5
        let maxPRs = 3
        var prs = [SimplePullRequest]()
        prs.reserveCapacity(min(commits.count, maxPRs))

        for commit in commits.prefix(maxCommits) where prs.count < 3 {
            let newPRs = try await getPRsRelatedToCommit(sha: commit.sha)
            prs.append(contentsOf: newPRs)
        }
        prs = prs.uniqued(on: \.htmlUrl)

        return (commits.count, prs)
    }

    func findComparisonRange() -> String? {
        guard let body = release.body else {
            return nil
        }
        let linkPrefix = "https://github.com/\(repo.fullName)/compare/"
        let lines = body.lazy.split(separator: "\n")
        let comparisonLine = lines.reversed().first {
            $0.contains(linkPrefix)
        }
        let components = comparisonLine?.split(
            whereSeparator: \.isWhitespace
        )
        let comparisonRange = components?.first {
            $0.hasPrefix(linkPrefix)
        }?.split(
            separator: "/"
        ).last
        return comparisonRange.map(String.init)
    }

    func getTagBefore() async throws -> String? {
        let json = try await context.githubClient.reposListTags(
            path: .init(
                owner: repo.owner.login,
                repo: repo.name
            )
        ).ok.body.json

        if let releaseIdx = json.firstIndex(where: { $0.name == release.tagName }),
            json.count > releaseIdx
        {
            return json[releaseIdx + 1].name
        } else {
            logger.warning(
                "No previous tag found. Will just return the first tag",
                metadata: [
                    "tags": "\(json)",
                    "release": "\(release)",
                ]
            )
            return json.first?.name
        }
    }

    func getCommitsInRelease(comparisonRange: String) async throws -> [Commit] {
        try await context.githubClient.reposCompareCommits(
            path: .init(
                owner: repo.owner.login,
                repo: repo.name,
                basehead: comparisonRange
            )
        ).ok.body.json.commits.reversed()
    }

    func getAllCommits() async throws -> [Commit] {
        try await context.githubClient.reposListCommits(
            path: .init(
                owner: repo.owner.login,
                repo: repo.name
            )
        ).ok.body.json.reversed()
    }

    func getPRsRelatedToCommit(sha: String) async throws -> [SimplePullRequest] {
        try await context.githubClient.reposListPullRequestsAssociatedWithCommit(
            path: .init(
                owner: repo.owner.login,
                repo: repo.name,
                commitSha: sha
            )
        ).ok.body.json
    }

    func sendToDiscord(pr: SimplePullRequest) async throws {
        let body =
            pr.body.map { body -> String in
                body.trimmingReleaseNoticeFromBody().formatMarkdown(
                    maxVisualLength: 256,
                    hardLimit: 2_048,
                    trailingTextMinLength: 96
                )
            } ?? ""

        let description = try await context.renderClient.ticketReport(title: pr.title, body: body)

        try await sendToDiscord(description: description)
    }

    func sendToDiscord(prs: [SimplePullRequest], commitCount: Int) async throws {
        precondition(!prs.isEmpty)

        let prDescriptions = try prs.map {
            let user = try $0.user.requireValue()
            return "\($0.title) by [@\(user.uiName)](\(user.htmlUrl)) in [#\($0.number)](\($0.htmlUrl))"
        }.map {
            "- \($0)"
        }.joined(
            separator: "\n"
        )

        let commitCount = commitCount > 10 ? "More Than 10" : "\(commitCount)"

        let description = """
            ### \(commitCount) Changes, Including:

            \(prDescriptions)
            """.formatMarkdown(
                maxVisualLength: 256,
                hardLimit: 2_048,
                trailingTextMinLength: 96
            )
        try await sendToDiscord(description: description)
    }

    func sendToDiscordWithRelease() async throws {
        let description =
            release.body.map { body -> String in
                let preferredContent =
                    body.contentsOfHeading(
                        named: "What's Changed"
                    ) ?? body
                let formatted = preferredContent.formatMarkdown(
                    maxVisualLength: 256,
                    hardLimit: 2_048,
                    trailingTextMinLength: 96
                )
                return formatted.isEmpty ? "" : ">>> \(formatted)"
            } ?? ""

        try await sendToDiscord(description: description)
    }

    func sendToDiscord(description: String) async throws {
        let image = await findUseableImageLink()

        try await self.sendToDiscord(
            embed: .init(
                title: "[\(repo.uiName)] Release \(release.tagName)".unicodesPrefix(256),
                description: description,
                url: release.htmlUrl,
                color: .cyan,
                image: image.map { .init(url: .exact($0)) }
            )
        )
    }

    func findUseableImageLink() async -> String? {
        let fullName = repo.fullName.urlPathEncoded()
        func makeImageLink() -> String {
            "https://opengraph.githubassets.com/\(UUID().uuidString)/\(fullName)/releases/tag/\(release.tagName)"
        }

        /// Try a maximum of 3 times
        for _ in 0..<3 {
            let imageLink = makeImageLink()
            var request = HTTPClientRequest(url: imageLink)
            request.method = .HEAD
            do {
                let response = try await context.httpClient.execute(
                    request,
                    timeout: .seconds(1),
                    logger: logger
                )
                guard response.status == .ok else {
                    continue
                }
                return imageLink
            } catch {
                logger.warning(
                    "GitHub release image did not exist",
                    metadata: [
                        "imageLink": "\(imageLink)",
                        "error": "\(String(reflecting: error))",
                    ]
                )
            }
        }

        return nil
    }

    func sendToDiscord(embed: Embed) async throws {
        try await context.discordClient.createMessage(
            channelId: Constants.Channels.release.id,
            payload: .init(embeds: [embed])
        ).guardSuccess()
    }
}
