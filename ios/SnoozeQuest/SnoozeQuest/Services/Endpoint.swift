//
//  Endpoint.swift
//  SnoozeQuest
//

import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
}

struct Endpoint {
    var path: String
    var method: HTTPMethod = .get
    var queryItems: [URLQueryItem] = []
    var body: Data?
}
