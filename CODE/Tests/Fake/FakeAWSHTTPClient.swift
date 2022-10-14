import SotoCore
import NIOCore
import NIOHTTP1
import Logging
import Foundation

public class FakeAWSHTTPClient: AWSHTTPClient {
    public func execute(
        request: AWSHTTPRequest,
        timeout: TimeAmount,
        on eventLoop: EventLoop,
        logger: Logger
    ) -> EventLoopFuture<AWSHTTPResponse> {
        eventLoop.makeSucceededFuture(
            FakeHTTPResponse(
                status: .noContent,
                headers: [:]
            )
        )
    }
    
    public func shutdown(queue: DispatchQueue, _ callback: @escaping (Error?) -> Void) { }
    
    public var eventLoopGroup: EventLoopGroup
    
    public init(eventLoopGroup: EventLoopGroup) {
        self.eventLoopGroup = eventLoopGroup
    }
}

private struct FakeHTTPResponse: AWSHTTPResponse {
    var status: HTTPResponseStatus
    var headers: HTTPHeaders
    var body: NIOCore.ByteBuffer?
}
