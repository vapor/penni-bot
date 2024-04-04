import DiscordBM
import Logging
import Models

struct MessageDeleteHandler {
    let context: HandlerContext
    var discordService: DiscordService {
        context.services.discordService
    }
    let logger = Logger(label: "MessageDeleteHandler")

    init(context: HandlerContext) {
        self.context = context
    }

    func handle(
        messageId: MessageSnowflake,
        in channelId: ChannelSnowflake
    ) async throws {
        guard let messageCreate = await discordService.getDeletedMessage(
            id: messageId,
            channelId: channelId
        ) else {
            logger.warning("Could not find a saved message for deleted message", metadata: [
                "messageId": .stringConvertible(messageId),
                "channelId": .stringConvertible(channelId)
            ])
            return
        }
        guard let author = messageCreate.author else {
            logger.error("Cannot find author of the message")
            return
        }
        await discordService.sendMessage(
            channelId: Constants.Channels.moderators.id,
            payload: .init(
                messageCreate: messageCreate,
                author: author
            )
        )
    }
}

extension Payloads.CreateMessage {
    init(
        messageCreate: Gateway.MessageCreate,
        author: DiscordUser
    ) {
        let member = messageCreate.member
        let avatarURL = member?.uiAvatarURL ?? author.uiAvatarURL
        let username = member?.uiName ?? author.username
        self.init(
            embeds: [.init(
                title: "Deleted Message",
                description: messageCreate.content,
                timestamp: messageCreate.timestamp.date,
                color: .red,
                footer: .init(
                    text: "From @\(username)",
                    icon_url: avatarURL.map { .exact($0) }
                ),
                fields: [
                    .init(
                        name: "Author",
                        value: DiscordUtils.mention(id: author.id),
                        inline: true
                    ),
                    .init(
                        name: "Author ID",
                        value: author.id.rawValue,
                        inline: true
                    ),
                    .init(
                        name: "Channel",
                        value: DiscordUtils.mention(id: messageCreate.channel_id),
                        inline: true
                    )
                ]
            )]
        )
    }
}
