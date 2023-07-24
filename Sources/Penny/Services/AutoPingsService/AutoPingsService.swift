import Models
import DiscordBM
import AsyncHTTPClient

protocol AutoPingsService: Sendable {
    typealias Expression = S3AutoPingItems.Expression
    func initialize(httpClient: HTTPClient) async
    func exists(expression: Expression, forDiscordID id: UserSnowflake) async throws -> Bool
    func insert(_ expressions: [Expression], forDiscordID id: UserSnowflake) async throws
    func remove(_ expressions: [Expression], forDiscordID id: UserSnowflake) async throws
    func get(discordID id: UserSnowflake) async throws -> [Expression]
    func getExpression(hash: Int) async throws -> Expression?
    func getAll() async throws -> S3AutoPingItems
}
