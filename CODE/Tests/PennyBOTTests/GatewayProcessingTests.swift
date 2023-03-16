@testable import PennyBOT
@testable import DiscordModels
import DiscordGateway
import PennyLambdaAddCoins
import PennyRepositories
import Fake
import XCTest

class GatewayProcessingTests: XCTestCase {
    
    var stateManager: BotStateManager { .shared }
    var responseStorage: FakeResponseStorage { .shared }
    var manager: FakeManager!
    
    override func setUp() async throws {
        /// Fake webhook url
        Constants.loggingWebhookUrl = "https://discord.com/api/webhooks/106628736/dS7kgaOyaiZE5wl_"
        Constants.botToken = "afniasdfosdnfoasdifnasdffnpidsanfpiasdfipnsdfpsadfnspif"
        Constants.botId = "950695294906007573"
        RepositoryFactory.makeUserRepository = { _ in FakeUserRepository() }
        RepositoryFactory.makeAutoPingsRepository = { _ in FakePingsRepository() }
        Constants.apiBaseUrl = "https://fake.com"
        ServiceFactory.makePingsService = { FakePingsService() }
        ServiceFactory.makeCoinService = { _ in FakeCoinService() }
        // reset the storage
        FakeResponseStorage.shared = FakeResponseStorage()
        ReactionCache._tests_reset()
        self.manager = FakeManager()
        BotFactory.makeBot = { _, _ in self.manager! }
        BotFactory.makeCache = {
            var storage = DiscordCache.Storage()
            storage.guilds[TestData.vaporGuild.id] = TestData.vaporGuild
            return await DiscordCache(
                gatewayManager: $0,
                intents: [.guilds, .guildMembers],
                requestAllMembers: .enabled,
                storage: storage
            )
        }
        await stateManager._tests_reset()
        // Due to how `Penny.main()` works, sometimes `Penny.main()` exits before
        // the fake manager is ready. That's why we need to use `waitUntilConnected()`.
        await Penny.main()
        await manager.waitUntilConnected()
    }
    
    func testSlashCommandsRegisterOnStartup() async throws {
        let response = await responseStorage.awaitResponse(
            at: .bulkOverwriteGlobalApplicationCommands(appId: "11111111")
        ).value
        
        let commandNames = ["link", "auto-pings", "how-many-coins"]
        let commands = try XCTUnwrap(response as? [RequestBody.ApplicationCommandCreate])
        XCTAssertEqual(commands.map(\.name).sorted(), commandNames.sorted())
    }
    
    func testMessageHandler() async throws {
        let response = try await manager.sendAndAwaitResponse(
            key: .thanksMessage,
            as: RequestBody.CreateMessage.self
        )
        
        let description = try XCTUnwrap(response.embeds?.first?.description)
        XCTAssertTrue(description.hasPrefix("<@950695294906007573> now has "))
        XCTAssertTrue(description.hasSuffix(" \(Constants.vaporCoinEmoji)!"))
    }
    
    func testInteractionHandler() async throws {
        let response = try await self.manager.sendAndAwaitResponse(
            key: .linkInteraction,
            as: RequestBody.InteractionResponse.CallbackData.self
        )
        
        let description = try XCTUnwrap(response.embeds?.first?.description)
        XCTAssertEqual(description, "This command is still a WIP. Linking Discord with Discord ID 9123813923")
    }
    
    func testReactionHandler() async throws {
        do {
            let response = try await manager.sendAndAwaitResponse(
                key: .thanksReaction,
                as: RequestBody.CreateMessage.self
            )
            
            let description = try XCTUnwrap(response.embeds?.first?.description)
            XCTAssertTrue(description.hasPrefix(
                "Mahdi BM gave a \(Constants.vaporCoinEmoji) to <@1030118727418646629>, who now has "
            ))
            XCTAssertTrue(description.hasSuffix(" \(Constants.vaporCoinEmoji)!"))
        }
        
        // For consistency with `testReactionHandler2()`
        try await Task.sleep(for: .seconds(1))
        
        // The second thanks message should just edit the last one, because the
        // receiver is the same person and the channel is the same channel.
        do {
            let response = try await manager.sendAndAwaitResponse(
                key: .thanksReaction2,
                as: RequestBody.EditMessage.self
            )
            
            let description = try XCTUnwrap(response.embeds?.first?.description)
            XCTAssertTrue(description.hasPrefix(
                "Mahdi BM & 0xTim gave 2 \(Constants.vaporCoinEmoji) to <@1030118727418646629>, who now has "
            ))
            XCTAssertTrue(description.hasSuffix(" \(Constants.vaporCoinEmoji)!"))
        }
    }
    
    func testReactionHandler2() async throws {
        do {
            let response = try await manager.sendAndAwaitResponse(
                key: .thanksReaction,
                as: RequestBody.CreateMessage.self
            )
            
            let description = try XCTUnwrap(response.embeds?.first?.description)
            XCTAssertTrue(description.hasPrefix(
                "Mahdi BM gave a \(Constants.vaporCoinEmoji) to <@1030118727418646629>, who now has "
            ))
            XCTAssertTrue(description.hasSuffix(" \(Constants.vaporCoinEmoji)!"))
        }
        
        // We need to wait a little bit to make sure Discord's response
        // is decoded and is used-in/added-to the `ReactionCache`.
        // This would happen in a real-world situation too.
        try await Task.sleep(for: .seconds(1))
        
        // Tell `ReactionCache` that someone sent a new message
        // in the same channel that the reaction happened.
        await ReactionCache.shared.invalidateCachesIfNeeded(
            event: .init(
                id: "1313",
                /// Based on how the function works right now, only `channel_id` matters
                channel_id: "684159753189982218",
                content: "",
                timestamp: .fake,
                tts: false,
                mention_everyone: false,
                mention_roles: [],
                attachments: [],
                embeds: [],
                pinned: false,
                type: .default,
                mentions: []
            )
        )
        
        // The second thanks message should NOT edit the last one, because although the
        // receiver is the same person and the channel is the same channel, Penny's message
        // is not the last message anymore.
        do {
            let response = try await manager.sendAndAwaitResponse(
                key: .thanksReaction2,
                endpoint: EventKey.thanksReaction.responseEndpoints[0],
                as: RequestBody.CreateMessage.self
            )
            
            let description = try XCTUnwrap(response.embeds?.first?.description)
            XCTAssertTrue(description.hasPrefix(
                "0xTim gave a \(Constants.vaporCoinEmoji) to <@1030118727418646629>, who now has "
            ))
            XCTAssertTrue(description.hasSuffix(" \(Constants.vaporCoinEmoji)!"))
        }
    }
    
    func testReactionHandler3() async throws {
        do {
            let response = try await manager.sendAndAwaitResponse(
                key: .thanksReaction3,
                as: RequestBody.CreateMessage.self
            )
            
            let description = try XCTUnwrap(response.embeds?.first?.description)
            XCTAssertTrue(description.hasPrefix("""
            https://discord.com/channels/431917998102675485/431926479752921098/1031112115928442034
            0xTim gave a \(Constants.vaporCoinEmoji) to <@1030118727418646629>, who now has
            """
                                               ), description)
            XCTAssertTrue(description.hasSuffix(" \(Constants.vaporCoinEmoji)!"))
        }
        
        // We need to wait a little bit to make sure Discord's response
        // is decoded and is used-in/added-to the `ReactionCache`.
        // This would happen in a real-world situation too.
        try await Task.sleep(for: .seconds(1))
        
        // The second thanks message should edit the last one.
        do {
            let response = try await manager.sendAndAwaitResponse(
                key: .thanksReaction4,
                as: RequestBody.EditMessage.self
            )
            
            let description = try XCTUnwrap(response.embeds?.first?.description)
            XCTAssertTrue(description.hasPrefix("""
            https://discord.com/channels/431917998102675485/431926479752921098/1031112115928442034
            0xTim & Mahdi BM gave 2 \(Constants.vaporCoinEmoji) to <@1030118727418646629>, who now has
            """
                                               ), description)
            XCTAssertTrue(description.hasSuffix(" \(Constants.vaporCoinEmoji)!"))
        }
    }
    
    func testRespondsInThanksChannelWhenDoesNotHavePermission() async throws {
        let response = try await manager.sendAndAwaitResponse(
            key: .thanksMessage2,
            as: RequestBody.CreateMessage.self
        )
        
        let description = try XCTUnwrap(response.embeds?.first?.description)
        let lines = description.split(whereSeparator: \.isNewline)
        
        let line1 = try XCTUnwrap(lines.first)
        XCTAssertEqual(line1, "https://discord.com/channels/431917998102675485/431917998102675487/1029637770005717042")
        
        let line2 = try XCTUnwrap(lines.last)
        XCTAssertTrue(line2.hasPrefix("<@950695294906007573> now has "))
        XCTAssertTrue(line2.hasSuffix(" \(Constants.vaporCoinEmoji)!"))
    }
    
    func testBotStateManagerSendsSignalOnStartUp() async throws {
        let canRespond = await stateManager.canRespond
        XCTAssertEqual(canRespond, true)
        
        let response = await responseStorage.awaitResponse(
            at: .createMessage(channelId: Constants.logsChannelId)
        ).value
        
        let message = try XCTUnwrap(response as? RequestBody.CreateMessage)
        XCTAssertGreaterThan(message.content?.count ?? -1, 20)
    }
    
    func testBotStateManagerReceivesSignal() async throws {
        await stateManager._tests_setDisableDuration(to: .seconds(3))
        
        let response = try await manager.sendAndAwaitResponse(
            key: .stopRespondingToMessages,
            as: RequestBody.CreateMessage.self
        )
        
        XCTAssertGreaterThan(response.content?.count ?? -1, 20)
        
        // Wait to make sure BotStateManager has had enough time to process
        try await Task.sleep(for: .milliseconds(800))
        let testEvent = Gateway.Event(opcode: .dispatch)
        do {
            let canRespond = await stateManager.canRespond(to: testEvent)
            XCTAssertEqual(canRespond, false)
        }
        
        // After 3 seconds, the state manager should allow responses again, because
        // `BotStateManager.disableDuration` has already been passed
        try await Task.sleep(for: .milliseconds(2600))
        do {
            let canRespond = await stateManager.canRespond(to: testEvent)
            XCTAssertEqual(canRespond, true)
        }
    }
    
    func testAutoPings() async throws {
        let event = EventKey.autoPingsTrigger
        await manager.send(key: event)
        let createDMEndpoint = event.responseEndpoints[0]
        let responseEndpoint = event.responseEndpoints[1]
        let (createDM1, createDM2, sendDM1, sendDM2) = await (
            responseStorage.awaitResponse(at: createDMEndpoint).value,
            responseStorage.awaitResponse(at: createDMEndpoint, expectFailure: true).value,
            responseStorage.awaitResponse(at: responseEndpoint).value,
            responseStorage.awaitResponse(at: responseEndpoint, expectFailure: true).value
        )
        
        let recipients = ["950695294906007573", "432065887202181142"]
        
        do {
            let dmPayload = try XCTUnwrap(createDM1 as? RequestBody.CreateDM, "\(createDM1)")
            XCTAssertTrue(recipients.contains(dmPayload.recipient_id), dmPayload.recipient_id)
        }
        
        do {
            let dmMessage = try XCTUnwrap(sendDM1 as? RequestBody.CreateMessage, "\(sendDM1)")
            let message = try XCTUnwrap(dmMessage.embeds?.first?.description)
            XCTAssertTrue(message.hasPrefix("There is a new message"), message)
            /// Check to make sure the expected ping-words are mentioned in the message
            XCTAssertTrue(message.contains("mongodb driver"), message)
        }
        
        do {
            /// These two must fail because user does not have enough permissions to receive pings
            let payload1: Never? = try XCTUnwrap(createDM2 as? Optional<Never>)
            XCTAssertEqual(payload1, .none)
            let payload2: Never? = try XCTUnwrap(sendDM2 as? Optional<Never>)
            XCTAssertEqual(payload2, .none)
        }
        
        let event2 = EventKey.autoPingsTrigger2
        let createDMEndpoint2 = event2.responseEndpoints[0]
        let responseEndpoint2 = event2.responseEndpoints[1]
        await manager.send(key: event2)
        let (createDM, sendDM) = await (
            responseStorage.awaitResponse(at: createDMEndpoint2, expectFailure: true).value,
            responseStorage.awaitResponse(at: responseEndpoint2).value
        )
        
        /// The DM channel has already been created for the last tests,
        /// so should not be created again since it should have been cached.
        do {
            let payload: Never? = try XCTUnwrap(createDM as? Optional<Never>)
            XCTAssertEqual(payload, .none)
        }
        
        do {
            let dmMessage = try XCTUnwrap(sendDM as? RequestBody.CreateMessage, "\(sendDM)")
            let message = try XCTUnwrap(dmMessage.embeds?.first?.description)
            XCTAssertTrue(message.hasPrefix("There is a new message"), message)
            /// Check to make sure the expected ping-words are mentioned in the message
            XCTAssertTrue(message.contains("blog"), message)
            XCTAssertTrue(message.contains("discord"), message)
            XCTAssertTrue(message.contains("discord-kit"), message)
        }
    }
    
    func testHowManyCoins() async throws {
        do {
            let response = try await manager.sendAndAwaitResponse(
                key: .howManyCoins1,
                as: RequestBody.InteractionResponse.CallbackData.self
            )
            let message = try XCTUnwrap(response.embeds?.first?.description)
            XCTAssertEqual(message, "<@290483761559240704> has 2591 \(Constants.vaporCoinEmoji)")
        }
        
        do {
            let response = try await manager.sendAndAwaitResponse(
                key: .howManyCoins2,
                as: RequestBody.InteractionResponse.CallbackData.self
            )
            let message = try XCTUnwrap(response.embeds?.first?.description)
            XCTAssertEqual(message, "<@961607141037326386> has 2591 \(Constants.vaporCoinEmoji)")
        }
    }
}

private extension DiscordTimestamp {
    static let fake: DiscordTimestamp = {
        let string = #""2022-11-23T09:59:04.037259+00:00""#
        let data = Data(string.utf8)
        return try! JSONDecoder().decode(DiscordTimestamp.self, from: data)
    }()
}
