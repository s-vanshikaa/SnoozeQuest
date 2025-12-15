//
//  APIError.swift
//  SnoozeQuest
//

import Foundation

enum APIError: Error, Equatable {
    case invalidResponse
    case validationError(message: String)
    case serverError(statusCode: Int)
    case timeout
    case connectionFailed
    case rateLimited
    case decodingError

    /// Whether repeating the identical request could plausibly succeed.
    /// Validation and decoding failures will fail the same way every time.
    var isTransient: Bool {
        switch self {
        case .timeout, .connectionFailed, .rateLimited:
            return true
        case .serverError(let statusCode):
            return statusCode >= 500
        case .invalidResponse, .validationError, .decodingError:
            return false
        }
    }
}
