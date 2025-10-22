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
    case decodingError
}
