import Foundation

public enum ProductType: String, Codable, Sendable {
    case standard
    case service
    case openPrice = "open_price"
    case weighted
}

public struct ProductUnit: Equatable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let abbreviation: String
    public let conversionFactor: Quantity
    public let isBaseUnit: Bool
    public let isSellable: Bool

    public init(id: UUID, name: String, abbreviation: String, conversionFactor: Quantity, isBaseUnit: Bool, isSellable: Bool) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.conversionFactor = conversionFactor
        self.isBaseUnit = isBaseUnit
        self.isSellable = isSellable
    }
}

public struct ProductBarcode: Equatable, Codable, Sendable {
    public let barcode: String
    public let unitId: UUID
    public let quantityMultiplier: Quantity
    public let isPrimary: Bool
}

public struct Product: Equatable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let localName: String?
    public let sku: String
    public let category: String
    public let type: ProductType
    public let trackStock: Bool
    public let allowNegativeStock: Bool
    public let lowStockThreshold: Quantity?
    public let unitPrice: Money
    public let unitCost: Money?
    public let units: [ProductUnit]
    public let barcodes: [ProductBarcode]
    public let cityMallSource: CityMallSource?
}

public struct CityMallSource: Equatable, Codable, Sendable {
    public let productId: String
    public let observedPrice: String?
    public let observedAt: String
}
