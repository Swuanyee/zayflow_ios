import Foundation

public struct ProductSearch: Sendable {
    private let products: [Product]

    public init(products: [Product]) {
        self.products = products
    }

    public func search(_ query: String, limit: Int = 50) -> [Product] {
        let normalizedQuery = Self.normalized(query)
        guard !normalizedQuery.isEmpty else {
            return Array(products.prefix(limit))
        }

        let tokens = normalizedQuery.split(separator: " ").map(String.init)
        return products
            .compactMap { product -> (product: Product, score: Int)? in
                let searchable = searchableText(for: product)
                let barcodeMatch = product.barcodes.contains { Self.normalized($0.barcode) == normalizedQuery }
                let skuMatch = Self.normalized(product.sku) == normalizedQuery
                let allTokensMatch = tokens.allSatisfy { searchable.contains($0) }

                guard barcodeMatch || skuMatch || allTokensMatch else { return nil }

                var score = 0
                if barcodeMatch { score += 1_000 }
                if skuMatch { score += 900 }
                if Self.normalized(product.name).hasPrefix(normalizedQuery) { score += 500 }
                if searchable.contains(normalizedQuery) { score += 250 }
                score += max(0, 100 - product.name.count)

                return (product, score)
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.product.name < rhs.product.name }
                return lhs.score > rhs.score
            }
            .prefix(limit)
            .map(\.product)
    }

    public func product(forBarcode barcode: String) -> Product? {
        let normalizedBarcode = Self.normalized(barcode)
        return products.first { product in
            product.barcodes.contains { Self.normalized($0.barcode) == normalizedBarcode }
        }
    }

    private func searchableText(for product: Product) -> String {
        [
            product.name,
            product.localName,
            product.sku,
            product.category,
            product.barcodes.map(\.barcode).joined(separator: " ")
        ]
        .compactMap { $0 }
        .map(Self.normalized)
        .joined(separator: " ")
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
