import AsyncHTTPClient
import DiscordHTTP
import DiscordModels
import Foundation
import GitHubAPI
import Markdown
import NIOPosix
import OpenAPIRuntime
import Rendering
import Shared
import SotoCore
import SwiftSemver
import Testing

@testable import GHHooksLambda
@testable import Logging

@Suite
actor GHHooksTests {
    let decoder: JSONDecoder = {
        var decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// The `…` (U+2026 Horizontal Ellipsis) character.
    let dots = "\u{2026}"

    let responseStorage: FakeResponseStorage
    let backgroundProcessorTask: Task<Void, Never>

    init() {
        setenv("DEPLOYMENT_ENVIRONMENT", "testing", 1)
        /// Disable logging
        LoggingSystem.bootstrapInternal(SwiftLogNoOpLogHandler.init)
        /// First reset the background runner
        let backgroundProcessor = BackgroundProcessor()
        /// Then reset the storage
        self.responseStorage = FakeResponseStorage(backgroundProcessor: backgroundProcessor)
        backgroundProcessorTask = Task<Void, Never> {
            await backgroundProcessor.run()
        }
    }

    deinit {
        backgroundProcessorTask.cancel()
    }

    @Test
    func unicodesPrefix() throws {
        do {
            let scalars_16 = "Hello, world! 👍🏾"
            let scalars_14 = "Hello, world! "
            let scalars_13 = "Hello, world!"
            let scalars_12 = "Hello, world"
            let scalars_11 = "Hello, worl"
            let scalars_6 = "Hello,"
            #expect(scalars_16.unicodesPrefix(17) == (1, scalars_16))
            #expect(scalars_16.unicodesPrefix(16) == (0, scalars_16))
            #expect(scalars_16.unicodesPrefix(15) == (0, scalars_14 + dots))
            #expect(scalars_16.unicodesPrefix(14) == (0, scalars_13 + dots))
            #expect(scalars_16.unicodesPrefix(13) == (0, scalars_12 + dots))
            #expect(scalars_16.unicodesPrefix(12) == (0, scalars_11 + dots))
            #expect(scalars_16.unicodesPrefix(7) == (0, scalars_6 + dots))
        }

        do {
            let scalars_11 = "👍🏿👍🏾👍🏽👍🏼👍🏻👍"
            let scalars_8 = "👍🏿👍🏾👍🏽👍🏼"
            let scalars_6 = "👍🏿👍🏾👍🏽"
            let scalars_4 = "👍🏿👍🏾"
            let scalars_2 = "👍🏿"
            #expect(scalars_11.unicodesPrefix(12) == (1, scalars_11))
            #expect(scalars_11.unicodesPrefix(11) == (0, scalars_11))
            #expect(scalars_11.unicodesPrefix(10) == (0, scalars_8 + dots))
            #expect(scalars_11.unicodesPrefix(9) == (0, scalars_8 + dots))
            #expect(scalars_11.unicodesPrefix(8) == (0, scalars_6 + dots))
            #expect(scalars_11.unicodesPrefix(7) == (0, scalars_6 + dots))
            #expect(scalars_11.unicodesPrefix(6) == (0, scalars_4 + dots))
            #expect(scalars_11.unicodesPrefix(4) == (0, scalars_2 + dots))
            #expect(scalars_11.unicodesPrefix(3) == (0, scalars_2 + dots))
            #expect(scalars_11.unicodesPrefix(2) == (0, dots))
            #expect(scalars_11.unicodesPrefix(1) == (0, dots))
        }

        do {
            let scalars_14 = "👩‍👩‍👧‍👦👨‍👨‍👧‍👦"
            let scalars_7 = "👩‍👩‍👧‍👦"
            #expect(scalars_14.unicodesPrefix(15) == (1, scalars_14))
            #expect(scalars_14.unicodesPrefix(14) == (0, scalars_14))
            #expect(scalars_14.unicodesPrefix(13) == (0, scalars_7 + dots))
            #expect(scalars_14.unicodesPrefix(10) == (0, scalars_7 + dots))
            #expect(scalars_14.unicodesPrefix(9) == (0, scalars_7 + dots))
            #expect(scalars_14.unicodesPrefix(8) == (0, scalars_7 + dots))
            #expect(scalars_14.unicodesPrefix(7) == (0, dots))
            #expect(scalars_14.unicodesPrefix(6) == (0, dots))
            #expect(scalars_14.unicodesPrefix(3) == (0, dots))
            #expect(scalars_14.unicodesPrefix(2) == (0, dots))
            #expect(scalars_14.unicodesPrefix(1) == (0, dots))
        }
    }

    @Test
    func markdownUnicodesPrefix() async throws {
        do {
            let scalars_16 = "Hello, world! 👍🏾"
            let scalars_14 = "Hello, world! "
            let scalars_13 = "Hello, world!"
            let scalars_12 = "Hello, world"
            let scalars_11 = "Hello, worl"
            let scalars_6 = "Hello,"
            #expect(scalars_16.markdownUnicodesPrefix(17) == (1, scalars_16))
            #expect(scalars_16.markdownUnicodesPrefix(16) == (0, scalars_16))
            #expect(scalars_16.markdownUnicodesPrefix(15) == (0, scalars_14 + dots))
            #expect(scalars_16.markdownUnicodesPrefix(14) == (0, scalars_13 + dots))
            #expect(scalars_16.markdownUnicodesPrefix(13) == (0, scalars_12 + dots))
            #expect(scalars_16.markdownUnicodesPrefix(12) == (0, scalars_11 + dots))
            #expect(scalars_16.markdownUnicodesPrefix(7) == (0, scalars_6 + dots))
        }

        do {
            let scalars_11 = "👍🏿👍🏾👍🏽👍🏼👍🏻👍"
            let scalars_8 = "👍🏿👍🏾👍🏽👍🏼"
            let scalars_6 = "👍🏿👍🏾👍🏽"
            let scalars_4 = "👍🏿👍🏾"
            let scalars_2 = "👍🏿"
            #expect(scalars_11.markdownUnicodesPrefix(12) == (1, scalars_11))
            #expect(scalars_11.markdownUnicodesPrefix(11) == (0, scalars_11))
            #expect(scalars_11.markdownUnicodesPrefix(10) == (0, scalars_8 + dots))
            #expect(scalars_11.markdownUnicodesPrefix(9) == (0, scalars_8 + dots))
            #expect(scalars_11.markdownUnicodesPrefix(8) == (0, scalars_6 + dots))
            #expect(scalars_11.markdownUnicodesPrefix(7) == (0, scalars_6 + dots))
            #expect(scalars_11.markdownUnicodesPrefix(6) == (0, scalars_4 + dots))
            #expect(scalars_11.markdownUnicodesPrefix(4) == (0, scalars_2 + dots))
            #expect(scalars_11.markdownUnicodesPrefix(3) == (0, scalars_2 + dots))
            #expect(scalars_11.markdownUnicodesPrefix(2) == (0, dots))
            #expect(scalars_11.markdownUnicodesPrefix(1) == (0, dots))
        }

        do {
            let scalars_14 = "👩‍👩‍👧‍👦👨‍👨‍👧‍👦"
            let scalars_7 = "👩‍👩‍👧‍👦"
            #expect(scalars_14.markdownUnicodesPrefix(15) == (1, scalars_14))
            #expect(scalars_14.markdownUnicodesPrefix(14) == (0, scalars_14))
            #expect(scalars_14.markdownUnicodesPrefix(13) == (0, scalars_7 + dots))
            #expect(scalars_14.markdownUnicodesPrefix(10) == (0, scalars_7 + dots))
            #expect(scalars_14.markdownUnicodesPrefix(9) == (0, scalars_7 + dots))
            #expect(scalars_14.markdownUnicodesPrefix(8) == (0, scalars_7 + dots))
            #expect(scalars_14.markdownUnicodesPrefix(7) == (0, dots))
            #expect(scalars_14.markdownUnicodesPrefix(6) == (0, dots))
            #expect(scalars_14.markdownUnicodesPrefix(3) == (0, dots))
            #expect(scalars_14.markdownUnicodesPrefix(2) == (0, dots))
            #expect(scalars_14.markdownUnicodesPrefix(1) == (0, dots))
        }

        /// Testing with markdown text
        do {
            let scalars_9 = "**Hello**"
            let scalars_8 = "**Hel\(dots)**"
            let scalars_7 = "**He\(dots)**"
            let scalars_6 = "**H\(dots)**"
            let scalars_5 = "**\(dots)**"
            #expect(scalars_9.markdownUnicodesPrefix(10) == scalars_9)
            #expect(scalars_9.markdownUnicodesPrefix(9) == scalars_9)
            #expect(scalars_9.markdownUnicodesPrefix(8) == scalars_9)
            #expect(scalars_9.markdownUnicodesPrefix(7) == scalars_9)
            #expect(scalars_9.markdownUnicodesPrefix(6) == scalars_9)
            #expect(scalars_9.markdownUnicodesPrefix(5) == scalars_9)
            #expect(scalars_9.markdownUnicodesPrefix(4) == scalars_8)
            #expect(scalars_9.markdownUnicodesPrefix(3) == scalars_7)
            #expect(scalars_9.markdownUnicodesPrefix(2) == scalars_6)
            #expect(scalars_9.markdownUnicodesPrefix(1) == scalars_5)
        }
    }

    @Test
    func semVerBumpNoForcePrerelease() throws {
        do {
            let version = try #require(SemanticVersion(string: "11.0.0"))
            /// Does not bump major versions to avoid releasing a whole new major version.
            #expect(version.next(.major, forcePrerelease: false) == nil)
        }

        do {
            let version = try #require(SemanticVersion(string: "2.12.0"))
            let next = try #require(version.next(.minor, forcePrerelease: false))
            #expect(next.description == "2.13.0")
        }

        do {
            let version = try #require(SemanticVersion(string: "0.0.299"))
            let next = try #require(version.next(.patch, forcePrerelease: false))
            #expect(next.description == "0.0.300")
        }

        do {
            let version = try #require(SemanticVersion(string: "122.9.67-alpha.1"))
            let next = version.next(.major, forcePrerelease: false)
            #expect(next == nil)
        }

        do {
            let version = try #require(SemanticVersion(string: "122.9.67-alpha.44.55"))
            let next = version.next(.minor, forcePrerelease: false)
            #expect(next == nil)
        }

        do {
            let version = try #require(SemanticVersion(string: "122.9.67-alpha"))
            let next = try #require(version.next(.patch, forcePrerelease: false))
            #expect(next.description == "122.9.67-alpha.1")
        }

        do {
            let version = try #require(SemanticVersion(string: "122.9.67-alpha"))
            let next = try #require(version.next(.minor, forcePrerelease: false))
            #expect(next.description == "122.9.67-alpha.1")
        }

        do {
            let version = try #require(SemanticVersion(string: "122.9.67-alpha.1"))
            let next = try #require(version.next(.patch, forcePrerelease: false))
            #expect(next.description == "122.9.67-alpha.2")
        }

        do {
            let version = try #require(SemanticVersion(string: "122.9.67-alpha.1"))
            let next = try #require(version.next(.minor, forcePrerelease: false))
            #expect(next.description == "122.9.67-alpha.2")
        }

        do {
            let version = try #require(SemanticVersion(string: "122.9.67-beta.1"))
            let next = try #require(version.next(.minor, forcePrerelease: false))
            #expect(next.description == "122.9.67-beta.2")
        }

        do {
            let version = try #require(SemanticVersion(string: "122.9.67-hdaoidhas.1"))
            let next = try #require(version.next(.minor, forcePrerelease: false))
            #expect(next.description == "122.9.67-hdaoidhas.2")
        }
    }

    @Test
    func semVerBumpForcePrerelease() throws {
        do {
            let version = try #require(SemanticVersion(string: "11.0.0"))
            /// Does not bump major versions to avoid releasing a whole new major version.
            #expect(version.next(.major, forcePrerelease: true) == nil)
        }

        do {
            let version = try #require(SemanticVersion(string: "2.12.0"))
            let next = try #require(version.next(.minor, forcePrerelease: true))
            #expect(next.description == "2.12.0-alpha.1")
        }

        do {
            let version = try #require(SemanticVersion(string: "0.0.299"))
            let next = try #require(version.next(.patch, forcePrerelease: true))
            #expect(next.description == "0.0.299-alpha.1")
        }

        do {
            let version = try #require(SemanticVersion(string: "122.9.67-alpha.1"))
            let next = version.next(.major, forcePrerelease: true)
            #expect(next == nil)
        }

        do {
            let version = try #require(SemanticVersion(string: "122.9.67-alpha.44.55"))
            let next = version.next(.minor, forcePrerelease: true)
            #expect(next == nil)
        }

        do {
            let version = try #require(SemanticVersion(string: "122.9.67-alpha"))
            let next = try #require(version.next(.patch, forcePrerelease: true))
            #expect(next.description == "122.9.67-alpha.1")
        }

        do {
            let version = try #require(SemanticVersion(string: "122.9.67-alpha"))
            let next = try #require(version.next(.minor, forcePrerelease: true))
            #expect(next.description == "122.9.67-alpha.1")
        }

        do {
            let version = try #require(SemanticVersion(string: "122.9.67-alpha.1"))
            let next = try #require(version.next(.patch, forcePrerelease: true))
            #expect(next.description == "122.9.67-alpha.2")
        }

        do {
            let version = try #require(SemanticVersion(string: "122.9.67-alpha.1"))
            let next = try #require(version.next(.minor, forcePrerelease: true))
            #expect(next.description == "122.9.67-alpha.2")
        }

        do {
            let version = try #require(SemanticVersion(string: "122.9.67-beta.1"))
            let next = try #require(version.next(.minor, forcePrerelease: true))
            #expect(next.description == "122.9.67-beta.2")
        }

        do {
            let version = try #require(SemanticVersion(string: "122.9.67-hdaoidhas.1"))
            let next = try #require(version.next(.minor, forcePrerelease: true))
            #expect(next.description == "122.9.67-hdaoidhas.2")
        }
    }

    @Test
    func markdownFormatting() async throws {
        do {
            let scalars_206 =
                "Add new, fully source-compatible APIs to `JWTSigners` and `JWTSigner` which allow specifying custom `JSONEncoder` and `JSONDecoder` instances. (The ability to use non-Foundation JSON coders is not included)"
            let formatted = scalars_206.formatMarkdown(
                maxVisualLength: 256,
                hardLimit: 2_048,
                trailingTextMinLength: 64
            )
            expectMultilineStringsEqual(formatted, scalars_206)
        }

        do {
            let scalars_206 =
                "Add new, fully source-compatible APIs to `JWTSigners` and `JWTSigner` which allow specifying custom `JSONEncoder` and `JSONDecoder` instances. (The ability to use non-Foundation JSON coders is not included)"
            let formatted = scalars_206.formatMarkdown(
                maxVisualLength: 200,
                hardLimit: 2_048,
                trailingTextMinLength: 64
            )
            expectMultilineStringsEqual(formatted, scalars_206)
        }

        do {
            let scalars_206 =
                "Add new, fully source-compatible APIs to `JWTSigners` and `JWTSigner` which allow specifying custom `JSONEncoder` and `JSONDecoder` instances. (The ability to use non-Foundation JSON coders is not included)"
            let formatted = scalars_206.formatMarkdown(
                maxVisualLength: 200,
                hardLimit: 203,
                trailingTextMinLength: 64
            )
            expectMultilineStringsEqual(
                formatted,
                """
                Add new, fully source-compatible APIs to `JWTSigners` and `JWTSigner` which allow specifying custom `JSONEncoder` and `JSONDecoder` instances. (The ability to use non-Foundation JSON coders is not inclu\(dots)
                """
            )
        }

        do {
            let text = """
                ```
                Hello, how are you?
                ```
                """
            let formatted = text.formatMarkdown(
                maxVisualLength: 10,
                hardLimit: 200,
                trailingTextMinLength: 64
            )
            expectMultilineStringsEqual(
                formatted,
                """
                ```
                Hello, ho\(dots)
                ```
                """
            )
        }

        /// Remove html and images + length limits.
        do {
            let scalars_206 =
                "Add new, fully source-compatible APIs to `JWTSigners` and `JWTSigner` which allow specifying custom `JSONEncoder` and `JSONDecoder` instances. (The ability to use non-Foundation JSON coders is not included)"
            let text = """
                <!-- 🚀 Thank you for contributing! -->

                ![test image](https://github.com/vapor/something/9j13e91j3e9j03jr0j230dm02)

                <!-- Describe your changes clearly and use examples if possible -->

                \(scalars_206)

                <img width="1273" alt="Vapor_docs_dark" src="https://gthub.com/vapor/docs/assets/54376466/109dbef2-a090-49ef-9db7-9952dd848e13">

                Custom coders specified for a single `JWTSigner` affect token parsing and signing performed only by that signer. Custom coders specified on a `JWTSigners` object will become the default coders for all signers added to that object, unless a given signer already specifies its own custom coders.
                """

            let formatted = text.formatMarkdown(
                maxVisualLength: 256,
                hardLimit: 2_048,
                trailingTextMinLength: 64
            )
            #expect(formatted == scalars_206 + "\n\(dots)")
        }

        /// Remove html and images + length limits.
        do {
            let scalars_200 =
                "Add new, fully source-compatible APIs to `JWTSigners` and `JWTSigner` which allow specifying custom `JSONEncoder` and `JSONDecoder` instances. (The ability to use non-Foundation JSON coders is not int"
            let text = """
                <!-- 🚀 Thank you for contributing! -->

                ![test image](https://github.com/vapor/something/9j13e91j3e9j03jr0j230dm02)

                <!-- Describe your changes clearly and use examples if possible -->

                \(scalars_200)

                <img width="1273" alt="Vapor_docs_dark" src="https://github.com/vapor/docs/assets/54376466/109dbef2-a090-49ef-9db7-9952dd848e13">

                Custom coders specified for a single `JWTSigner` affect token parsing and signing performed only by that signer. Custom coders specified on a `JWTSigners` object will become the default coders for all signers added to that object, unless a given signer already specifies its own custom coders.
                """

            let formatted = text.formatMarkdown(
                maxVisualLength: 256,
                hardLimit: 2_048,
                trailingTextMinLength: 64
            )
            let scalars_66 = "Custom coders specified for a single `JWTSigner` affect token par…"
            expectMultilineStringsEqual(
                formatted,
                scalars_200 + """


                    \(scalars_66)
                    """
            )
        }

        /// Remove html and images + length limits.
        do {
            let scalars_190 =
                "Add new, fully source-compatible APIs to `JWTSigners` and `JWTSigner` which allow specifying custom `JSONEncoder` and `JSONDecoder` instances. (The ability to use non-Foundation JSON coders)"
            let text = """
                <!-- 🚀 Thank you for contributing! -->

                ![test image](https://github.com/vapor/something/9j13e91j3e9j03jr0j230dm02)

                <!-- Describe your changes clearly and use examples if possible -->

                \(scalars_190)

                <img width="1273" alt="Vapor_docs_dark" src="https://github.com/vapor/docs/assets/54376466/109dbef2-a090-49ef-9db7-9952dd848e13">

                Custom coders specified for a single `JWTSigner` affect token parsing and signing performed only by that signer. Custom coders specified on a `JWTSigners` object will become the default coders for all signers added to that object, unless a given signer already specifies its own custom coders.
                """

            let formatted = text.formatMarkdown(
                maxVisualLength: 256,
                hardLimit: 2_048,
                trailingTextMinLength: 64
            )
            let scalars_76 = "Custom coders specified for a single `JWTSigner` affect token parsing and s…"
            expectMultilineStringsEqual(
                formatted,
                scalars_190 + """


                    \(scalars_76)
                    """
            )
        }

        /// Remove html and images + length limits.
        do {
            let scalars_aLot =
                "Add new, fully source-compatible APIs to `JWTSigners` and `JWTSigner` which allow specifying custom `JSONEncoder` and `JSONDecoder` instances. (The ability to use non-Foundation JSON coders) Custom coders specified for a single `JWTSigner` affect token parsing and signing performed only by that signer. Custom coders specified"
            let text = """
                <!-- 🚀 Thank you for contributing! -->

                ![test image](https://github.com/vapor/something/9j13e91j3e9j03jr0j230dm02)

                <!-- Describe your changes clearly and use examples if possible -->

                \(scalars_aLot)

                <img width="1273" alt="Vapor_docs_dark" src="https://github.com/vapor/docs/assets/54376466/109dbef2-a090-49ef-9db7-9952dd848e13">

                on a `JWTSigners` object will become the default coders for all signers added to that object, unless a given signer already specifies its own custom coders.
                """

            let formatted = text.formatMarkdown(
                maxVisualLength: 256,
                hardLimit: 2_048,
                trailingTextMinLength: 64
            )
            expectMultilineStringsEqual(
                formatted,
                "Add new, fully source-compatible APIs to `JWTSigners` and `JWTSigner` which allow specifying custom `JSONEncoder` and `JSONDecoder` instances. (The ability to use non-Foundation JSON coders) Custom coders specified for a single `JWTSigner` affect token parsing and …"
            )
        }

        /// Remove empty links
        do {
            let text = """
                Bumps [sass](https://github.com/sass/dart-sass) from 1.63.6 to 1.64.0.

                [![Dependabot compatibility score](https://dependabot-badges.githubapp.com/badges/compatibility_score?dependency-name=sass&package-manager=npm_and_yarn&previous-version=1.63.6&new-version=1.64.0)](https://docs.github.com/en/github/managing-security-vulnerabilities/about-dependabot-security-updates#about-compatibility-scores)

                Dependabot will resolve any conflicts with this PR as long as you don't alter it yourself. You can also trigger a rebase manually by commenting `@dependabot rebase`.

                [//]: # (dependabot-automerge-start)
                [//]: # (dependabot-automerge-end)

                ---

                <details>
                <summary>Dependabot commands and options</summary>
                <br />

                You can trigger Dependabot actions by commenting on this PR:
                """

            let formatted = text.formatMarkdown(
                maxVisualLength: 256,
                hardLimit: 2_048,
                trailingTextMinLength: 96
            )
            expectMultilineStringsEqual(
                formatted,
                """
                Bumps [sass](https://github.com/sass/dart-sass) from 1.63.6 to 1.64.0.

                Dependabot will resolve any conflicts with this PR as long as you don’t alter it yourself. You can also trigger a rebase manually by commenting `@dependabot rebase`.
                \(dots)
                """
            )
        }

        do {
            let text = """
                ### Describe the bug

                I've got a custom `Codable` type that throws an error when decoding... because it's being asked to decode an empty string, rather than being skipped because I've got `T?` rather than `T` as the type in my `Content`.

                ### To Reproduce

                1. Declare some custom `Codable` type that throws an error if told to decode from an empty string.
                2. Declare some custom `Content` struct that has an `Optional` of your custom type as a parameter.
                3. Have a browser submit a request that includes `yourThing: ` in the body. (Doable in Safari by creating an HTML form, giving it a date input with the right `name`, and then... not selecting a date before hitting submit)
                4. Observe thrown error.
                """

            let formatted = text.formatMarkdown(
                maxVisualLength: 256,
                hardLimit: 2_048,
                trailingTextMinLength: 96
            )
            // TODO: Handle this situation better os we don't end up with an empty list item.
            expectMultilineStringsEqual(
                formatted,
                """
                ### Describe the bug

                I’ve got a custom `Codable` type that throws an error when decoding… because it’s being asked to decode an empty string, rather than being skipped because I’ve got `T?` rather than `T` as the type in my `Content`.

                ### To Reproduce

                1.
                \(dots)
                """
            )
        }

        do {
            let text = """
                ### Describe the bug

                White text on white background is not readable.

                ### To Reproduce

                Go to [https://api.vapor.codes/fluent/documentation/fluent/](https://api.vapor.codes/fluent/documentation/fluent/)

                ### Expected behavior

                Expect some contrast between the text and the background.

                ### Environment

                * Vapor Framework version: current [https://api.vapor.codes/](https://api.vapor.codes/) website
                * Vapor Toolbox version: N/A
                * OS version: N/A
                """

            let formatted = text.formatMarkdown(
                maxVisualLength: 256,
                hardLimit: 2_048,
                trailingTextMinLength: 96
            )

            expectMultilineStringsEqual(
                formatted,
                """
                ### Describe the bug

                White text on white background is not readable.

                ### To Reproduce

                Go to <https://api.vapor.codes/fluent/documentation/fluent/>

                ### Expected behavior

                Expect some contrast between the text and the background.
                \(dots)
                """
            )
        }

        do {
            let text = """
                Final stage of Vapor's `Sendable` journey as `Request` is now `Sendable`.

                There should be no more `Sendable` warnings in Vapor, even with complete concurrency checking turned on.
                """

            let formatted = text.formatMarkdown(
                maxVisualLength: 256,
                hardLimit: 2_048,
                trailingTextMinLength: 128
            )

            expectMultilineStringsEqual(
                formatted,
                """
                Final stage of Vapor’s `Sendable` journey as `Request` is now `Sendable`.

                There should be no more `Sendable` warnings in Vapor, even with complete concurrency checking turned on.
                """
            )
        }

        /// Test modifying GitHub links
        do {
            let text = """
                https://github.com/swift-server/swiftly/pull/9Final stage of Vapor’s `Sendable` journey as `Request` is now [#40](https://github.com/swift-server/swiftly/pull/9) `Sendable` at https://github.com/swift-server/swiftly/pull/9.

                There should https://github.com/vapor-bad-link/issues/44 be no more `Sendable` warnings in Vapor https://github.com/vapor/penny-bot/issues/98, even with complete concurrency checking turned on.](https://github.com/vapor/penny-bot/issues/98
                """

            let formatted = text.formatMarkdown(
                maxVisualLength: 512,
                hardLimit: 2_048,
                trailingTextMinLength: 128
            )

            expectMultilineStringsEqual(
                formatted,
                """
                [swift-server/swiftly#9](https://github.com/swift-server/swiftly/pull/9)Final stage of Vapor’s `Sendable` journey as `Request` is now [#40](https://github.com/swift-server/swiftly/pull/9) `Sendable` at [swift-server/swiftly#9](https://github.com/swift-server/swiftly/pull/9).

                There should https://github.com/vapor-bad-link/issues/44 be no more `Sendable` warnings in Vapor [vapor/penny-bot#98](https://github.com/vapor/penny-bot/issues/98), even with complete concurrency checking turned on.]([vapor/penny-bot#98](https://github.com/vapor/penny-bot/issues/98)
                """
            )
        }
    }

    @Test
    func headingFinder() async throws {
        /// Goes into the `What's Changed` heading.
        let text = """
            ## What's Changed
            * Use HTTP Client from vapor and update APNS library, add multiple configs by @kylebrowning in https://github.com/vapor/apns/pull/46
            * Update package to use Alpha 5 by @kylebrowning in https://github.com/vapor/apns/pull/48
            * Add support for new version of APNSwift by @Gerzer in https://github.com/vapor/apns/pull/51
            * Update to latest APNS by @kylebrowning in https://github.com/vapor/apns/pull/52

            ## New Contributors
            * @Gerzer made their first contribution in https://github.com/vapor/apns/pull/51

            **Full Changelog**: https://github.com/vapor/apns/compare/3.0.0...4.0.0
            """

        let contentsOfHeading = try #require(text.contentsOfHeading(named: "What's Changed"))
        expectMultilineStringsEqual(
            contentsOfHeading,
            """
            - Use HTTP Client from vapor and update APNS library, add multiple configs by @kylebrowning in https://github.com/vapor/apns/pull/46
            - Update package to use Alpha 5 by @kylebrowning in https://github.com/vapor/apns/pull/48
            - Add support for new version of APNSwift by @Gerzer in https://github.com/vapor/apns/pull/51
            - Update to latest APNS by @kylebrowning in https://github.com/vapor/apns/pull/52
            """
        )
    }

    @Test
    func parseCodeOwners() async throws {
        let text = """
            # This is a comment.
            # Each line is a file pattern followed by one or more owners.

            # These owners will be the default owners for everything in
            *       @global-owner1 @global-owner2

            *.js    @js-owner #This is an inline comment.

            *.go docs@example.com

            *.txt @octo-org/octocats
            /build/logs/ @doctocat

            # The `docs/*` pattern will match files like
            # `docs/getting-started.md` but not further nested files like
            # `docs/build-app/troubleshooting.md`.
            docs/*  docs@example.com

            apps/ @octocat
            /docs/ @doctocat
            /scripts/ @doctocat @octocat
            **/logs @octocat

            /apps/ @octocat
            /apps/github
            """
        let context = try makeContext(
            eventName: .pull_request,
            eventKey: "pr1"
        )
        let handler = try ReleaseMaker(
            context: context,
            pr: context.event.pull_request!,
            number: context.event.number!
        )
        let expected = [
            "docs@example.com", "doctocat", "global-owner1", "global-owner2", "js-owner", "octo-org/octocats",
            "octocat",
        ]
        #expect(handler.context.requester.parseCodeOwners(text: text).value.sorted() == expected)
    }

    @Test
    func makeReleaseBody() async throws {
        let context = try makeContext(
            eventName: .pull_request,
            eventKey: "pr4"
        )
        let handler = try ReleaseMaker(
            context: context,
            pr: context.event.pull_request!,
            number: context.event.number!
        )
        let body = try await handler.makeReleaseBody(
            mergedBy: context.event.pull_request!.mergedBy!,
            previousVersion: "v2.3.1",
            newVersion: "v2.4.5"
        )
        #expect(body.hasPrefix("## What's Changed"), "\(body)")
    }

    @Test
    func isPrimaryOrReleaseBranch() async throws {
        let context = try makeContext(
            eventName: .pull_request,
            eventKey: "pr3"
        )
        let repo = try #require(context.event.repository)

        #expect("main".isPrimaryOrReleaseBranch(repo: repo))

        #expect(!"mainiac".isPrimaryOrReleaseBranch(repo: repo))
        #expect(!"master".isPrimaryOrReleaseBranch(repo: repo))

        #expect("release/1.0.4".isPrimaryOrReleaseBranch(repo: repo))
        #expect("postgres-3.2.x".isPrimaryOrReleaseBranch(repo: repo))
        #expect("release/58.x".isPrimaryOrReleaseBranch(repo: repo))
        #expect("release/58.1".isPrimaryOrReleaseBranch(repo: repo))

        #expect(!"release/x.9".isPrimaryOrReleaseBranch(repo: repo))
        #expect(!"release/5.x.9".isPrimaryOrReleaseBranch(repo: repo))
        #expect(!"release/x".isPrimaryOrReleaseBranch(repo: repo))
        #expect(!"release/3".isPrimaryOrReleaseBranch(repo: repo))
        /// No pre-release / build identifiers supported
        #expect(!"postgres-my/branch#42.99.56-alpha.x".isPrimaryOrReleaseBranch(repo: repo))
        #expect(!"postgres-my/branch#42.99.56-alpha.1345".isPrimaryOrReleaseBranch(repo: repo))
    }

    @Test
    func findComparisonRange() async throws {
        let context = try makeContext(
            eventName: .release,
            eventKey: "release1"
        )
        let handler = try ReleaseReporter(context: context)
        let comparisonRange = handler.findComparisonRange()
        #expect(comparisonRange == "1.43.0...1.43.1")
    }

    @Test
    func handleIssueEvent1() async throws {
        try await handleEvent(key: "issue1", eventName: .issues, expect: .noResponse)
    }

    @Test
    func handleIssueEvent2() async throws {
        try await handleEvent(
            key: "issue2",
            eventName: .issues,
            expect: .response(at: .issuesAndPRs)
        )
    }

    @Test
    func handleIssueEvent3() async throws {
        try await handleEvent(key: "issue3", eventName: .issues, expect: .noResponse)
    }

    @Test
    func handleIssueEvent4() async throws {
        try await handleEvent(key: "issue4", eventName: .issues, expect: .noResponse)
    }

    @Test
    func handleIssueEvent5() async throws {
        try await handleEvent(
            key: "issue5",
            eventName: .issues,
            expect: .response(
                at: .issuesAndPRs,
                type: .edit(messageId: FakeMessageLookupRepo.randomMessageID)
            )
        )
    }

    // TODO: Add real response-JSONs for project board stuff to `ghRestOperations.json`.

    @Test
    func handleIssueEvent6() async throws {
        /// Labeled with "help wanted"
        try await handleEvent(key: "issue6", eventName: .issues, expect: .noResponse)
    }

    @Test
    func handleIssueEvent7() async throws {
        /// Unlabeled with "help wanted"
        try await handleEvent(key: "issue7", eventName: .issues, expect: .noResponse)
    }

    @Test
    func handleIssueEvent8() async throws {
        /// Issue-closed that has "timeline" info too, in case sometime in the future
        /// we want to be more accurate about reporting who closed the issue.
        /// See https://discord.com/channels/431917998102675485/441327731486097429/1155443078778323036.
        /// The message isn't public (doesn't contain anything too special tbh),
        /// only Penny maintainers can see it.
        try await handleEvent(key: "issue8", eventName: .issues, expect: .noResponse)
    }

    @Test
    func handlePREvent1() async throws {
        try await handleEvent(key: "pr1", eventName: .pull_request, expect: .noResponse)
    }

    @Test
    func handlePREvent2() async throws {
        try await handleEvent(key: "pr2", eventName: .pull_request, expect: .noResponse)
    }

    @Test
    func handlePREvent3() async throws {
        try await handleEvent(key: "pr3", eventName: .pull_request, expect: .noResponse)
    }

    @Test
    func handlePREvent4() async throws {
        try await handleEvent(
            key: "pr4",
            eventName: .pull_request,
            expect: .noResponse
        )
    }

    @Test
    func handlePREvent5() async throws {
        try await handleEvent(
            key: "pr5",
            eventName: .pull_request,
            expect: .noResponse
        )
    }

    @Test
    func handlePREvent6() async throws {
        try await handleEvent(
            key: "pr6",
            eventName: .pull_request,
            expect: .noResponse
        )
    }

    @Test
    func handlePREvent7() async throws {
        /// For now expect an error since there are no test values for
        /// the discord list-messages endpoint.
        try await handleEvent(
            key: "pr7",
            eventName: .pull_request,
            expect: .error(
                description:
                    "DiscordHTTPError.emptyBody(DiscordHTTPResponse(host: discord.com, status: 200 OK, version: HTTP/2.0, headers: [], body: nil))"
            )
        )
    }

    @Test
    func handlePREvent8() async throws {
        try await handleEvent(
            key: "pr8",
            eventName: .pull_request,
            expect: .noResponse
        )
    }

    @Test
    func handlePREvent9() async throws {
        try await handleEvent(
            key: "pr9",
            eventName: .pull_request,
            expect: .noResponse
        )
    }

    @Test
    func handlePREvent10() async throws {
        try await handleEvent(
            key: "pr10",
            eventName: .pull_request,
            expect: .noResponse
        )
    }

    @Test
    func handlePREvent11() async throws {
        try await handleEvent(
            key: "pr11",
            eventName: .pull_request,
            expect: .noResponse
        )
    }

    @Test
    func handlePREvent12() async throws {
        /// From `dependabot[bot]` so should be ignored
        try await handleEvent(
            key: "pr12",
            eventName: .pull_request,
            expect: .noResponse
        )
    }

    @Test
    func handlePREvent13() async throws {
        try await handleEvent(
            key: "pr13",
            eventName: .pull_request,
            expect: .response(at: .issuesAndPRs, type: .create)
        )
    }

    @Test("PR with [DNM] prefix where author_association is CONTRIBUTOR should not be posted to Discord")
    func handlePREvent14() async throws {
        try await handleEvent(
            key: "pr14",
            eventName: .pull_request,
            expect: .noResponse
        )
    }

    @Test
    func handlePushEvent1() async throws {
        try await handleEvent(
            key: "push1",
            eventName: .push,
            expect: .noResponse
        )
    }

    @Test
    func handlePushEvent2() async throws {
        // TODO: Should assert that `create_issue` endpoint is called after this.
        try await handleEvent(
            key: "push2",
            eventName: .push,
            expect: .noResponse
        )
    }

    @Test
    func handlePushEvent3() async throws {
        try await handleEvent(
            key: "push3",
            eventName: .push,
            expect: .noResponse
        )
    }

    @Test
    func handlePushEvent4() async throws {
        try await handleEvent(
            key: "push4",
            eventName: .push,
            expect: .noResponse
        )
    }

    @Test
    func handlePushEvent5() async throws {
        try await handleEvent(
            key: "push5",
            eventName: .push,
            expect: .response(at: .thanks, type: .create, count: 2)
        )
    }

    @Test
    func handleReleaseEvent1() async throws {
        try await handleEvent(
            key: "release1",
            eventName: .release,
            expect: .noResponse
        )
    }

    @Test
    func handleReleaseEvent2() async throws {
        try await handleEvent(
            key: "release2",
            eventName: .release,
            expect: .response(at: .release, type: .create)
        )
    }

    @Test
    func handleReleaseEvent3() async throws {
        try await handleEvent(
            key: "release3",
            eventName: .release,
            expect: .noResponse
        )
    }

    @Test
    func handleReleaseEvent4() async throws {
        try await handleEvent(
            key: "release4",
            eventName: .release,
            expect: .noResponse
        )
    }

    @Test
    func handleReleaseEvent5() async throws {
        try await handleEvent(
            key: "release5",
            eventName: .release,
            expect: .response(at: .release, type: .create)
        )
    }

    @Test
    func handleReleaseEvent6() async throws {
        try await handleEvent(
            key: "release6",
            eventName: .release,
            expect: .response(at: .release, type: .create)
        )
    }

    @Test
    func handleOtherEvent1() async throws {
        try await handleEvent(
            key: "projects_v2_item1",
            eventName: .projects_v2_item,
            expect: .noResponse
        )
    }

    @Test
    func handleOtherEvent2() async throws {
        try await handleEvent(
            key: "installation_repos1",
            eventName: .installation_repositories,
            expect: .noResponse
        )
    }

    func handleEvent(
        key: String,
        eventName: GHEvent.Kind,
        expect: Expectation,
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) async throws {
        let data = TestData.for(ghEventKey: key)!
        do {
            let event = try decoder.decode(GHEvent.self, from: data)
            try await EventHandler(
                context: makeContext(
                    eventName: eventName,
                    event: event
                )
            ).handle()
            switch expect {
            case let .response(channel, responseType, count):
                precondition(count > 0)
                for _ in 0..<count {
                    switch responseType {
                    case .create:
                        let response = await self.responseStorage.awaitResponse(
                            at: .createMessage(channelId: channel.id),
                            sourceLocation: sourceLocation
                        ).value
                        #expect(
                            "\(type(of: response))" == "\(Payloads.CreateMessage.self)",
                            sourceLocation: sourceLocation
                        )
                    case let .edit(messageId):
                        let response = await self.responseStorage.awaitResponse(
                            at: .updateMessage(channelId: channel.id, messageId: messageId),
                            sourceLocation: sourceLocation
                        ).value
                        #expect(
                            "\(type(of: response))" == "\(Payloads.EditMessage.self)",
                            sourceLocation: sourceLocation
                        )
                    }
                }
            case let .failure(failures):
                await withTaskGroup(of: Void.self) { group in
                    for failure in failures {
                        group.addTask {
                            let endpoint: APIEndpoint
                            switch failure.type {
                            case .create:
                                endpoint = .createMessage(channelId: failure.channel.id)
                            case let .edit(messageID):
                                endpoint = .updateMessage(
                                    channelId: failure.channel.id,
                                    messageId: messageID
                                )
                            }
                            let response = await self.responseStorage.awaitResponse(
                                at: endpoint,
                                expectFailure: true,
                                sourceLocation: sourceLocation
                            ).value
                            #expect(
                                "\(type(of: response))" == "Optional<Never>",
                                sourceLocation: sourceLocation
                            )
                        }
                    }
                }
            case .error:
                break
            }
        } catch {
            if case let .error(description) = expect,
                description == "\(error)"
            {
                /// Expected error
                return
            }

            let prettyJSON = try! JSONSerialization.data(
                withJSONObject: JSONSerialization.jsonObject(with: data),
                options: .prettyPrinted
            )
            let event = String(decoding: prettyJSON, as: UTF8.self)
            Issue.record(
                """
                Failed handling event.
                Error: \(error).
                Event name: \(eventName).
                Event: \(event).
                """,
                sourceLocation: sourceLocation
            )
        }
    }

    func makeContext(eventName: GHEvent.Kind, eventKey: String) throws -> HandlerContext {
        let data = TestData.for(ghEventKey: eventKey)!
        let event = try decoder.decode(GHEvent.self, from: data)
        return try makeContext(
            eventName: eventName,
            event: event
        )
    }

    func makeContext(eventName: GHEvent.Kind, event: GHEvent) throws -> HandlerContext {
        let logger = Logger(label: "GHHooksTests")
        return HandlerContext(
            eventName: eventName,
            event: event,
            httpClient: .shared,
            discordClient: FakeDiscordClient(responseStorage: self.responseStorage),
            githubClient: Client(
                serverURL: try Servers.Server1.url(),
                transport: FakeClientTransport()
            ),
            renderClient: RenderClient(
                renderer: try .forGHHooks(
                    httpClient: .shared,
                    logger: logger
                )
            ),
            messageLookupRepo: FakeMessageLookupRepo(),
            usersService: FakeUsersService(),
            requester: FakeRequester(),
            logger: logger
        )
    }

    enum Expectation {

        enum ResponseKind {
            case create
            case edit(messageId: MessageSnowflake)
        }

        struct Failure {
            let channel: GHHooksLambda.Constants.Channels
            let type: ResponseKind
        }

        case response(at: GHHooksLambda.Constants.Channels, type: ResponseKind = .create, count: Int = 1)
        case failure([Failure])
        case error(description: String)

        /// Checks for no responses in any of the channels.
        static var noResponse: Self {
            .failure(Constants.Channels.allCases.map({ .init(channel: $0, type: .create) }))
        }
    }
}
