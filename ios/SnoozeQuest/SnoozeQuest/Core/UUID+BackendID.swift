//
//  UUID+BackendID.swift
//  SnoozeQuest
//
//  Domain models use UUID identifiers, but the backend uses integer primary
//  keys. This embeds an integer ID into a stable, deterministic UUID so the
//  same backend row always maps to the same UUID across fetches (important
//  for SwiftUI identity/diffing), without pulling in a UUID-namespacing
//  dependency for what is otherwise a trivial 1:1 mapping.
//

import Foundation

extension UUID {
    init(backendID: Int) {
        self.init(uuidString: String(format: "00000000-0000-0000-0000-%012d", backendID))!
    }
}
