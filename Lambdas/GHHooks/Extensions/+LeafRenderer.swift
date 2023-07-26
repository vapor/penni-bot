import LeafKit
import NIO
@preconcurrency import AsyncHTTPClient
import Logging
import Foundation

extension LeafRenderer {
    private static let leafRendererThreadPool: NIOThreadPool = {
        let pool = NIOThreadPool(numberOfThreads: 1)
        pool.start()
        return pool
    }()

    static func forGHHooks(httpClient: HTTPClient, logger: Logger) throws -> LeafRenderer {
        let workingDir = FileManager.default.currentDirectoryPath
        let rootDirectory = "\(workingDir)/templates/GHHooksLambda"
        let configuration = LeafConfiguration(rootDirectory: rootDirectory)
        let fileIO = NonBlockingFileIO(threadPool: leafRendererThreadPool)
        let fileIOLeafSource = NIOLeafFiles(
            fileio: fileIO,
            limits: .default,
            sandboxDirectory: rootDirectory,
            viewDirectory: rootDirectory
        )
        let docsLeafSource = DocsLeafSource(
            httpClient: httpClient,
            logger: logger
        )
        let sources = LeafSources()
        try sources.register(source: "default", using: fileIOLeafSource)
        try sources.register(source: "docs", using: docsLeafSource)
        return LeafRenderer(
            configuration: configuration,
            sources: sources,
            eventLoop: httpClient.eventLoopGroup.any()
        )
    }

    func render(path: String, context: [String: LeafData]) async throws -> String {
        let buffer = try await self.render(path: "\(path).leaf", context: context).get()
        return String(buffer: buffer)
    }
}

private struct DocsLeafSource: LeafSource {

    enum Configuration {
        static var supportedFileNamePrefixes: Set<String> {
            ["translation_needed"]
        }
    }

    enum Errors: Error, CustomStringConvertible {
        case unsupportedTemplate(String)
        case badStatusCode(response: HTTPClient.Response)
        case emptyBody(template: String, response: HTTPClient.Response)

        var description: String {
            switch self {
            case .unsupportedTemplate(let template):
                return "unsupportedTemplate(\(template))"
            case .badStatusCode(let response):
                return "badStatusCode(\(response))"
            case .emptyBody(let template, let response):
                return "emptyBody(template: \(template), response: \(response))"
            }
        }
    }

    let httpClient: HTTPClient
    let logger: Logger

    func file(
        template: String,
        escape: Bool,
        on eventLoop: any EventLoop
    ) throws -> EventLoopFuture<ByteBuffer> {
        guard Configuration.supportedFileNamePrefixes.contains(where: {
            template.hasPrefix($0)
        }) else {
            return eventLoop.makeFailedFuture(Errors.unsupportedTemplate(template))
        }
        #warning("change")
        let repoURL = "https://raw.githubusercontent.com/vapor/docs/main"
        let url = "\(repoURL)/.github/workflows/translation-issue-template.md"
        let request = try HTTPClient.Request(url: url)
        return httpClient.execute(request: request).flatMapThrowing { response in
            guard response.status == .ok else {
                throw Errors.badStatusCode(response: response)
            }
            guard let body = response.body else {
                throw Errors.emptyBody(template: template, response: response)
            }
            return body
        }
    }
}
