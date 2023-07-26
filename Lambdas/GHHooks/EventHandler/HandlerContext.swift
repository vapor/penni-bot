import AsyncHTTPClient
import DiscordBM
import GitHubAPI
import OpenAPIRuntime
import LeafKit
import Logging

struct HandlerContext {
    let eventName: GHEvent.Kind
    let event: GHEvent
    let httpClient: HTTPClient
    let discordClient: any DiscordClient
    let githubClient: Client
    let messageLookupRepo: any MessageLookupRepo
    let leafRenderer: LeafRenderer
    let logger: Logger
}
