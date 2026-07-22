import Foundation

public enum DemoCatalogError: Error, Equatable {
    case resourceMissing
}

public struct DemoCatalog: Sendable {
    public let products: [Product]

    public init(products: [Product]) {
        self.products = products
    }

    public static func loadFromBundle() throws -> DemoCatalog {
        guard let url = Bundle.module.url(forResource: "DemoCatalog", withExtension: "json") else {
            throw DemoCatalogError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        let entries = try JSONDecoder.zayflow.decode([DemoCatalogEntry].self, from: data)
        return try DemoCatalog(products: entries.map { try $0.product })
    }
}

private struct DemoCatalogEntry: Decodable {
    let id: UUID
    let name: String
    let localName: String?
    let sku: String
    let category: String
    let type: ProductType
    let trackStock: Bool
    let allowNegativeStock: Bool
    let lowStockThreshold: String?
    let unitPrice: String
    let unitCost: String?
    let barcodes: [String]
    let source: CityMallSource?

    var product: Product {
        get throws {
            let baseUnitId = deterministicUnitId(productId: id, label: "piece")
            let unit = ProductUnit(
                id: baseUnitId,
                name: "Piece",
                abbreviation: "pc",
                conversionFactor: Quantity.units(1),
                isBaseUnit: true,
                isSellable: true
            )
            let productBarcodes = barcodes.enumerated().map { index, barcode in
                ProductBarcode(
                    barcode: barcode,
                    unitId: baseUnitId,
                    quantityMultiplier: Quantity.units(1),
                    isPrimary: index == 0
                )
            }
            return Product(
                id: id,
                name: name,
                localName: localName,
                sku: sku,
                category: category,
                type: type,
                trackStock: trackStock,
                allowNegativeStock: allowNegativeStock,
                lowStockThreshold: try lowStockThreshold.map(Quantity.parse),
                unitPrice: try Money.parse(unitPrice),
                unitCost: try unitCost.map { try Money.parse($0) },
                units: [unit],
                barcodes: productBarcodes,
                cityMallSource: source
            )
        }
    }

    private func deterministicUnitId(productId: UUID, label: String) -> UUID {
        var bytes = Array(productId.uuidString.utf8)
        bytes.append(contentsOf: label.utf8)
        while bytes.count < 16 { bytes.append(0) }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private extension JSONDecoder {
    static var zayflow: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
