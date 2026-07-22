import Foundation

public enum QuantityError: Error, Equatable {
    case invalidQuantity(String)
    case overflow
}

public struct Quantity: Equatable, Hashable, Codable, Sendable, Comparable {
    public static let scale: Int64 = 1_000_000

    public let microUnits: Int64

    public init(microUnits: Int64) {
        self.microUnits = microUnits
    }

    public static func units(_ value: Int64) -> Quantity {
        Quantity(microUnits: value * scale)
    }

    public static func parse(_ value: String) throws -> Quantity {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw QuantityError.invalidQuantity(value) }

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
        guard parts.count <= 2, let whole = Int64(parts[0]) else {
            throw QuantityError.invalidQuantity(value)
        }

        let fractionalUnits: Int64
        if parts.count == 2 {
            let fractional = parts[1]
            guard fractional.count <= 6, fractional.allSatisfy(\.isNumber) else {
                throw QuantityError.invalidQuantity(value)
            }
            let padded = fractional.padding(toLength: 6, withPad: "0", startingAt: 0)
            fractionalUnits = Int64(padded) ?? 0
        } else {
            fractionalUnits = 0
        }

        let scaledWhole = whole.multipliedReportingOverflow(by: scale)
        guard !scaledWhole.overflow else { throw QuantityError.overflow }
        let total = scaledWhole.partialValue.addingReportingOverflow(fractionalUnits)
        guard !total.overflow else { throw QuantityError.overflow }
        return Quantity(microUnits: total.partialValue * sign)
    }

    public var decimalString: String {
        let absUnits = Swift.abs(microUnits)
        let whole = absUnits / Self.scale
        let fractional = absUnits % Self.scale
        let sign = microUnits < 0 ? "-" : ""
        if fractional == 0 { return "\(sign)\(whole)" }
        let padded = String(format: "%06d", fractional)
        return "\(sign)\(whole).\(padded.trimmingCharacters(in: CharacterSet(charactersIn: "0")))"
    }

    public func adding(_ other: Quantity) throws -> Quantity {
        let result = microUnits.addingReportingOverflow(other.microUnits)
        guard !result.overflow else { throw QuantityError.overflow }
        return Quantity(microUnits: result.partialValue)
    }

    public func subtracting(_ other: Quantity) throws -> Quantity {
        let result = microUnits.subtractingReportingOverflow(other.microUnits)
        guard !result.overflow else { throw QuantityError.overflow }
        return Quantity(microUnits: result.partialValue)
    }

    public static func < (lhs: Quantity, rhs: Quantity) -> Bool {
        lhs.microUnits < rhs.microUnits
    }
}
