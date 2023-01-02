import DiscordBM
import Logging

struct EventHandler {
    let event: Gateway.Event
    let coinService: any CoinService
    let logger: Logger
    
    func handle() {
        Task {
            guard await BotStateManager.shared.canRespond(to: event) else {
                logger.debug("BotStateManager doesn't allow responding to event", metadata: [
                    "event": "\(event)"
                ])
                return
            }
            switch event.data {
            case .messageCreate(let message):
                await ReactionCache.shared.invalidateCachesIfNeeded(event: message)
                await MessageHandler(
                    coinService: coinService,
                    logger: logger,
                    event: message
                ).handle()
            case .interactionCreate(let interaction):
                await InteractionHandler(
                    logger: logger,
                    event: interaction,
                    coinService: coinService
                ).handle()
            case .messageReactionAdd(let reaction):
                await ReactionHandler(
                    coinService: coinService,
                    logger: logger,
                    event: reaction
                ).handle()
            default: break
            }
        }
    }
}
