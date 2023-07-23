@testable import Penny
import DiscordModels
import Models

public struct FakeCoinService: CoinService {
    
    public init() { }
    
    public func postCoin(with coinRequest: CoinRequest.DiscordCoinEntry) async throws -> CoinResponse {
        CoinResponse(
            sender: coinRequest.fromDiscordID,
            receiver: coinRequest.toDiscordID,
            newCoinCount: coinRequest.amount + .random(in: 0..<10_000)
        )
    }
    
    public func getCoinCount(of discordID: UserSnowflake) async throws -> Int {
        2591
    }

    public func getGitHubName(of discordID: UserSnowflake) async throws -> GitHubUserResponse {
        .userName("fake-username")
    }
}
