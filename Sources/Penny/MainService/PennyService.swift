import DiscordBM
import DiscordLogger
import AsyncHTTPClient
import NIOCore
import SotoCore
import Logging

struct PennyService: MainService {
    func bootstrapLoggingSystem(httpClient: HTTPClient) async throws {
#if DEBUG
        // Discord-logging is disabled in debug based on the logger configuration,
        // so we can just use an invalid url
        let webhookUrl = "https://discord.com/api/webhooks/1066284436045439037/dSs4nFhjpxcOh6HWD_"
#else
        guard let webhookUrl = Constants.loggingWebhookUrl else {
            fatalError("Missing 'LOGGING_WEBHOOK_URL' env var")
        }
#endif
        DiscordGlobalConfiguration.logManager = await DiscordLogManager(
            httpClient: httpClient,
            configuration: .init(
                aliveNotice: .init(
                    address: try! .url(webhookUrl),
                    interval: nil,
                    message: "I'm Alive! :)",
                    initialNoticeMention: .user(Constants.botDevUserId)
                ),
                mentions: [
                    .warning: .user(Constants.botDevUserId),
                    .error: .user(Constants.botDevUserId),
                    .critical: .user(Constants.botDevUserId)
                ],
                extraMetadata: [.warning, .error, .critical],
                disabledLogLevels: [.debug, .trace],
                disabledInDebug: true
            )
        )
        await LoggingSystem.bootstrapWithDiscordLogger(
            address: try! .url(webhookUrl),
            level: .trace,
            makeMainLogHandler: { label, metadataProvider in
                StreamLogHandler.standardOutput(label: label, metadataProvider: metadataProvider)
            }
        )
    }

    func makeBot(
        eventLoopGroup: any EventLoopGroup,
        httpClient: HTTPClient
    ) async throws -> any GatewayManager {
        guard let token = Constants.botToken else {
            fatalError("Missing 'BOT_TOKEN' env var")
        }
        /// Custom caching for the `getApplicationGlobalCommands` endpoint.
        let clientConfiguration = ClientConfiguration(
            cachingBehavior: .custom(
                apiEndpoints: [
                    .listApplicationCommands: .seconds(60 * 60) /// 1 hour
                ],
                apiEndpointsDefaultTTL: .seconds(5)
            )
        )
        return await BotGatewayManager(
            eventLoopGroup: eventLoopGroup,
            httpClient: httpClient,
            clientConfiguration: clientConfiguration,
            token: token,
            presence: .init(
                activities: [.init(name: "you", type: .game)],
                status: .online,
                afk: false
            ),
            intents: [.guilds, .guildMembers, .guildMessages, .messageContent, .guildMessageReactions]
        )
    }

    func makeCache(bot: any GatewayManager) async throws -> DiscordCache {
        await DiscordCache(
            gatewayManager: bot,
            intents: [.guilds, .guildMembers],
            requestAllMembers: .enabled
        )
    }

    func beforeConnectCall(
        bot: any GatewayManager,
        cache: DiscordCache,
        httpClient: HTTPClient,
        awsClient: AWSClient
    ) async throws -> HandlerContext {
        await DefaultPingsService.shared.initialize(httpClient: httpClient)
        await DefaultFaqsService.shared.initialize(httpClient: httpClient)
        try await DefaultUsersService.shared.initialize(httpClient: httpClient)
        await DefaultCachesService.shared.initialize(awsClient: awsClient)
        let discordService = DiscordService(discordClient: bot.client, cache: cache)
        let proposalsChecker = ProposalsChecker(
            proposalsService: DefaultProposalsService(httpClient: httpClient),
            discordService: discordService
        )
        let services = HandlerContext.Services(
            usersService: DefaultUsersService.shared,
            pingsService: DefaultPingsService.shared,
            faqsService: DefaultFaqsService.shared,
            cachesService: DefaultCachesService.shared,
            discordService: discordService
        )
        let workers = HandlerContext.Workers(
            proposalsChecker: proposalsChecker,
            reactionCache: ReactionCache()
        )
        let context = HandlerContext(
            services: services,
            workers: workers,
            botStateManager: BotStateManager(
                services: services,
                workers: workers
            )
        )
        await CommandsManager().registerCommands(context: context)
        return context
    }

    func afterConnectCall(context: HandlerContext) async throws {
        /// Initialize `BotStateManager` after `bot.connect()` and `bot.makeEventsStream()`.
        /// since it communicates through Discord and will need the Gateway connection.
        await context.botStateManager.start {
            /// ProposalsChecker contains cached stuff and needs to wait for `BotStateManager`.
            context.workers.proposalsChecker.run()
        }
    }
}
