import DiscordBM

struct EventHandler {
    let context: HandlerContext

    func handle() async throws {
        switch context.eventName {
        case .issues:
            try await IssueHandler(context: context).handle()
        case .pull_request:
            try await PRHandler(context: context).handle()
        case .ping:
            try await onPing()
        case .pull_request_review:
            break
        default:
            try await onDefault()
        }
    }

    func onPing() async throws {
        try await context.discordClient.createMessage(
            channelId: Constants.Channels.logs.id,
            payload: .init(embeds: [.init(
                title: "Ping events should not reach here",
                description: """
                Ping events must be handled immediately, even before any body-decoding happens.
                Action: \(context.event.action ?? "null")
                Repo: \(context.event.repository?.name ?? "null")
                """,
                color: .red
            )])
        ).guardSuccess()
    }

    func onDefault() async throws {
        try await context.discordClient.createMessage(
            channelId: Constants.Channels.logs.id,
            payload: .init(embeds: [.init(
                title: "Received UNHANDLED event \(context.eventName)",
                description: """
                Action: \(context.event.action ?? "null")
                Repo: \(context.event.repository?.name ?? "null")
                """,
                color: .red
            )])
        ).guardSuccess()
    }
}

extension String {
    func unicodesPrefix(_ maxUnicodeScalars: Int) -> String {
        /// Well, I mean, you _can_, but you won't like the resulting infinite loop!
        assert(maxUnicodeScalars >= 0, "Can request a negative maximum.")

        guard self.unicodeScalars.count > maxUnicodeScalars else {
            return self
        }

        let newMaxUnicodeScalars = maxUnicodeScalars - 3
        let needsDots = newMaxUnicodeScalars >= 0
        /// `-3` because we'll append `...` to the string.
        let maxUnicodeScalars = needsDots ? newMaxUnicodeScalars : maxUnicodeScalars

        /// Take a prefix of the string (i.e. a sequence of extended grapheme clusters) first.
        /// Most of the time, this will already be short enough.
        var trimmed = self.prefix(maxUnicodeScalars)

        /// If the result still has too many unicode scalars, there're one or more grapheme
        /// clusters in the string. Keep dropping extended grapheme clusters off the end (which
        /// with `String` is as easy as just removing the last `Character`) until we're within
        /// bounds. Worst-case complexity is `O(n)`.
        while trimmed.unicodeScalars.count > maxUnicodeScalars {
            trimmed.removeLast()
        }

        let dots = needsDots ? "..." : ""
        return "\(trimmed)\(dots)"
    }
}
