@testable import PennyBOT
@testable import DiscordModels
import DiscordGateway
import PennyLambdaAddCoins
import PennyRepositories
import Fake
import PennyModels
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
        RepositoryFactory.makeHelpsRepository = { _ in FakeHelpsRepository() }
        Constants.apiBaseUrl = "https://fake.com"
        ServiceFactory.makeCoinService = { FakeCoinService() }
        ServiceFactory.makePingsService = { FakePingsService() }
        ServiceFactory.makeHelpsService = { FakeHelpsService() }
        ServiceFactory.makeProposalsService = { _ in FakeProposalsService() }
        await ProposalsChecker.shared._tests_setPreviousProposals(to: TestData.proposals)
        /// So the proposals are send as soon as they're queued, in tests.
        await ProposalsChecker.shared._tests_setQueuedProposalsWaitTime(to: -1)
        // reset the storage
        FakeResponseStorage.shared = FakeResponseStorage()
        ReactionCache._tests_reset()
        self.manager = FakeManager()
        DiscordFactory.makeBot = { _, _ in self.manager! }
        DiscordFactory.makeCache = {
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
        Task { try await Penny.main() }
        await manager.waitUntilConnected()
    }
    
    func testCommandsRegisterOnStartup() async throws {
        let response = await responseStorage.awaitResponse(
            at: .bulkSetApplicationCommands(applicationId: "11111111")
        ).value
        
        let commandNames = SlashCommand.allCases.map(\.rawValue)
        let commands = try XCTUnwrap(response as? [Payloads.ApplicationCommandCreate])
        XCTAssertEqual(commands.map(\.name).sorted(), commandNames.sorted())
    }
    
    func testMessageHandler() async throws {
        let response = try await manager.sendAndAwaitResponse(
            key: .thanksMessage,
            as: Payloads.CreateMessage.self
        )
        
        let description = try XCTUnwrap(response.embeds?.first?.description)
        XCTAssertTrue(description.hasPrefix("<@950695294906007573> now has "))
        XCTAssertTrue(description.hasSuffix(" \(Constants.ServerEmojis.coin.emoji)!"))
    }
    
    func testLinkCommand() async throws {
        let response = try await self.manager.sendAndAwaitResponse(
            key: .linkInteraction,
            as: Payloads.EditWebhookMessage.self
        )
        let description = try XCTUnwrap(response.embeds?.first?.description)
        XCTAssertEqual(description, "This command is still a WIP. Linking Discord with Discord ID '9123813923'")
    }
    
    func testReactionHandler() async throws {
        do {
            let response = try await manager.sendAndAwaitResponse(
                key: .thanksReaction,
                as: Payloads.CreateMessage.self
            )
            
            let description = try XCTUnwrap(response.embeds?.first?.description)
            XCTAssertTrue(description.hasPrefix(
                "Mahdi BM gave a \(Constants.ServerEmojis.coin.emoji) to <@1030118727418646629>, who now has "
            ))
            XCTAssertTrue(description.hasSuffix(" \(Constants.ServerEmojis.coin.emoji)!"))
        }
        
        // For consistency with `testReactionHandler2()`
        try await Task.sleep(for: .seconds(1))
        
        // The second thanks message should just edit the last one, because the
        // receiver is the same person and the channel is the same channel.
        do {
            let response = try await manager.sendAndAwaitResponse(
                key: .thanksReaction2,
                as: Payloads.EditMessage.self
            )
            
            let description = try XCTUnwrap(response.embeds?.first?.description)
            XCTAssertTrue(description.hasPrefix(
                "Mahdi BM & 0xTim gave 2 \(Constants.ServerEmojis.coin.emoji) to <@1030118727418646629>, who now has "
            ))
            XCTAssertTrue(description.hasSuffix(" \(Constants.ServerEmojis.coin.emoji)!"))
        }
    }
    
    func testReactionHandler3() async throws {
        do {
            let response = try await manager.sendAndAwaitResponse(
                key: .thanksReaction3,
                as: Payloads.CreateMessage.self
            )
            
            let description = try XCTUnwrap(response.embeds?.first?.description)
            XCTAssertTrue(description.hasPrefix("""
            0xTim gave a \(Constants.ServerEmojis.coin.emoji) to <@1030118727418646629>, who now has
            """), description)
            XCTAssertTrue(description.hasSuffix("""
            \(Constants.ServerEmojis.coin.emoji)! (https://discord.com/channels/431917998102675485/431926479752921098/1031112115928442034)
            """), description)
        }
        
        // We need to wait a little bit to make sure Discord's response
        // is decoded and is used-in/added-to the `ReactionCache`.
        // This would happen in a real-world situation too.
        try await Task.sleep(for: .seconds(1))
        
        // The second thanks message should edit the last one.
        do {
            let response = try await manager.sendAndAwaitResponse(
                key: .thanksReaction4,
                as: Payloads.EditMessage.self
            )
            
            let description = try XCTUnwrap(response.embeds?.first?.description)
            XCTAssertTrue(description.hasPrefix("""
            0xTim & Mahdi BM gave 2 \(Constants.ServerEmojis.coin.emoji) to <@1030118727418646629>, who now has
            """), description)
            XCTAssertTrue(description.hasSuffix("""
            \(Constants.ServerEmojis.coin.emoji)! (https://discord.com/channels/431917998102675485/431926479752921098/1031112115928442034)
            """))
        }
    }
    
    func testRespondsInThanksChannelWhenDoesNotHavePermission() async throws {
        let response = try await manager.sendAndAwaitResponse(
            key: .thanksMessage2,
            as: Payloads.CreateMessage.self
        )
        
        let description = try XCTUnwrap(response.embeds?.first?.description)

        XCTAssertTrue(description.hasPrefix("<@950695294906007573> now has "))
        XCTAssertTrue(description.hasSuffix("""
        \(Constants.ServerEmojis.coin.emoji)! (https://discord.com/channels/431917998102675485/431917998102675487/1029637770005717042)
        """))
    }
    
    func testBotStateManagerSendsSignalOnStartUp() async throws {
        let canRespond = await stateManager.canRespond
        XCTAssertEqual(canRespond, true)
        
        let response = await responseStorage.awaitResponse(
            at: .createMessage(channelId: Constants.Channels.logs.id)
        ).value
        
        let message = try XCTUnwrap(response as? Payloads.CreateMessage)
        XCTAssertGreaterThan(message.content?.count ?? -1, 20)
    }
    
    func testBotStateManagerReceivesSignal() async throws {
        await stateManager._tests_setDisableDuration(to: .seconds(3))
        
        let response = try await manager.sendAndAwaitResponse(
            key: .stopRespondingToMessages,
            as: Payloads.CreateMessage.self
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
            responseStorage.awaitResponse(at: createDMEndpoint).value,
            responseStorage.awaitResponse(at: responseEndpoint).value,
            responseStorage.awaitResponse(at: responseEndpoint).value
        )
        
        let recipients: [UserSnowflake] = ["950695294906007573", "432065887202181142"]
        
        do {
            let dmPayload = try XCTUnwrap(createDM1 as? Payloads.CreateDM, "\(createDM1)")
            XCTAssertTrue(recipients.contains(dmPayload.recipient_id), "\(dmPayload.recipient_id)")
        }
        
        let dmMessage1 = try XCTUnwrap(sendDM1 as? Payloads.CreateMessage, "\(sendDM1)")
        let message1 = try XCTUnwrap(dmMessage1.embeds?.first?.description)
        XCTAssertTrue(message1.hasPrefix("There is a new message"), message1)
        /// Check to make sure the expected ping-words are mentioned in the message
        XCTAssertTrue(message1.contains("- mongodb driver"), message1)
        
        do {
            /// These two must not fail. The user does not have any
            /// significant roles but they still should receive the pings.
            let dmPayload = try XCTUnwrap(createDM2 as? Payloads.CreateDM, "\(createDM1)")
            XCTAssertTrue(recipients.contains(dmPayload.recipient_id), "\(dmPayload.recipient_id)")
        }
        
        let dmMessage2 = try XCTUnwrap(sendDM2 as? Payloads.CreateMessage, "\(sendDM1)")
        let message2 = try XCTUnwrap(dmMessage2.embeds?.first?.description)
        XCTAssertTrue(message2.hasPrefix("There is a new message"), message2)
        /// Check to make sure the expected ping-words are mentioned in the message
        XCTAssertTrue(message2.contains("- mongodb driver"), message2)
        
        /// Contains `godb dr` (part of `mongodb driver`).
        /// Tests `Expression.contain("godb dr")`.
        XCTAssertTrue(
            [message1, message2].contains(where: { $0.contains("- godb dr") }),
            #"None of the 2 payloads contained "godb dr". Messages: \#([message1, message2]))"#
        )
        
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
            let dmMessage = try XCTUnwrap(sendDM as? Payloads.CreateMessage, "\(sendDM)")
            let message = try XCTUnwrap(dmMessage.embeds?.first?.description)
            XCTAssertTrue(message.hasPrefix("There is a new message"), message)
            /// Check to make sure the expected ping-words are mentioned in the message
            XCTAssertTrue(message.contains("- blog"), message)
            XCTAssertTrue(message.contains("- discord"), message)
            XCTAssertTrue(message.contains("- discord-kit"), message)
            XCTAssertTrue(message.contains("- cord"), message)
        }
    }
    
    func testHowManyCoins() async throws {
        do {
            let response = try await manager.sendAndAwaitResponse(
                key: .howManyCoins1,
                as: Payloads.EditWebhookMessage.self
            )
            let message = try XCTUnwrap(response.embeds?.first?.description)
            XCTAssertEqual(message, "<@290483761559240704> has 2591 \(Constants.ServerEmojis.coin.emoji)!")
        }
        
        do {
            let response = try await manager.sendAndAwaitResponse(
                key: .howManyCoins2,
                as: Payloads.EditWebhookMessage.self
            )
            let message = try XCTUnwrap(response.embeds?.first?.description)
            XCTAssertEqual(message, "<@961607141037326386> has 2591 \(Constants.ServerEmojis.coin.emoji)!")
        }
    }
    
    func testServerBoostCoins() async throws {
        let response = try await manager.sendAndAwaitResponse(
            key: .serverBoost,
            as: Payloads.CreateMessage.self
        )
        let message = try XCTUnwrap(response.embeds?.first?.description)
        XCTAssertTrue(
            message.hasPrefix(
                """
                <@432065887202181142> Thanks for the Server Boost \(Constants.ServerEmojis.love.emoji)!
                You now have 10 more \(Constants.ServerEmojis.coin.emoji) for a total of
                """
            )
        )
        XCTAssertTrue(message.hasSuffix(" \(Constants.ServerEmojis.coin.emoji)!"))
    }

    func testProposalsChecker() async throws {
        let endpoint = APIEndpoint.createMessage(channelId: Constants.Channels.proposals.id)
        let (message1, message2) = await (
            responseStorage.awaitResponse(at: endpoint).value,
            responseStorage.awaitResponse(at: endpoint).value
        )

        /// New proposal message
        do {
            let message = try XCTUnwrap(message1 as? Payloads.CreateMessage, "\(message1)")

            let buttons = try XCTUnwrap(message.components?.first?.components)
            XCTAssertEqual(buttons.count, 3, "\(buttons)")
            let expectedLinks = [
                "https://github.com/apple/swift-evolution/blob/main/proposals/0051-stride-semantics.md",
                "https://forums.swift.org/t/se-0400-init-accessors/65583",
                "https://forums.swift.org/search?q=Conventionalizing%20stride%20semantics%20%23evolution"
            ]
            for (idx, buttonComponent) in buttons.enumerated() {
                if case let .button(button) = buttonComponent,
                   let url = button.url {
                    XCTAssertEqual(expectedLinks[idx], url)
                } else {
                    XCTFail("\(buttonComponent) was not a button")
                }
            }

            let embed = try XCTUnwrap(message.embeds?.first)
            XCTAssertEqual(embed.title, "[SE-0051] Withdrawn: Conventionalizing stride semantics")
            XCTAssertEqual(embed.description, "> \n\n**Status: Withdrawn**\n\n**Authors:** [Erica Sadun](http://github.com/erica)\n")
            XCTAssertEqual(embed.color, .brown)
        }

        /// Updated proposal message
        do {
            let message = try XCTUnwrap(message2 as? Payloads.CreateMessage, "\(message2)")

            let buttons = try XCTUnwrap(message.components?.first?.components)
            XCTAssertEqual(buttons.count, 3, "\(buttons)")
            let expectedLinks = [
                "https://github.com/apple/swift-evolution/blob/main/proposals/0001-keywords-as-argument-labels.md",
                "https://forums.swift.org/t/se-0400-init-accessors/65583",
                "https://forums.swift.org/search?q=Allow%20(most)%20keywords%20as%20argument%20labels%20%23evolution"
            ]
            for (idx, buttonComponent) in buttons.enumerated() {
                if case let .button(button) = buttonComponent,
                   let url = button.url {
                    XCTAssertEqual(expectedLinks[idx], url)
                } else {
                    XCTFail("\(buttonComponent) was not a button")
                }
            }


            let embed = try XCTUnwrap(message.embeds?.first)
            XCTAssertEqual(embed.title, "[SE-0001] In Active Review: Allow (most) keywords as argument labels")
            XCTAssertEqual(embed.description, "> Argument labels are an important part of the interface of a Swift function, describing what particular arguments to the function do and improving readability. Sometimes, the most natural label for an argument coincides with a language keyword, such as `in`, `repeat`, or `defer`. Such keywords should be allowed as argument labels, allowing better expression of these interfaces.\n\n**Status:** Implemented -> **Active Review**\n\n**Authors:** [Doug Gregor](https://github.com/DougGregor)\n")
            XCTAssertEqual(embed.color, .orange)
        }
    }

    func testHelpsCommand() async throws {
        do {
            let response = try await manager.sendAndAwaitResponse(
                key: .helpsAdd,
                as: Payloads.InteractionResponse.self
            )
            switch response.data {
            case .modal: break
            default:
                XCTFail("Wrong response data type for `/help add`: \(response.data as Any)")
            }
        }

        do {
            let response = try await manager.sendAndAwaitResponse(
                key: .helpsAddFailure,
                as: Payloads.EditWebhookMessage.self
            )
            let message = try XCTUnwrap(response.embeds?.first?.description)
            XCTAssertTrue(message.hasPrefix("You don't have access level for this command. This command is only available to"), message)
        }

        do {
            let response = try await manager.sendAndAwaitResponse(
                key: .helpsGet,
                as: Payloads.EditWebhookMessage.self
            )
            let message = try XCTUnwrap(response.embeds?.first?.description)
            XCTAssertEqual(message, "Test working directory help")
        }

        do {
            let response = try await manager.sendAndAwaitResponse(
                key: .helpsGetAutocomplete,
                as: Payloads.InteractionResponse.self
            )
            switch response.data {
            case .autocomplete: break
            default:
                XCTFail("Wrong response data type for `/help get`: \(response.data as Any)")
            }
        }
    }
}

private extension DiscordTimestamp {
    static let fake: DiscordTimestamp = {
        let string = #""2022-11-23T09:59:04.037259+00:00""#
        let data = Data(string.utf8)
        return try! JSONDecoder().decode(DiscordTimestamp.self, from: data)
    }()
    
    static let inFutureFake: DiscordTimestamp = {
        let string = #""2100-11-23T09:59:04.037259+00:00""#
        let data = Data(string.utf8)
        return try! JSONDecoder().decode(DiscordTimestamp.self, from: data)
    }()
}
