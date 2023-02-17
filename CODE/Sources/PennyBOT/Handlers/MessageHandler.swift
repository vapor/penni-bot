import DiscordBM
import Logging
import PennyModels

struct MessageHandler {
    
    let coinService: any CoinService
    var logger = Logger(label: "MessageHandler")
    let event: Gateway.MessageCreate
    var pingsService: any AutoPingsService {
        ServiceFactory.makePingsService()
    }
    
    init(coinService: any CoinService, event: Gateway.MessageCreate) {
        self.coinService = coinService
        self.event = event
        self.logger[metadataKey: "event"] = "\(event)"
    }
    
    func handle() async {
        await checkForNewCoins()
        await checkForPings()
    }
    
    func checkForNewCoins() async {
        guard let author = event.author else {
            logger.error("Cannot find author of the message")
            return
        }
        
        // Stop the bot from responding to other bots and itself
        if author.bot == true {
            return
        }
        
        let sender = "<@\(author.id)>"
        let repliedUser = event.referenced_message?.value.author.map({ "<@\($0.id)>" })
        let coinHandler = CoinHandler(
            text: event.content,
            repliedUser: repliedUser,
            mentionedUsers: event.mentions.map(\.id).map({ "<@\($0)>" }),
            excludedUsers: [sender] // Can't give yourself a coin
        )
        let usersWithNewCoins = coinHandler.findUsers()
        // Return if there are no coins to be granted
        if usersWithNewCoins.isEmpty { return }
        
        var successfulResponses = [String]()
        successfulResponses.reserveCapacity(usersWithNewCoins.count)
        
        for receiver in usersWithNewCoins {
            let coinRequest = CoinRequest(
                // Possible to make this a variable later to include in the thanks message
                amount: 1,
                from: sender,
                receiver: receiver,
                source: .discord,
                reason: .userProvided
            )
            do {
                let response = try await self.coinService.postCoin(with: coinRequest)
                let responseString = "\(response.receiver) now has \(response.coins) \(Constants.vaporCoinEmoji)!"
                successfulResponses.append(responseString)
            } catch {
                logger.error("CoinService failed", metadata: [
                    "request": "\(coinRequest)",
                    "error": "\(error)"
                ])
            }
        }
        
        if successfulResponses.isEmpty {
            // Definitely there were some coin requests that failed.
            await self.respondToThanks(with: "Oops. Something went wrong! Please try again later")
        } else {
            // Stitch responses together instead of sending a lot of messages,
            // to consume less Discord rate-limit.
            let finalResponse = successfulResponses.joined(separator: "\n")
            // Discord doesn't like embed-descriptions with more than 4_000 content length.
            if finalResponse.unicodeScalars.count > 4_000 {
                logger.warning("Can't send the full thanks-response", metadata: [
                    "full": .string(finalResponse)
                ])
                await self.respondToThanks(with: "Coins were granted to a lot of members!")
            } else {
                await self.respondToThanks(with: finalResponse)
            }
        }
    }
    
    func checkForPings() async {
        if event.content.isEmpty { return }
        guard let guildId = event.guild_id else { return }
        let wordUsersDict: [S3AutoPingItems.Expression: Set<String>]
        do {
            wordUsersDict = try await pingsService.getAll().items
        } catch {
            logger.error("Can't retrieve ping-words", metadata: ["error": "\(error)"])
            return
        }
        let folded = event.content.foldForPingCommand()
        /// `[UserID: [PingTrigger]]`
        var usersToPing: [String: Set<String>] = [:]
        for word in wordUsersDict.keys {
            let innerValue = word.innerValue
            if folded.contains(innerValue),
               let users = wordUsersDict[word] {
                for user in users {
                    let plainId = user.makePlainUserID()
                    /// Both checks if the user has the required roles,
                    /// and if the user is in the guild at all.
                    if await DiscordService.shared.userHasAnyTechnicalRoles(userId: plainId) {
                        usersToPing[user, default: []].insert(innerValue)
                    }
                }
            }
        }
        let _usersToPing = usersToPing
        let messageLink = "https://discord.com/channels/\(guildId)/\(event.channel_id)/\(event.id)"
        Task {
            /// Don't need any throttling for now, `DiscordBM` will
            /// do enough and won't exceed rate-limits.
            for (user, words) in _usersToPing {
                let words = words.sorted().map { "`\($0)`" }.joined(separator: ", ")
                await DiscordService.shared.sendDM(
                    userId: user,
                    payload: .init(
                        embeds: [.init(
                            description: """
                            There is a new message that might be of interest to you.
                            Triggered by: \(words)
                            Message: \(messageLink)
                            """,
                            color: .vaporPurple
                        )]
                    )
                )
            }
        }
    }
    
    private func respondToThanks(with response: String) async {
        await DiscordService.shared.sendThanksResponse(
            channelId: event.channel_id,
            replyingToMessageId: event.id,
            response: response
        )
    }
}
