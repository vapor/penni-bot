import DiscordBM
@testable import PennyBOT

public enum EventKey: String, Sendable {
    case thanksMessage
    case thanksMessage2
    case linkInteraction
    case thanksReaction
    case thanksReaction2
    case thanksReaction3
    case thanksReaction4
    case stopRespondingToMessages
    case autoPingsTrigger
    case autoPingsTrigger2
    case howManyCoins1
    case howManyCoins2
    case serverBoost
    case helpsAdd
    case helpsAddFailure
    case helpsGet
    case helpsGetAutocomplete

    /// The endpoints from which the bot will send a response, after receiving each event.
    public var responseEndpoints: [APIEndpoint] {
        switch self {
        case .thanksMessage:
            return [.createMessage(channelId: "519613337638797315")]
        case .thanksMessage2:
            return [.createMessage(channelId: Constants.thanksChannelId)]
        case .linkInteraction:
            return [.updateOriginalInteractionResponse(applicationId: "11111111", interactionToken: "aW50ZXJhY3Rpb246MTAzMTExMjExMzk3ODA4OTUwMjpRVGVBVXU3Vk1XZ1R0QXpiYmhXbkpLcnFqN01MOXQ4T2pkcGRXYzRjUFNMZE9TQ3g4R3NyM1d3OGszalZGV2c3a0JJb2ZTZnluS3VlbUNBRDh5N2U3Rm00QzQ2SWRDMGJrelJtTFlveFI3S0RGbHBrZnpoWXJSNU1BV1RqYk5Xaw"), .createInteractionResponse(interactionId: "1031112113978089502", interactionToken: "aW50ZXJhY3Rpb246MTAzMTExMjExMzk3ODA4OTUwMjpRVGVBVXU3Vk1XZ1R0QXpiYmhXbkpLcnFqN01MOXQ4T2pkcGRXYzRjUFNMZE9TQ3g4R3NyM1d3OGszalZGV2c3a0JJb2ZTZnluS3VlbUNBRDh5N2U3Rm00QzQ2SWRDMGJrelJtTFlveFI3S0RGbHBrZnpoWXJSNU1BV1RqYk5Xaw")]
        case .thanksReaction:
            return [.createMessage(channelId: "684159753189982218")]
        case .thanksReaction2:
            return [.updateMessage(
                channelId: "684159753189982218",
                messageId: "1031112115928449022"
            )]
        case .thanksReaction3:
            return [.createMessage(channelId: Constants.thanksChannelId)]
        case .thanksReaction4:
            return [.updateMessage(
                channelId: Constants.thanksChannelId,
                messageId: "1031112115928111022"
            )]
        case .stopRespondingToMessages:
            return [.createMessage(channelId: "1067060193982156880")]
        case .autoPingsTrigger, .autoPingsTrigger2:
            return [
                .createDm,
                .createMessage(channelId: "1018169583619821619")
            ]
        case .howManyCoins1:
            return [.updateOriginalInteractionResponse(applicationId: "11111111", interactionToken: "aW50ZXJhY3Rpb246MTA1OTM0NTUzNjM2NjQyMDExODowbHZldWtVOUVvMVFCMEhnSjR2RmJrMncyOXNuV3J6OVR5Qk9mZ2h6YzhMSDVTdEZ3NWNIMXA1VzJlZ2RteXdHbzFGdGl0dVFMa2dBNVZUUndmVVFqZzJhUDJlTERuNDRjYXBuSWRHZzRwSFZnNjJLR3hZM1hKNjRuaWtCUzZpeg"), .createInteractionResponse(interactionId: "1059345536366420118", interactionToken: "aW50ZXJhY3Rpb246MTA1OTM0NTUzNjM2NjQyMDExODowbHZldWtVOUVvMVFCMEhnSjR2RmJrMncyOXNuV3J6OVR5Qk9mZ2h6YzhMSDVTdEZ3NWNIMXA1VzJlZ2RteXdHbzFGdGl0dVFMa2dBNVZUUndmVVFqZzJhUDJlTERuNDRjYXBuSWRHZzRwSFZnNjJLR3hZM1hKNjRuaWtCUzZpeg")]
        case .howManyCoins2:
            return [.updateOriginalInteractionResponse(applicationId: "11111111", interactionToken: "aW50ZXJhY3Rpb246MTA1OTM0NTY0MTY1MTgzMDg1NTp2NWI1eVFkNEVJdHJaRlc0bUZoRmNjMUFKeHNqS09YcXhHTUxHZGJIMXdzdFhkVkhWSk95YnNUdUV4U29UdUl3ejJsN2k0RTlDNVA3Nmhza2xIdkdrR2ZQRnduOEFBNUFlM28zN1NzSlJta0tVSkt1M1FxQ1lvb3FZU1lnMWg1ag"), .createInteractionResponse(interactionId: "1059345641651830855", interactionToken: "aW50ZXJhY3Rpb246MTA1OTM0NTY0MTY1MTgzMDg1NTp2NWI1eVFkNEVJdHJaRlc0bUZoRmNjMUFKeHNqS09YcXhHTUxHZGJIMXdzdFhkVkhWSk95YnNUdUV4U29UdUl3ejJsN2k0RTlDNVA3Nmhza2xIdkdrR2ZQRnduOEFBNUFlM28zN1NzSlJta0tVSkt1M1FxQ1lvb3FZU1lnMWg1ag")]
        case .serverBoost:
            return [.createMessage(channelId: "443074453719744522")]
        case .helpsAdd:
            return [.createInteractionResponse(interactionId: "1097057830038667314", interactionToken: "aW50ZXJhY3Rpb246MTA5NzA1NzgzMDAzODY2NzMxNDpISXNabG5KMTlPdUtDOEhSbU93WmlucUd2eGNRYXRuS2lUaVNVZ255RHhLMThLZGM1Q1diU21sY3ByaGJMSkJxYXBZdkdEZXJRbVdNSmZ0WHp0dzNvcVNWWkE5dmllSmxoRUE1UG0xdXVPSUE0cDA3N1AzY2ZlSjluTFFFMzJTRw")]
        case .helpsAddFailure:
            return [.updateOriginalInteractionResponse(applicationId: "11111111", interactionToken: "aW50ZXJhY3Rpb246MTA5NzA1NzgzMDAzODY2NzMxNDpISXNabG5KMTlPdUtDOEhSbU93WmlucUd2eGNRYXRuS2lUaVNVZ255RHhLMThLZGM1Q1diU21sY3ByaGJMSkJxYXBZdkdEZXJRbVdNSmZ0WHp0dzNvcVNWWkE5dmllSmxoRUE1UG0xdXVPSUE0cDA3N1AzY2ZlSjluTFFFMzJTRw"),.createInteractionResponse(interactionId: "1097057830038667314", interactionToken: "aW50ZXJhY3Rpb246MTA5NzA1NzgzMDAzODY2NzMxNDpISXNabG5KMTlPdUtDOEhSbU93WmlucUd2eGNRYXRuS2lUaVNVZ255RHhLMThLZGM1Q1diU21sY3ByaGJMSkJxYXBZdkdEZXJRbVdNSmZ0WHp0dzNvcVNWWkE5dmllSmxoRUE1UG0xdXVPSUE0cDA3N1AzY2ZlSjluTFFFMzJTRw")]
        case .helpsGet:
            return [.updateOriginalInteractionResponse(applicationId: "11111111", interactionToken: "aW50ZXJhY3Rpb246MTA5NzA2MjQ3NDExODg2NDkwNjpJMXhuZEVPeXViZFVteXV0UUpNZjAzZFBNMTNvVndnSkpLZ0xlbFprbnFLbmNLSlpFQmc3bUc3bVF6YzdJVklZemRqNlIzcFhsZlBEM3FoZmtPeXQwZHRkY2psNlExeTRRcDB4dWhmcGwyOW1EWGtuajhVWjdidU1VQ2dUQk5JcA"), .createInteractionResponse(interactionId: "1097062474118864906", interactionToken: "aW50ZXJhY3Rpb246MTA5NzA2MjQ3NDExODg2NDkwNjpJMXhuZEVPeXViZFVteXV0UUpNZjAzZFBNMTNvVndnSkpLZ0xlbFprbnFLbmNLSlpFQmc3bUc3bVF6YzdJVklZemRqNlIzcFhsZlBEM3FoZmtPeXQwZHRkY2psNlExeTRRcDB4dWhmcGwyOW1EWGtuajhVWjdidU1VQ2dUQk5JcA")]
        case .helpsGetAutocomplete:
            return [.createInteractionResponse(interactionId: "1097060331508994088", interactionToken: "aW50ZXJhY3Rpb246MTA5NzA2MDMzMTUwODk5NDA4ODpyWDROWEtucXBJNm1ZaDRDQ2QzVFVyRDU5Q21pZlhFV3pkUHJaaDZUbHczUlVkc1dGRDdYdHBYdVJFT2VrN2ROUzByTEdUTVJNaXhMRk5uUWk4Mng4MWF5S00yRWdQdzNqbGlkbUR3N3pwTm5HR2JnQVZQUkhtajhJbWltMVBQOQ")]
        }
    }
}
