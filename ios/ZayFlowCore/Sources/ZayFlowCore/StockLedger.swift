import Foundation

public enum StockMovementType: String, Codable, Sendable {
    case openingStock = "opening_stock"
    case stockReceived = "stock_received"
    case sale
    case saleReturn = "sale_return"
    case stockAdjustment = "stock_adjustment"
    case damaged
    case voidReversal = "void_reversal"
}

public struct StockLedgerEntry: Equatable, Codable, Sendable {
    public let id: UUID
    public let productId: UUID
    public let movementType: StockMovementType
    public let quantityDelta: Quantity
    public let occurredAt: Date
    public let referenceId: UUID?

    public init(id: UUID, productId: UUID, movementType: StockMovementType, quantityDelta: Quantity, occurredAt: Date, referenceId: UUID? = nil) {
        self.id = id
        self.productId = productId
        self.movementType = movementType
        self.quantityDelta = quantityDelta
        self.occurredAt = occurredAt
        self.referenceId = referenceId
    }
}

public struct StockBalanceProjector: Sendable {
    public init() {}

    public func balance(for productId: UUID, entries: [StockLedgerEntry]) throws -> Quantity {
        try entries
            .filter { $0.productId == productId }
            .sorted { $0.occurredAt < $1.occurredAt }
            .reduce(Quantity.units(0)) { partial, entry in
                try partial.adding(entry.quantityDelta)
            }
    }
}
