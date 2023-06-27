import DiscordBM
import Foundation
import Logging

/**
 When we update Penny, AWS waits a few minutes before taking down the old Penny instance to
 make sure the new instance is healthy.
 This makes it so there is a short period where there are 2 Penny bots that will respond to
 Discord Gateway events.
 This actor's job is to prevent that. Only the new bot should respond to events.

 This will:
   * Disallow Gateway-event handling from the beginning.
   * When `initialize()` is called, this will send a "please shutdown" message.
   * When the old Penny instance receive that message.
     * The old instance will save all needed cached stuff into a S3 bucket.
     * Then it will send a "did shutdown" message.
   * The new instance will catch the "did shutdown" message.
     * The new instance will get the stuff from the S3 bucket.
     * Then it will start allowing Gateway-event handlings.
   * If the old instance is too slow to make the process happen, the process is aborted and
     the new instance will start handling events without waiting more for the old instance.
 */
actor BotStateManager {

    let id = Int(Date().timeIntervalSince1970)
    var logger = Logger(label: "BotStateManager")

    var canRespond = false
    var disableDuration = Duration.seconds(3 * 60)
    var onStart: (() async -> Void)?

    var cachesService: any CachesService {
        ServiceFactory.makeCachesService()
    }

    static private(set) var shared = BotStateManager()
    
    private init() { }
    
    func initialize(onStart: @Sendable @escaping () async -> Void) async {
        self.logger[metadataKey: "id"] = "\(self.id)"
        self.onStart = onStart
        Task { await send(.shutdown) }
        cancelIfCachePopulationTakesTooLong()
    }

    func cancelIfCachePopulationTakesTooLong() {
        Task {
            try await Task.sleep(for: .seconds(2 * 60))
            if !canRespond {
                await startAllowingResponses()
                logger.error("No CachesStorage-population was done in-time")
            }
        }
    }

    func canRespond(to event: Gateway.Event) -> Bool {
        checkIfItsASignal(event: event)
        return canRespond
    }
    
    private func checkIfItsASignal(event: Gateway.Event) {
        guard case let .messageCreate(message) = event.data,
              message.channel_id == Constants.Channels.logs.id,
              let author = message.author,
              author.id.rawValue == Constants.botId,
              let otherId = message.content.split(whereSeparator: \.isWhitespace).last
        else { return }
        if otherId == "\(self.id)" { return }

        if StateManagerSignal.shutdown.isInMessage(message.content) {
            logger.trace("Received 'shutdown' signal")
            shutdown()
        } else if StateManagerSignal.didShutdown.isInMessage(message.content) {
            logger.trace("Received 'didShutdown' signal")
            populateCache()
        } else {
            logger.error("Unknown signal", metadata: ["signal": .string(message.content)])
            return
        }
    }

    private func shutdown() {
        self.canRespond = false
        Task {
            await cachesService.gatherCachedInfoAndSaveToRepository()
            await send(.didShutdown)

            try await Task.sleep(for: disableDuration)
            await startAllowingResponses()
            logger.error("AWS has not yet shutdown this instance of Penny! Why?!")
        }
    }

    private func populateCache() {
        Task {
            if canRespond {
                logger.warning("Received a did-shutdown signal but Cache is already populated")
            } else {
                await cachesService.getCachedInfoFromRepositoryAndPopulateServices()
                await startAllowingResponses()
                logger.notice("Done loading old-instance's cached info")
            }
        }
    }

    private func startAllowingResponses() async {
        canRespond = true
        await onStart?()
    }

    private func send(_ signal: StateManagerSignal) async {
        let content = makeSignalMessage(text: signal.rawValue, id: self.id)
        await DiscordService.shared.sendMessage(
            channelId: Constants.Channels.logs.id,
            payload: .init(content: content)
        )
    }

    func makeSignalMessage(text: String, id: Int) -> String {
        "\(text) \(id)"
    }

#if DEBUG
    func _tests_reset() {
        BotStateManager.shared = BotStateManager()
    }
    
    func _tests_setDisableDuration(to duration: Duration) {
        self.disableDuration = duration
    }

    func _tests_didShutdownSignalEventContent() -> String {
        makeSignalMessage(text: StateManagerSignal.didShutdown.rawValue, id: self.id - 10)
    }
#endif
}

enum StateManagerSignal: String {
    case shutdown = "Hello the other Pennys 👋 you can retire now :)"
    case didShutdown = "I'm retired!"

    func isInMessage(_ text: String) -> Bool {
        text.hasPrefix(self.rawValue)
    }
}
