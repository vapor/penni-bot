import DiscordBM
import GitHubAPI
import OpenAPIRuntime
import Logging

struct HandlerContext {
    let eventName: GHEvent.Kind
    let event: GHEvent
    let discordClient: any DiscordClient
    let githubClient: Client
    let logger: Logger
}
