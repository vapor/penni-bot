
struct HandlerContext: Sendable {

    struct Services: Sendable {
        let usersService: any UsersService
        let pingsService: any AutoPingsService
        let faqsService: any FaqsService
        let cachesService: any CachesService
        let discordService: DiscordService
    }

    struct Workers: Sendable {
        let proposalsChecker: ProposalsChecker
        let reactionCache: ReactionCache
    }

    let services: Services
    let workers: Workers
    let botStateManager: BotStateManager
}
