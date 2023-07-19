import AsyncHTTPClient
import AWSLambdaRuntime
import AWSLambdaEvents
import DiscordBM
import Foundation
import SotoSecretsManager
import GHHooksLambda
import Models
import JWTKit
import SharedServices

@main
struct GHOAuthHandler: LambdaHandler {
    typealias Event = APIGatewayV2Request
    typealias Output = APIGatewayV2Response

    let client: HTTPClient
    let logger: Logger
    let secretsRetriever: SecretsRetriever
    let discordClient: any DiscordClient
    let jsonDecoder: JSONDecoder
    let jsonEncoder: JSONEncoder
    let userService: UserService

    init(context: LambdaInitializationContext) async throws {
        self.client = HTTPClient(eventLoopGroupProvider: .shared(context.eventLoop))
        self.logger = context.logger

        let awsClient = AWSClient(httpClientProvider: .shared(client))
        self.secretsRetriever = SecretsRetriever(awsClient: awsClient, logger: logger)

        let botToken = try await secretsRetriever.getSecret(arnEnvVarKey: "BOT_TOKEN_ARN")
        self.discordClient = await DefaultDiscordClient(httpClient: client, token: botToken)

        self.userService = UserService(awsClient, logger)

        self.jsonDecoder = JSONDecoder()
        self.jsonEncoder = JSONEncoder()
    }

    func handle(_ event: APIGatewayV2Request, context: LambdaContext) async -> APIGatewayV2Response {
        logger.trace("Received event: \(event)")

        guard let code = event.queryStringParameters?["code"] else {
            return .init(statusCode: .badRequest, body: "Missing code query parameter")
        }

        let accessToken: String

        do {
            accessToken = try await getGHAccessToken(code: code)
        } catch {
            logger.error("Error getting access token: \(error)")
            return .init(statusCode: .badRequest, body: "Error getting access token")
        }

        let userID: Int

        do {
            userID = try await getGHUserID(accessToken: accessToken)
        } catch {
            logger.error("Error getting user ID: \(error)")
            return .init(statusCode: .badRequest, body: "Error getting user")
        }

        let jwt: GHOAuthPayload

        do {
            jwt = try await verifyState(state: String(event.queryStringParameters?["state"] ?? ""))
        } catch {
            logger.error("Error during state verification: error: \(error)", metadata: [
                "state": .string(event.queryStringParameters?["state"] ?? "")
            ])
            return .init(statusCode: .badRequest, body: "Error verifying state")
        }

        do {
            try await userService.linkGithubID(to: jwt.discordID.rawValue, githubID: "\(userID)")
        } catch {
            logger.error("Error linking user with Discord ID \(jwt.discordID) and GitHub ID \(userID): \(error)")
            return .init(statusCode: .badRequest, body: "Error linking user")
        }

        return .init(statusCode: .ok, body: "Account linking successful, you can return to Discord now")
    }

    func verifyState(state: String) async throws -> GHOAuthPayload {
        logger.trace("Verifying state parameter...")

        logger.trace("Retrieving JWT signer secrets")
        guard let publicKeyString = ProcessInfo.processInfo.environment["ACCOUNT_LINKING_OAUTH_FLOW_PUB_KEY"] else {
            throw OAuthLambdaError.envVarNotFound(name: "ACCOUNT_LINKING_OAUTH_FLOW_PUB_KEY")
        }
        guard let publicKeyData = Data(base64Encoded: publicKeyString) else {
            throw OAuthLambdaError.invalidPublicKey
        }
        guard let publicKey = try? ECDSAKey.public(pem: publicKeyData) else {
            throw OAuthLambdaError.invalidPublicKey
        }

        let signer = JWTSigner.es256(key: publicKey)

        let payload = try signer.verify(state, as: GHOAuthPayload.self)

        return payload
    }

    func getGHAccessToken(code: String) async throws -> String {
        logger.trace("Retrieving GitHub client secrets")

        let clientSecret = try await secretsRetriever.getSecret(arnEnvVarKey: "GH_CLIENT_SECRET_ARN")
        guard let clientID = ProcessInfo.processInfo.environment["GH_CLIENT_ID"] else {
            throw OAuthLambdaError.envVarNotFound(name: "GH_CLIENT_ID")
        }

        // https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps

        logger.trace("Requesting GitHub access token")
        var request = HTTPClientRequest(url: "https://github.com/login/oauth/access_token")
        request.method = .POST
        request.headers = [
            "Accept": "application/json",
            "Content-Type": "application/json"
        ]
        let requestBody = try jsonEncoder.encode([
            "client_id": clientID,
            "client_secret": clientSecret.value,
            "code": code
        ])
        request.body = .bytes(requestBody)

        let response = try await client.execute(request, timeout: .seconds(30))
        logger.trace("Got response: \(response.status)")

        guard response.status == .ok else {
            throw OAuthLambdaError.badResponse(status: Int(response.status.code))
        }

        let responseBody = try await response.body.collect(upTo: 1024 * 1024)
        let accessToken = try jsonDecoder.decode(AccessTokenResponse.self, from: responseBody).accessToken

        return accessToken
    }

    func getGHUserID(accessToken: String) async throws -> Int {
        logger.trace("Requesting GitHub user info")

        // https://docs.github.com/en/rest/users/users?apiVersion=2022-11-28#get-the-authenticated-user

        var request = HTTPClientRequest(url: "https://api.github.com/user")
        request.method = .GET
        request.headers = [
            "Accept": "application/vnd.github+json",
            "Authorization": "Bearer \(accessToken)",
            "X-GitHub-Api-Version": "2022-11-28"
        ]

        let response = try await client.execute(request, timeout: .seconds(30))

        guard response.status == .ok else {
            throw OAuthLambdaError.badResponse(status: Int(response.status.code))
        }

        let userResponseBody = try await response.body.collect(upTo: 1024 * 1024)
        let id = try jsonDecoder.decode(User.self, from: userResponseBody).id
        
        logger.info("Got user id: \(id)")

        return id
    }
}
