//
//  FakeAPIClient.swift
//  SnoozeQuestTests
//

import Foundation
@testable import SnoozeQuest

final class FakeAPIClient: APIClientProtocol {
    private(set) var requestedEndpoints: [Endpoint] = []
    private var stubs: [String: Any] = [:]
    var errorToThrow: Error?

    func stub<T>(path: String, value: T) {
        stubs[path] = value
    }

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        requestedEndpoints.append(endpoint)
        if let errorToThrow {
            throw errorToThrow
        }
        guard let value = stubs[endpoint.path] as? T else {
            fatalError("FakeAPIClient: no stub configured for \(endpoint.path) returning \(T.self)")
        }
        return value
    }
}
