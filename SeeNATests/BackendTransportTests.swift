import Foundation
import XCTest
@testable import SEENACore

final class BackendTransportTests: XCTestCase {
    func testPermanentClientErrorsDoNotRetry() async throws {
        for status in [400, 401, 403, 404, 422] {
            let stub = ResponseSequence(statuses: [status, 200])
            let client = makeClient(stub)
            do {
                _ = try await client.explain(facts)
                XCTFail("HTTP \(status) should fail")
            } catch BackendClient.BackendError.serverStatus(let actual) {
                XCTAssertEqual(actual, status)
            }
            XCTAssertEqual(stub.requestCount, 1)
        }
    }

    func testTransientServiceFailureRetriesOnceThenSucceeds() async throws {
        let stub = ResponseSequence(statuses: [503, 200])
        let result = try await makeClient(stub).explain(facts)
        XCTAssertEqual(stub.requestCount, 2)
        XCTAssertEqual(result.headline, "Test response")
    }

    func testRepeatedServiceFailureStopsAfterTwoRequests() async throws {
        let stub = ResponseSequence(statuses: [503, 503, 200])
        do {
            _ = try await makeClient(stub).explain(facts)
            XCTFail("Repeated service failure should fail")
        } catch BackendClient.BackendError.serverStatus(let status) {
            XCTAssertEqual(status, 503)
        }
        XCTAssertEqual(stub.requestCount, 2)
    }

    func testURLCancellationIsNotRetried() async throws {
        let stub = ResponseSequence(statuses: [], error: URLError(.cancelled))
        do {
            _ = try await makeClient(stub).explain(facts)
            XCTFail("Cancellation should propagate")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled)
        }
        XCTAssertEqual(stub.requestCount, 1)
    }

    private var facts: ExplanationRequest {
        ExplanationRequest(locale: "en-AU", rightEye: nil, leftEye: nil,
                           comparisonCode: .repeatNeeded, actionCode: .noReliableResult,
                           limitations: [.notAPrescription], localIntegrityCode: .consistent)
    }

    private func makeClient(_ sequence: ResponseSequence) -> BackendClient {
        let host = UUID().uuidString.lowercased() + ".invalid"
        StubURLProtocol.register(sequence, host: host)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return BackendClient(
            configuration: NetworkConfiguration(baseURL: URL(string: "https://" + host), appToken: "test-only"),
            session: URLSession(configuration: configuration)
        )
    }
}

private final class ResponseSequence: @unchecked Sendable {
    private let lock = NSLock()
    private let statuses: [Int]
    private let error: URLError?
    private var count = 0
    init(statuses: [Int], error: URLError? = nil) { self.statuses = statuses; self.error = error }
    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    func next() -> (Int, URLError?) {
        lock.lock(); defer { lock.unlock() }
        let index = count
        count += 1
        return (statuses.isEmpty ? 0 : statuses[min(index, statuses.count - 1)], error)
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var sequences: [String: ResponseSequence] = [:]
    static func register(_ sequence: ResponseSequence, host: String) {
        lock.lock(); defer { lock.unlock() }
        sequences[host] = sequence
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let sequence = Self.sequences[request.url?.host ?? ""]
        Self.lock.unlock()
        guard let sequence, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let (status, error) = sequence.next()
        if let error { client?.urlProtocol(self, didFailWithError: error); return }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        let body = #"{"headline":"Test response","plainMeaning":"Test","limitations":[],"nextSteps":[],"disclaimer":"Not a prescription","verification":"notApplicable"}"#
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
