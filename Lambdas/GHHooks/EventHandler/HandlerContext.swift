import AsyncHTTPClient
import DiscordBM
import GitHubAPI
import OpenAPIRuntime
import Rendering
import Shared
import Logging

struct HandlerContext: Sendable {
    let eventName: GHEvent.Kind
    let event: GHEvent
    let httpClient: HTTPClient = .shared
    let discordClient: any DiscordClient
    let githubClient: Client
    let renderClient: RenderClient
    let messageLookupRepo: any MessageLookupRepo
    let usersService: any UsersService
    let requester: Requester
    var logger: Logger

    init(
        eventName: GHEvent.Kind,
        event: GHEvent,
        discordClient: any DiscordClient,
        githubClient: Client,
        renderClient: RenderClient,
        messageLookupRepo: any MessageLookupRepo,
        usersService: any UsersService,
        logger: Logger
    ) {
        self.eventName = eventName
        self.event = event
        self.discordClient = discordClient
        self.githubClient = githubClient
        self.renderClient = renderClient
        self.messageLookupRepo = messageLookupRepo
        self.usersService = usersService
        self.requester = .init(
            eventName: eventName,
            event: event,
            discordClient: discordClient,
            githubClient: githubClient,
            usersService: usersService,
            logger: logger
        )
        self.logger = logger
    }
}
