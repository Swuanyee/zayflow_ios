import Foundation

public enum Discount: Equatable, Codable, Sendable {
    case fixed(Money)
    case percentage(basisPoints: Int)

    public func amount(for subtotal: Money) throws -> Money {
        switch self {
        case .fixed(let money):
            return money.minorUnits > subtotal.minorUnits ? subtotal : money
        case .percentage(let basisPoints):
            let clamped = max(0, min(10_000, basisPoints))
            let raw = subtotal.minorUnits.multipliedReportingOverflow(by: Int64(clamped))
            guard !raw.overflow else { throw MoneyError.overflow }
            let amount = divideHalfAwayFromZero(raw.partialValue, by: 10_000)
            return try Money(minorUnits: amount, currency: subtotal.currency)
        }
    }

    private func divideHalfAwayFromZero(_ value: Int64, by divisor: Int64) -> Int64 {
        let quotient = value / divisor
        let remainder = Swift.abs(value % divisor)
        guard remainder * 2 >= divisor else { return quotient }
        return quotient + (value >= 0 ? 1 : -1)
    }
}

public struct CartLine: Equatable, Codable, Sendable {
    public let id: UUID
    public let product: Product
    public let quantity: Quantity
    public let unit: ProductUnit
    public let unitPrice: Money
    public let discount: Discount?

    public init(id: UUID = UUID(), product: Product, quantity: Quantity, unit: ProductUnit? = nil, unitPrice: Money? = nil, discount: Discount? = nil) throws {
        guard let selectedUnit = unit ?? product.units.first(where: \.isBaseUnit) ?? product.units.first else {
            throw CartError.productHasNoSellableUnit(product.id)
        }
        self.id = id
        self.product = product
        self.quantity = quantity
        self.unit = selectedUnit
        self.unitPrice = unitPrice ?? product.unitPrice
        self.discount = discount
    }

    public var baseQuantity: Quantity {
        let raw = quantity.microUnits.multipliedReportingOverflow(by: unit.conversionFactor.microUnits)
        guard !raw.overflow else { return Quantity(microUnits: Int64.max) }
        return Quantity(microUnits: raw.partialValue / Quantity.scale)
    }

    public func subtotal() throws -> Money {
        try unitPrice.multiplied(by: quantity)
    }

    public func discountAmount() throws -> Money {
        guard let discount else { return try Money(minorUnits: 0, currency: unitPrice.currency) }
        return try discount.amount(for: subtotal())
    }

    public func total() throws -> Money {
        try subtotal().subtracting(discountAmount())
    }
}

public enum CartError: Error, Equatable {
    case emptyCart
    case productHasNoSellableUnit(UUID)
    case currencyMismatch
}

public struct CartTotals: Equatable, Sendable {
    public let subtotal: Money
    public let discountTotal: Money
    public let grandTotal: Money
}

public struct Cart: Equatable, Sendable {
    public let lines: [CartLine]
    public let invoiceDiscount: Discount?

    public init(lines: [CartLine] = [], invoiceDiscount: Discount? = nil) {
        self.lines = lines
        self.invoiceDiscount = invoiceDiscount
    }

    public func adding(product: Product, quantity: Quantity = .units(1)) throws -> Cart {
        let line = try CartLine(product: product, quantity: quantity)
        return Cart(lines: lines + [line], invoiceDiscount: invoiceDiscount)
    }

    public func totals(currency: String = "MMK") throws -> CartTotals {
        let zero = try Money(minorUnits: 0, currency: currency)
        let subtotal = try lines.reduce(zero) { partial, line in
            try partial.adding(line.subtotal())
        }
        let lineDiscount = try lines.reduce(zero) { partial, line in
            try partial.adding(line.discountAmount())
        }
        let afterLineDiscount = try subtotal.subtracting(lineDiscount)
        let invoiceDiscountAmount = try invoiceDiscount?.amount(for: afterLineDiscount) ?? zero
        let discountTotal = try lineDiscount.adding(invoiceDiscountAmount)
        let grandTotal = try subtotal.subtracting(discountTotal)
        return CartTotals(subtotal: subtotal, discountTotal: discountTotal, grandTotal: grandTotal)
    }

    public func quantityInCart(for productId: UUID) throws -> Quantity {
        try lines
            .filter { $0.product.id == productId }
            .reduce(Quantity.units(0)) { partial, line in
                try partial.adding(line.baseQuantity)
            }
    }

    public func availableStock(productId: UUID, currentBalance: Quantity) throws -> Quantity {
        try currentBalance.subtracting(quantityInCart(for: productId))
    }
}
