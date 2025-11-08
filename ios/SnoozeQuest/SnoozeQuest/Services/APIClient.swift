//
//  APIClient.swift
//  SnoozeQuest
//

import Foundation

protocol APIClientProtocol {
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T
}

protocol HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

final class APIClient: APIClientProtocol {
    private let baseURL: URL
    private let transport: HTTPTransport
    private let decoder: JSONDecoder

    init(baseURL: URL, transport: HTTPTransport = URLSession.shared, decoder: JSONDecoder = APIClient.makeDecoder()) {
        self.baseURL = baseURL
        self.transport = transport
        self.decoder = decoder
    }

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let urlRequest = try makeURLRequest(for: endpoint)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: urlRequest)
        } catch let error as URLError where error.code == .timedOut {
            throw APIError.timeout
        } catch {
            throw APIError.invalidResponse
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError
            }
        case 400...499:
            throw APIError.validationError(message: Self.extractErrorMessage(from: data))
        default:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    private func makeURLRequest(for endpoint: Endpoint) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint.path),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidResponse
        }
        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems
        }
        guard let url = components.url else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        if endpoint.body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private struct SimpleErrorBody: Decodable {
        let detail: String
    }

    private struct ValidationErrorBody: Decodable {
        struct Detail: Decodable { let msg: String }
        let detail: [Detail]
    }

    private static func extractErrorMessage(from data: Data) -> String {
        if let simple = try? JSONDecoder().decode(SimpleErrorBody.self, from: data) {
            return simple.detail
        }
        if let validation = try? JSONDecoder().decode(ValidationErrorBody.self, from: data),
           let firstMessage = validation.detail.first?.msg {
            return firstMessage
        }
        return "Request failed"
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]

        decoder.dateDecodingStrategy = .custom { valueDecoder in
            let container = try valueDecoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = fractionalFormatter.date(from: dateString) ?? standardFormatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }

        return decoder
    }
}
