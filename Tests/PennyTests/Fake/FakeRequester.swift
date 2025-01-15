import AsyncHTTPClient
import Logging

@testable import GHHooksLambda

struct FakeRequester: GenericRequester {
    var httpClient: HTTPClient = .shared
    var logger: Logger = .init(label: "FakeRequester")

    func getDiscordMember(githubID: String) async throws -> GuildMember? {
        switch githubID {
        case "54685446":
            return .init(
                uiName: "MahdiBM",
                userId: "290483761559240704"
            )
        case "69189821":
            return .init(
                uiName: "Paul",
                userId: "409376125995974666"
            )
        case "1130717":
            return .init(
                uiName: "Gwynne",
                userId: "684888401719459858"
            )
        case "9938337":
            return .init(
                uiName: "0xTim",
                userId: "432065887202181142"
            )
        /// Explicitly add github user ids with no registered discord member to here:
        case "11927376", "3184228", "27312159", "624238", "49933115", "31141451", "54376466", "49699333":
            return nil
        default:
            fatalError("Unhandled githubID: \(githubID)")
        }
    }
}
