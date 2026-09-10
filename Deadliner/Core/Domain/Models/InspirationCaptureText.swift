//
//  InspirationCaptureText.swift
//  Deadliner
//
//  Shared validation for every quick-inspiration entry point.
//

import Foundation

enum InspirationCaptureText {
    static func normalized(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
