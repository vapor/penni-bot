import DiscordBM
import Logging

struct InteractionHandler {
    var logger = Logger(label: "InteractionHandler")
    let event: Interaction
    var pingsService: AutoPingsService {
        ServiceFactory.makePingsService()
    }
    
    init(event: Interaction) {
        self.event = event
        self.logger[metadataKey: "event"] = "\(event)"
    }
    
    func handle() async {
        guard let kind = SlashCommandKind(name: event.data?.name) else {
            logger.error("Unrecognized command")
            return await sendInteractionNameResolveFailure()
        }
        guard await sendInteractionAcknowledgement(isEphemeral: kind.isEphemeral) else { return }
        let response = await processAndMakeResponse(kind: kind)
        await respond(with: response)
    }
    
    private func processAndMakeResponse(kind: SlashCommandKind) async -> String {
        let options = event.data?.options ?? []
        switch kind {
        case .link: return handleLinkCommand(options: options)
        case .automatedPings: return await handlePingsCommand(options: options)
        }
    }
    
    func handleLinkCommand(options: [Interaction.Data.Option]) -> String {
        if options.isEmpty {
            logger.error("Discord did not send required info")
            return "Please provide more options"
        }
        let first = options[0]
        guard let id = first.options?.first?.value?.asString else {
            logger.error("Discord did not send required info")
            return "No ID option recognized"
        }
        switch first.name {
        case "discord":
            return "This command is still a WIP. Linking Discord with Discord ID \(id)"
        case "github":
            return "This command is still a WIP. Linking Discord with Github ID \(id)"
        case "slack":
            return "This command is still a WIP. Linking Discord with Slack ID \(id)"
        default:
            logger.error("Unrecognized link option", metadata: ["name": "\(first.name)"])
            return "Option not recognized: \(first.name)"
        }
    }
    
    func handlePingsCommand(options: [Interaction.Data.Option]) async -> String {
        guard let member = event.member else {
            logger.error("Discord did not send required info")
            return "Sorry something went wrong :("
        }
        guard await DiscordService.shared.memberHasAnyTechnicalRoles(member: member) else {
            logger.warning("Someone tried to use 'automated-pings' but they don't have any of the required roles")
            let rolesString = Constants.TechnicalRoles.allCases.map {
                DiscordUtils.roleMention(id: $0.rawValue)
            }.joined(separator: " ")
            return "Sorry, this functionality is currently restricted to members with any of these roles, to make sure Penny can handle the load: \(rolesString)"
        }
        if options.isEmpty {
            logger.error("Discord did not send required interaction info")
            return "Please provide more options"
        }
        guard let _id = (event.member?.user ?? event.user)?.id else {
            logger.error("Can't find a user's id")
            return "Sorry something went wrong :("
        }
        let discordId = "<@\(_id)>"
        let first = options[0]
        do {
            switch first.name {
            case "add":
                guard let option = first.options?.first,
                      let text = option.value?.asString else {
                    logger.error("Discord did not send required info")
                    return "No 'text' option recognized"
                }
                if text.unicodeScalars.count < 3 {
                    return "The text is less than 3 letters. This is not acceptable"
                }
                try await pingsService.insert([text.foldForPingCommand()], forDiscordID: discordId)
                return "Successfully added `\(text)` to your pings list"
            case "bulk-add":
                guard let option = first.options?.first,
                      let _text = option.value?.asString else {
                    logger.error("Discord did not send required info")
                    return "No 'text' option recognized"
                }
                let texts = _text.split(separator: ",")
                    .map(String.init)
                    .map({ $0.foldForPingCommand() })
                if texts.contains(where: { $0.unicodeScalars.count < 3 }) {
                    return "One of the texts is less than 3 letters. This is not acceptable"
                }
                try await pingsService.insert(texts, forDiscordID: discordId)
                let textsList = texts.map({ "`\($0)`" }).joined(separator: "\n")
                return """
                Successfully added
                \(textsList)
                to your pings list
                """
            case "remove":
                guard let option = first.options?.first,
                      let text = option.value?.asString else {
                    logger.error("Discord did not send required info")
                    return "No 'text' option recognized"
                }
                try await pingsService.remove([text.foldForPingCommand()], forDiscordID: discordId)
                return "Successfully removed `\(text)` from your pings list"
            case "list":
                let list = try await pingsService
                    .get(discordID: discordId)
                    .enumerated().map { idx, text in
                        "**\(idx).** `\(text)`"
                    }.joined(separator: "\n")
                return list
            default:
                logger.error("Unrecognized link option", metadata: ["name": "\(first.name)"])
                return "Option not recognized: \(first.name)"
            }
        } catch {
            logger.error("Pings command error", metadata: ["error": "\(error)"])
            return "Sorry some errors happened :( please report this to us if it happens again"
        }
    }
    
    /// Returns `true` if the acknowledgement was successfully sent
    private func sendInteractionAcknowledgement(isEphemeral: Bool) async -> Bool {
        await DiscordService.shared.respondToInteraction(
            id: event.id,
            token: event.token,
            payload: .init(
                type: .deferredChannelMessageWithSource,
                data: isEphemeral ? .init(flags: [.ephemeral]) : nil
            )
        )
    }
    
    private func sendInteractionNameResolveFailure() async {
        await DiscordService.shared.respondToInteraction(
            id: event.id,
            token: event.token,
            payload: .init(
                type: .channelMessageWithSource,
                data: .init(embeds: [.init(
                    description: "Failed to resolve the interaction name :(",
                    color: .vaporPurple
                )], flags: [.ephemeral])
            )
        )
    }
    
    private func respond(with response: String) async {
        await DiscordService.shared.editInteraction(
            token: event.token,
            payload: .init(embeds: [.init(
                description: response,
                color: .vaporPurple
            )])
        )
    }
}

private enum SlashCommandKind {
    case link
    case automatedPings
    
    /// Ephemeral means the interaction will only be visible to the user, not the whole guild.
    var isEphemeral: Bool {
        switch self {
        case .link: return true
        case .automatedPings: return true
        }
    }
    
    init? (name: String?) {
        switch name {
        case "link": self = .link
        case "automated-pings": self = .automatedPings
        default: return nil
        }
    }
}
