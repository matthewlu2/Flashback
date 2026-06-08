//
//  PhoneNormalizer.swift
//  Flashback
//
//  Created by Claude on 6/7/26.
//

import Foundation

/// Lightweight phone normalization to a consistent E.164-ish form used purely for contact matching.
/// Both the stored profile number and scanned contact numbers run through the same logic so they match.
enum PhoneNormalizer {
    /// Default country calling code applied to numbers that have no explicit `+` prefix.
    static let defaultCountryCode = "1"

    /// Returns a normalized string like "+15551234567", or nil if it can't form a plausible number.
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let hasPlus = trimmed.hasPrefix("+")
        let digits = trimmed.filter { $0.isNumber }
        guard digits.count >= 7 else { return nil }

        if hasPlus {
            return "+" + digits
        }

        // No country code provided.
        if digits.count == 10 {
            return "+" + defaultCountryCode + digits
        }
        // 11 digits starting with the default code (e.g. 1XXXXXXXXXX).
        if digits.count == 11, digits.hasPrefix(defaultCountryCode) {
            return "+" + digits
        }
        // Fallback: assume already includes a country code.
        return "+" + digits
    }
}
