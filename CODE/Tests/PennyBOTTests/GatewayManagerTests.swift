@testable import PennyBOT
@testable import DiscordBM
import XCTest

class GatewayManagerTests: XCTestCase {
    
    let manager = MockedManager.shared
    
    override func setUp() async throws {
        Penny.makeBot = { _, _ in MockedManager.shared }
        try await Penny.main()
    }
    
    func testSomething() async throws {
        let event = try! JSONDecoder().decode(
            Gateway.Event.self,
            from: Data(messageText.utf8)
        )
        await manager.send(event: event)
    }
}

private let messageText = """
{
        "t": "MESSAGE_CREATE",
        "s": 54,
        "op": 0,
        "d": {
            "type": 0,
            "tts": false,
            "timestamp": "2022-10-12T06:12:54.114000+00:00",
            "referenced_message": null,
            "pinned": false,
            "nonce": "1029637767555973120",
            "mentions": [
                {
                    "username": "Penny",
                    "public_flags": 0,
                    "member": {
                        "roles": [
                            "950719637044207689",
                            "441346871651336193"
                        ],
                        "premium_since": null,
                        "pending": false,
                        "nick": null,
                        "mute": false,
                        "joined_at": "2022-03-08T11:40:25.028000+00:00",
                        "flags": 0,
                        "deaf": false,
                        "communication_disabled_until": null,
                        "avatar": null
                    },
                    "id": "950695294906007573",
                    "discriminator": "9194",
                    "bot": true,
                    "avatar_decoration": null,
                    "avatar": "a3a7e4c4ded91fc9b2bf71a77ae68367"
                }
            ],
            "mention_roles": [],
            "mention_everyone": false,
            "member": {
                "roles": [
                    "431920712505098240"
                ],
                "premium_since": null,
                "pending": false,
                "nick": null,
                "mute": false,
                "joined_at": "2020-04-07T20:49:57.563000+00:00",
                "flags": 0,
                "deaf": false,
                "communication_disabled_until": null,
                "avatar": null
            },
            "id": "1029637770005717042",
            "flags": 0,
            "embeds": [],
            "edited_timestamp": null,
            "content": "<@950695294906007573> thank you, nice job!",
            "components": [],
            "channel_id": "441327731486097429",
            "author": {
                "username": "Mahdi BM",
                "public_flags": 0,
                "id": "290483761559240704",
                "discriminator": "0517",
                "avatar_decoration": null,
                "avatar": "2df0a0198e00ba23bf2dc728c4db94d9"
            },
            "attachments": [],
            "guild_id": "431917998102675485"
        }
    }
"""
