import XCTest
@testable import TubeShelfCore

final class LocalAITests: XCTestCase {
    func testEndpointAcceptsBaseOrFullPath() {
        let base = LocalAIConfig(baseURL: "http://127.0.0.1:1976/v1", model: "system")
        XCTAssertEqual(base.endpointURL?.absoluteString, "http://127.0.0.1:1976/v1/chat/completions")

        let trailing = LocalAIConfig(baseURL: "http://127.0.0.1:1976/v1/", model: "system")
        XCTAssertEqual(trailing.endpointURL?.absoluteString, "http://127.0.0.1:1976/v1/chat/completions")

        let full = LocalAIConfig(baseURL: "http://127.0.0.1:1976/v1/chat/completions", model: "system")
        XCTAssertEqual(full.endpointURL?.absoluteString, "http://127.0.0.1:1976/v1/chat/completions")

        XCTAssertNil(LocalAIConfig(baseURL: "not a url", model: "system").endpointURL)
        XCTAssertNil(LocalAIConfig(baseURL: "ftp://127.0.0.1/v1", model: "system").endpointURL)
    }

    func testParseKeepsKnownCategoriesAndDropsPeople() {
        let known = ["Joe Rogan", "Talks & Podcasts"]
        let tags = LocalAIClient.parse(
            content: "AI & Machine Learning, Joe Rogan, Marc Andreessen, \"Talks & Podcasts\"",
            knownCategories: known
        )
        XCTAssertEqual(tags, ["AI & Machine Learning", "Joe Rogan", "Talks & Podcasts"])
    }

    func testParseHandlesBulletsNewlinesAndDuplicates() {
        let tags = LocalAIClient.parse(
            content: "- AI & Machine Learning\n- Podcasts\n* ai & machine learning\n",
            knownCategories: []
        )
        XCTAssertEqual(tags, ["AI & Machine Learning", "Talks & Podcasts"])
    }

    func testParseRespectsLimit() {
        let tags = LocalAIClient.parse(
            content: "AI & Machine Learning, Education, Programming, Cooking",
            knownCategories: [],
            limit: 2
        )
        XCTAssertEqual(tags.count, 2)
    }

    func testClientSendsAConstrainedPromptAndReadsChoices() async throws {
        StubChatProtocol.payload = Data(#"""
        {"choices":[{"message":{"content":"AI & Machine Learning, Talks & Podcasts"}}]}
        """#.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubChatProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = LocalAIClient(
            config: LocalAIConfig(baseURL: "http://127.0.0.1:1976/v1", model: "system"),
            session: session
        )

        let tags = try await client.suggest(
            title: "Marc Andreessen: The real AI boom",
            channel: "Lenny's Podcast",
            description: "A conversation.",
            knownCategories: ["Joe Rogan"]
        )

        XCTAssertEqual(tags, ["AI & Machine Learning", "Talks & Podcasts"])
        XCTAssertEqual(StubChatProtocol.lastPath, "/v1/chat/completions")
        let body = try XCTUnwrap(StubChatProtocol.lastBody)
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("\"model\":\"system\""), text)
        XCTAssertTrue(text.contains("Allowed categories"), text)
        XCTAssertTrue(text.contains("Joe Rogan"), "user categories are allowed: \(text)")
    }
}

private final class StubChatProtocol: URLProtocol {
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var lastPath: String?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastPath = request.url?.path
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            Self.lastBody = data
        } else {
            Self.lastBody = request.httpBody
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
