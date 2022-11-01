import Foundation
import SotoCore
import SotoDynamoDB
import PennyRepositories
import PennyModels

public struct UserService {
    
    public enum ServiceError: Error {
        case failedToUpdate
        case unimplemented(line: UInt = #line)
    }
    
    let logger: Logger
    let userRepo: any UserRepository
    
    public init(_ awsClient: AWSClient, _ logger: Logger) {
        let euWest = Region(awsRegionName: "eu-west-1")
        let dynamoDB = DynamoDB(client: awsClient, region: euWest)
        self.logger = logger
        self.userRepo = RepositoryFactory.makeUserRepository((
            db: dynamoDB,
            tableName: "penny-bot-table",
            eventLoop: awsClient.eventLoopGroup.next(),
            logger: logger
        ))
    }
    
    public func addCoins(
        with coinEntry: CoinEntry,
        fromDiscordID: String,
        to user: User
    ) async throws -> CoinResponse {
        var localUser: User
        
        do {
            switch coinEntry.source {
            case .discord:
                localUser = try await userRepo.getUser(discord: user.discordID!)
            case .github:
                localUser = try await userRepo.getUser(github: user.githubID!)
            case .penny:
                throw ServiceError.unimplemented()
            }
            
            localUser.addCoinEntry(coinEntry)
            let dbUser = DynamoDBUser(user: localUser)
                
            try await userRepo.updateUser(dbUser)
            return CoinResponse(
                sender: fromDiscordID,
                receiver: localUser.discordID!,
                coins: localUser.numberOfCoins
            )
        }
        catch DBError.itemNotFound {
            localUser = try await insertIntoDB(user: user, with: coinEntry)
            return CoinResponse(
                sender: fromDiscordID,
                receiver: localUser.discordID!,
                coins: localUser.numberOfCoins
            )
        }
        catch let error {
            logger.error("\(error.localizedDescription)")
            throw ServiceError.failedToUpdate
        }
    }
    
    public func getUserUUID(from user: User, with source: CoinEntrySource) async throws -> UUID {
        var localUser: User
        
        do {
            switch source {
            case .discord:
                localUser = try await userRepo.getUser(discord: user.discordID!)
            case .github:
                localUser = try await userRepo.getUser(github: user.githubID!)
            case .penny:
                throw ServiceError.unimplemented()
            }
            
            return localUser.id
        }
        catch {
            return UUID()
        }
    }
    
    private func insertIntoDB(user account: User, with coinEntry: CoinEntry) async throws -> User{
        var localUser = account
        
        localUser.addCoinEntry(coinEntry)
        
        let dbUser = DynamoDBUser(user: localUser)
        try await userRepo.insertUser(dbUser)
        
        return localUser
    }
}
