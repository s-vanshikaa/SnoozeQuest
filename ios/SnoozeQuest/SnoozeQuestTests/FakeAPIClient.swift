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
    private var queuedErrors: [Error?] = []

    func stub<T>(path: String, value: T) {
        stubs[path] = value
    }

    /// Errors are thrown in call order, one per request, before falling back to `errorToThrow`.
    /// Lets tests simulate a batch where some calls succeed and others fail.
    func queueError(_ error: Error?) {
        queuedErrors.append(error)
    }

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        requestedEndpoints.append(endpoint)
        if !queuedErrors.isEmpty {
            if let error = queuedErrors.removeFirst() {
                throw error
            }
        } else if let errorToThrow {
            throw errorToThrow
        }
        guard let value = stubs[endpoint.path] as? T else {
            fatalError("FakeAPIClient: no stub configured for \(endpoint.path) returning \(T.self)")
        }
        return value
    }
}
