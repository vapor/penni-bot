import PennyModels

public protocol UserRepository {
    
    // MARK: - Insert
    func insertUser(_ user: DynamoDBUser, coinEntry: CoinEntry) async throws
    func updateUser(_ user: DynamoDBUser, coinEntry: CoinEntry) async throws
    
    // MARK: - Retrieve
    
    /// Returns nil if user does not exist.
    func getUser(discord id: String) async throws -> User?
    /// Returns nil if user does not exist.
    func getUser(github id: String) async throws -> User?
    
    // MARK: - Link users
    func linkGithub(with discordId: String, _ githubId: String) async throws -> String
    func linkDiscord(with githubId: String, _ discordId: String) async throws -> String
}
