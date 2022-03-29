import AWSLambdaRuntime
import AWSLambdaEvents
import Foundation
import SotoCore

struct Response: Codable {
    let body: String
}

@main
struct AddCoins: LambdaHandler {
    typealias Event = APIGatewayV2Request
    typealias Output = APIGatewayV2Response
    
    let awsClient: AWSClient
    
    let userService: UserService
    
    init(context: Lambda.InitializationContext) async throws {
        // setup your resources that you want to reuse for every invocation here.
        self.awsClient = AWSClient(
            httpClientProvider: .createNewWithEventLoopGroup(context.eventLoop))
        self.userService = UserService(awsClient, context.logger)
    }
    
    func shutdown(context: Lambda.ShutdownContext) async throws {
        try? awsClient.syncShutdown()
    }

    func handle(_ event: APIGatewayV2Request, context: LambdaContext) async throws -> APIGatewayV2Response {
        let response: APIGatewayV2Response
        do {
            let product: CoinRequest = try event.bodyObject()
            
            var user = User(
                id: UUID(),
                discordID: product.receiver,
                githubID: product.receiver,
                numberOfCoins: product.amount,
                coinEntries: [],
                createdAt: Date())
            
            let userUUID = try await userService.getUserUUID(from: user, with: product.source)
            let coinEntry = CoinEntry(
                id: UUID(),
                createdAt: Date(),
                amount: product.amount,
                from: userUUID,
                source: product.source,
                reason: product.reason)
            
            user.addCoinEntry(coinEntry)
            
            let message = try await userService.addCoins(with: coinEntry, to: user)
            response = APIGatewayV2Response(statusCode: .ok, body: message)
        }
        catch UserService.ServiceError.failedToUpdate {
            response = APIGatewayV2Response(statusCode: .notFound)
        }
        catch let error {
            response = APIGatewayV2Response(statusCode: .badRequest, body: "ERROR-\(error.localizedDescription)")
            
        }
        return response
    }
}

public enum APIError: Error{
    case invalidItem
    case tableNameNotFound
    case invalidRequest
    case invalidHandler
}
