import Foundation
import DiscordBM

enum Constants {
    static func env(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }
    static let vaporGuildId = "431917998102675485"
    static let logsChannelId = "1067060193982156880"
    static let thanksChannelId = "443074453719744522"
    static let botDevUserId = "290483761559240704"
    static var botToken: String! = env("BOT_TOKEN")
    static var botId: String! = env("BOT_APP_ID")
    static var loggingWebhookUrl: String! = env("LOGGING_WEBHOOK_URL")
    static var coinServiceBaseUrl: String! = env("API_BASE_URL")
    static var pingsServiceBaseUrl: String! = env("PINGS_API_BASE_URL")
    /// Vapor's custom coin emoji in Discord's format.
    static let vaporCoinEmoji = DiscordUtils.customEmoji(name: "coin", id: "473588485962596352")
    
    enum TechnicalRoles: String, CaseIterable {
        case contributor = "431920712505098240"
        case maintainer = "530113860129259521"
        case moderator = "431920836631592980"
        case core = "431919254372089857"
    }
}
