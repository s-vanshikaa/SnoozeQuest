//
//  APIClientTests.swift
//  SnoozeQuestTests
//

import Foundation
import Testing
@testable import SnoozeQuest

private struct FakeTransport: HTTPTransport {
    var result: Result<(Data, URLResponse), Error>
    var onRequest: ((URLRequest) -> Void)?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        onRequest?(request)
        return try result.get()
    }
}

private struct Sample: Codable, Equatable {
    let value: Int
}

private func httpResponse(statusCode: Int, url: URL = URL(string: "https://example.com/test")!) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

private func makeClient(transport: HTTPTransport) -> APIClient {
    APIClient(baseURL: URL(string: "https://example.com")!, transport: transport)
}

struct APIClientTests {
    @Test func successDecodesResponseBody() async throws {
        let data = try JSONEncoder().encode(Sample(value: 42))
        let client = makeClient(transport: FakeTransport(result: .success((data, httpResponse(statusCode: 200)))))

        let result: Sample = try await client.request(Endpoint(path: "/test"))

        #expect(result == Sample(value: 42))
    }

    @Test func requestIncludesMethodQueryItemsAndBody() async throws {
        var capturedRequest: URLRequest?
        let responseData = try JSONEncoder().encode(Sample(value: 1))
        let transport = FakeTransport(
            result: .success((responseData, httpResponse(statusCode: 200))),
            onRequest: { capturedRequest = $0 }
        )
        let client = makeClient(transport: transport)
        let body = try JSONEncoder().encode(Sample(value: 7))
        let endpoint = Endpoint(
            path: "/api/v1/sleep/sync",
            method: .post,
            queryItems: [URLQueryItem(name: "user_id", value: "1")],
            body: body
        )

        let _: Sample = try await client.request(endpoint)

        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.httpBody == body)
        #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(capturedRequest?.url?.absoluteString == "https://example.com/api/v1/sleep/sync?user_id=1")
    }

    @Test func decodesISO8601DatesWithAndWithoutFractionalSeconds() async throws {
        let json = """
        [{"date": "2026-08-17T18:11:15.837866Z"}, {"date": "2026-03-01T23:00:00Z"}]
        """
        struct DatedSample: Decodable { let date: Date }
        let transport = FakeTransport(result: .success((Data(json.utf8), httpResponse(statusCode: 200))))
        let client = makeClient(transport: transport)

        let result: [DatedSample] = try await client.request(Endpoint(path: "/test"))

        #expect(result.count == 2)
    }

    @Test func decodingErrorIsThrownForMalformedBody() async throws {
        let transport = FakeTransport(result: .success((Data("not json".utf8), httpResponse(statusCode: 200))))
        let client = makeClient(transport: transport)

        await #expect(throws: APIError.decodingError) {
            let _: Sample = try await client.request(Endpoint(path: "/test"))
        }
    }

    @Test func validationErrorExtractsSimpleDetailMessage() async throws {
        let body = Data(#"{"detail": "User not found"}"#.utf8)
        let transport = FakeTransport(result: .success((body, httpResponse(statusCode: 404))))
        let client = makeClient(transport: transport)

        await #expect(throws: APIError.validationError(message: "User not found")) {
            let _: Sample = try await client.request(Endpoint(path: "/test"))
        }
    }

    @Test func validationErrorExtractsFastAPIValidationDetail() async throws {
        let body = Data(#"{"detail": [{"msg": "end_time must be after start_time"}]}"#.utf8)
        let transport = FakeTransport(result: .success((body, httpResponse(statusCode: 422))))
        let client = makeClient(transport: transport)

        await #expect(throws: APIError.validationError(message: "end_time must be after start_time")) {
            let _: Sample = try await client.request(Endpoint(path: "/test"))
        }
    }

    @Test func serverErrorIsThrownForFiveHundredStatus() async throws {
        let transport = FakeTransport(result: .success((Data(), httpResponse(statusCode: 500))))
        let client = makeClient(transport: transport)

        await #expect(throws: APIError.serverError(statusCode: 500)) {
            let _: Sample = try await client.request(Endpoint(path: "/test"))
        }
    }

    @Test func timeoutMapsURLErrorTimedOut() async throws {
        let transport = FakeTransport(result: .failure(URLError(.timedOut)))
        let client = makeClient(transport: transport)

        await #expect(throws: APIError.timeout) {
            let _: Sample = try await client.request(Endpoint(path: "/test"))
        }
    }

    @Test func otherNetworkFailuresMapToInvalidResponse() async throws {
        let transport = FakeTransport(result: .failure(URLError(.notConnectedToInternet)))
        let client = makeClient(transport: transport)

        await #expect(throws: APIError.invalidResponse) {
            let _: Sample = try await client.request(Endpoint(path: "/test"))
        }
    }
}
