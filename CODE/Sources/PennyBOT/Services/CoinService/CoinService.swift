import PennyModels

protocol CoinService {
    func postCoin(with coinRequest: CoinRequest.AddCoin) async throws -> CoinResponse
    func getCoinCount(of user: String) async throws -> Int
}
