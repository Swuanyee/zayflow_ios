import Foundation

public enum MoneyError: Error, Equatable {
    case invalidCurrency(String)
    case invalidAmount(String)
    case currencyMismatch(String, String)
    case overflow
}

public struct Money: Equatable, Hashable, Codable, Sendable {
    public static let scale: Int64 = 100

    public let minorUnits: Int64
    public let currency: String

    public init(minorUnits: Int64, currency: String) throws {
        guard currency.count == 3 else { throw MoneyError.invalidCurrency(currency) }
        self.minorUnits = minorUnits
        self.currency = currency.uppercased()
    }

    public static func mmk(_ majorUnits: Int64) -> Money {
        try! Money(minorUnits: majorUnits * scale, currency: "MMK")
    }

    public static func parse(_ value: String, currency: String = "MMK") throws -> Money {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MoneyError.invalidAmount(value) }

        let sign: Int64
        let unsigned: Substring
        if trimmed.first == "-" {
            sign = -1
            unsigned = trimmed.dropFirst()
        } else {
            sign = 1
            unsigned = Substring(trimmed)
        }

        let parts = unsigned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let major = Int64(parts[0]), major >= 0 else {
            throw MoneyError.invalidAmount(value)
        }

        let cents: Int64
        if parts.count == 2 {
            let fractional = parts[1]
            guard fractional.count <= 2, fractional.allSatisfy(\.isNumber) else {
                throw MoneyError.invalidAmount(value)
            }
            let padded = fractional.padding(toLength: 2, withPad: "0", startingAt: 0)
            cents = Int64(padded) ?? 0
        } else {
            cents = 0
        }

        let majorResult = major.multipliedReportingOverflow(by: scale)
        guard !majorResult.overflow else {
            throw MoneyError.overflow
        }
        let totalResult = majorResult.partialValue.addingReportingOverflow(cents)
        guard !totalResult.overflow else {
            throw MoneyError.overflow
        }

        return try Money(minorUnits: totalResult.partialValue * sign, currency: currency)
    }

    public var decimalString: String {
        let absMinor = Swift.abs(minorUnits)
        let major = absMinor / Self.scale
        let minor = absMinor % Self.scale
        let sign = minorUnits < 0 ? "-" : ""
        return "\(sign)\(major).\(String(format: "%02d", minor))"
    }

    public var displayString: String {
        let absMinor = Swift.abs(minorUnits)
        let major = absMinor / Self.scale
        let minor = absMinor % Self.scale
        let sign = minorUnits < 0 ? "-" : ""
        if currency == "MMK", minor == 0 {
            return "\(sign)\(major.formatted()) Ks"
        }
        return "\(sign)\(major.formatted()).\(String(format: "%02d", minor)) \(currency)"
    }

    public func adding(_ other: Money) throws -> Money {
        try ensureSameCurrency(other)
        let result = minorUnits.addingReportingOverflow(other.minorUnits)
        guard !result.overflow else { throw MoneyError.overflow }
        return try Money(minorUnits: result.partialValue, currency: currency)
    }

    public func subtracting(_ other: Money) throws -> Money {
        try ensureSameCurrency(other)
        let result = minorUnits.subtractingReportingOverflow(other.minorUnits)
        guard !result.overflow else { throw MoneyError.overflow }
        return try Money(minorUnits: result.partialValue, currency: currency)
    }

    public func multiplied(by quantity: Quantity) throws -> Money {
        let product = minorUnits.multipliedReportingOverflow(by: quantity.microUnits)
        guard !product.overflow else { throw MoneyError.overflow }
        let rounded = Self.divideHalfAwayFromZero(product.partialValue, by: Quantity.scale)
        return try Money(minorUnits: rounded, currency: currency)
    }

    private func ensureSameCurrency(_ other: Money) throws {
        guard currency == other.currency else {
            throw MoneyError.currencyMismatch(currency, other.currency)
        }
    }

    private static func divideHalfAwayFromZero(_ value: Int64, by divisor: Int64) -> Int64 {
        let quotient = value / divisor
        let remainder = Swift.abs(value % divisor)
        guard remainder * 2 >= divisor else { return quotient }
        return quotient + (value >= 0 ? 1 : -1)
    }
}
