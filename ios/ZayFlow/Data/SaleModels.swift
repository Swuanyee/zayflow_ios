import Foundation
import ZayFlowCore

enum PaymentMethod: String, CaseIterable, Codable, Sendable, Identifiable {
    case cash
    case qr

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash: "Cash"
        case .qr: "QR payment"
        }
    }

    var symbol: String {
        switch self {
        case .cash: "banknote.fill"
        case .qr: "qrcode"
        }
    }
}

struct CheckoutLine: Equatable, Sendable {
    let productId: UUID
    let quantity: Quantity
}

struct CheckoutRequest: Equatable, Sendable {
    let lines: [CheckoutLine]
    let paymentMethod: PaymentMethod
    let amountTendered: Money
}

struct CheckoutContext: Equatable, Sendable {
    let organizationId: UUID
    let shopId: UUID
    let userId: UUID
    let deviceId: UUID
}

struct CompletedSaleLine: Equatable, Codable, Sendable, Identifiable {
    let id: UUID
    let productName: String
    let quantity: Quantity
    let unitPrice: Money
    let lineTotal: Money
}

struct CompletedSale: Equatable, Sendable, Identifiable {
    let id: UUID
    let receiptNumber: String
    let occurredAt: Date
    let subtotal: Money
    let grandTotal: Money
    let amountTendered: Money
    let change: Money
    let paymentMethod: PaymentMethod
    let lines: [CompletedSaleLine]
}

struct SaleSummary: Equatable, Sendable, Identifiable {
    let id: UUID
    let receiptNumber: String
    let occurredAt: Date
    let grandTotal: Money
    let paymentMethod: PaymentMethod
    let itemCount: Int
    let status: String
    let shopCode: String?
}

enum CheckoutError: Error, Equatable, LocalizedError {
    case emptyCart
    case invalidQuantity
    case productUnavailable
    case insufficientStock(productName: String, available: Quantity)
    case registerShiftClosed
    case insufficientPayment(required: Money)
    case currencyMismatch

    var errorDescription: String? {
        switch self {
        case .emptyCart:
            "Add at least one product before charging."
        case .invalidQuantity:
            "Every sale quantity must be greater than zero."
        case .productUnavailable:
            "A product in this cart is no longer available."
        case .insufficientStock(let name, let available):
            "Only \(available.decimalString) of \(name) is available."
        case .registerShiftClosed:
            "Open a register shift before completing a sale."
        case .insufficientPayment(let required):
            "Enter at least \(required.displayString)."
        case .currencyMismatch:
            "The payment currency does not match this sale."
        }
    }
}
