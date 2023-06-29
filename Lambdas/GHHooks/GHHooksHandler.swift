import AWSLambdaRuntime
import AWSLambdaEvents
import AsyncHTTPClient
import SotoSecretsManager
import Crypto
import DiscordHTTP
import Extensions
import Foundation

import OpenAPIAsyncHTTPClient

@main
struct GHHooksHandler: LambdaHandler {
    typealias Event = APIGatewayV2Request
    typealias Output = APIGatewayV2Response

    let discordClient: any DiscordClient
    let secretsRetriever: SecretsRetriever
    let logger: Logger

    init(context: LambdaInitializationContext) async throws {
        self.logger = context.logger

        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(context.eventLoop))
        let awsClient = AWSClient(httpClientProvider: .shared(httpClient))
        self.secretsRetriever = SecretsRetriever(awsClient: awsClient, logger: logger)

        let botToken = try await secretsRetriever.getSecret(arnEnvVarKey: "BOT_TOKEN_ARN")
        self.discordClient = await DefaultDiscordClient(httpClient: httpClient, token: botToken)

        let transport = AsyncHTTPClientTransport(
            configuration: .init(client: httpClient)
        )

        let serverURL = try Servers.server1()

        let client = Client(
            serverURL: serverURL,
            transport: transport
        )
    }

    func handle(
        _ request: APIGatewayV2Request,
        context: LambdaContext
    ) async throws -> APIGatewayV2Response {
        do {
            return try await handleThrowing(request, context: context)
        } catch {
            do {
                /// Report to Discord server for easier notification of maintainers
                try await discordClient.createMessage(
                    channelId: Constants.Channels.logs.id,
                    payload: .init(embeds: [.init(
                        title: "GHHooks lambda top-level error",
                        description: String("\(error)".prefix(4_000)),
                        color: .red
                    )])
                ).guardSuccess()
            } catch {
                logger.error("DiscordClient logging error", metadata: [
                    "error": "\(error)"
                ])
            }
            throw error
        }
    }

    func handleThrowing(
        _ request: APIGatewayV2Request,
        context: LambdaContext
    ) async throws -> APIGatewayV2Response {
        logger.trace("Got request", metadata: [
            "request": "\(request)"
        ])
        try await verifyWebhookSignature(request: request)
        logger.debug("Verified signature")

        guard let _eventName = request.headers.first(name: "x-gitHub-event"),
              let eventName = GHEvent.Kind(rawValue: _eventName) else {
            throw Errors.headerNotFound(name: "x-gitHub-event", headers: request.headers)
        }

        logger.trace("Event name is '\(eventName)'")

        /// To make sure we don't miss pings because of a decoding error or something
        if eventName == .ping {
            return APIGatewayV2Response(statusCode: .ok)
        }

        let event = try request.decodeWithISO8601(as: GHEvent.self)

        logger.debug("Decoded event", metadata: [
            "event": "\(event)"
        ])

        try await EventHandler(
            client: discordClient,
            eventName: eventName,
            event: event
        ).handle()

        logger.trace("Event handled")

        return APIGatewayV2Response(statusCode: .ok)
    }

    func verifyWebhookSignature(request: APIGatewayV2Request) async throws {
        guard let signature = request.headers.first(name: "x-hub-signature-256") else {
            throw Errors.headerNotFound(name: "x-hub-signature-256", headers: request.headers)
        }
        let hmacMessageData = Data((request.body ?? "").utf8)
        let secret = try await getWebhookSecret()
        var hmac = HMAC<SHA256>.init(key: secret)
        hmac.update(data: hmacMessageData)
        let mac = hmac.finalize()
        let expectedSignature = "sha256=" + mac.hexDigest()
        guard signature == expectedSignature else {
            throw Errors.signaturesDoNotMatch(found: signature, expected: expectedSignature)
        }
    }

    func getWebhookSecret() async throws -> SymmetricKey {
        let secret = try await secretsRetriever.getSecret(arnEnvVarKey: "WH_SECRET_ARN")
        let data = Data(secret.utf8)
        return SymmetricKey(data: data)
    }
}
