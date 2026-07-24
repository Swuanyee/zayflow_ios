import CryptoKit
import Foundation
import GRDB
import ZayFlowCore

extension AppDatabase {
    func completeSale(_ request: CheckoutRequest, context: CheckoutContext? = nil, now: Date = Date()) throws -> CompletedSale {
        guard !request.lines.isEmpty else { throw CheckoutError.emptyCart }
        guard request.lines.allSatisfy({ $0.quantity.microUnits > 0 }) else {
            throw CheckoutError.invalidQuantity
        }

        return try writer.write { db in
            guard let shiftId = try String.fetchOne(
                db,
                sql: "SELECT id FROM register_shifts WHERE status = 'open' ORDER BY opened_at DESC LIMIT 1"
            ) else {
                throw CheckoutError.registerShiftClosed
            }

            var preparedLines: [PreparedSaleLine] = []
            var subtotal = Money.mmk(0)
            var costTotal = Money.mmk(0)

            for requestedLine in request.lines {
                let row: Row?
                if let context {
                    row = try Row.fetchOne(db, sql: """
                        SELECT p.id, p.name, p.local_name, p.sku, p.category, p.product_type,
                               p.track_stock, p.allow_negative_stock, p.unit_cost_minor, p.currency,
                               COALESCE(sp.price_override_minor, p.unit_price_minor) AS unit_price_minor,
                               sp.low_stock_micro_units AS low_stock_micro_units,
                               b.barcode,
                               COALESCE(ib.quantity_micro_units, 0) AS stock_micro_units
                        FROM org_shop_products sp
                        JOIN products p ON p.id = sp.product_id
                        LEFT JOIN product_barcodes b ON b.product_id = p.id AND b.is_primary = 1
                        LEFT JOIN org_inventory_balances ib ON ib.shop_id = sp.shop_id AND ib.product_id = sp.product_id
                        WHERE sp.shop_id = ? AND p.id = ? AND sp.enabled = 1 AND p.active = 1
                          AND (
                              NOT EXISTS (SELECT 1 FROM org_device_category_permissions dcp WHERE dcp.device_id = ?)
                              OR EXISTS (SELECT 1 FROM org_device_category_permissions dcp WHERE dcp.device_id = ? AND dcp.category = p.category)
                          )
                        LIMIT 1
                        """, arguments: [context.shopId.uuidString, requestedLine.productId.uuidString, context.deviceId.uuidString, context.deviceId.uuidString])
                } else {
                    row = try Row.fetchOne(db, sql: """
                        SELECT p.*, b.barcode, COALESCE(sb.quantity_micro_units, 0) AS stock_micro_units
                        FROM products p
                        LEFT JOIN product_barcodes b ON b.product_id = p.id AND b.is_primary = 1
                        LEFT JOIN stock_balances sb ON sb.product_id = p.id
                        WHERE p.id = ? AND p.active = 1
                        LIMIT 1
                        """, arguments: [requestedLine.productId.uuidString])
                }

                guard let row else {
                    throw CheckoutError.productUnavailable
                }

                let currency: String = row["currency"]
                let unitPrice = try Money(minorUnits: row["unit_price_minor"], currency: currency)
                let unitCost = try Money(minorUnits: row["unit_cost_minor"], currency: currency)
                let lineTotal = try unitPrice.multiplied(by: requestedLine.quantity)
                let lineCost = try unitCost.multiplied(by: requestedLine.quantity)
                let currentStock = Quantity(microUnits: row["stock_micro_units"])
                let tracksStock: Bool = row["track_stock"]
                let allowsNegative: Bool = row["allow_negative_stock"]
                let name: String = row["name"]

                if tracksStock, !allowsNegative, requestedLine.quantity > currentStock {
                    throw CheckoutError.insufficientStock(productName: name, available: currentStock)
                }

                subtotal = try subtotal.adding(lineTotal)
                costTotal = try costTotal.adding(lineCost)
                preparedLines.append(PreparedSaleLine(
                    id: UUID(),
                    productId: requestedLine.productId,
                    productName: name,
                    sku: row["sku"],
                    barcode: row["barcode"],
                    quantity: requestedLine.quantity,
                    unitPrice: unitPrice,
                    unitCost: unitCost,
                    lineTotal: lineTotal,
                    currentStock: currentStock,
                    tracksStock: tracksStock
                ))
            }

            guard request.amountTendered.currency == subtotal.currency else {
                throw CheckoutError.currencyMismatch
            }
            guard request.amountTendered.minorUnits >= subtotal.minorUnits else {
                throw CheckoutError.insufficientPayment(required: subtotal)
            }

            guard let state = try Row.fetchOne(db, sql: "SELECT * FROM device_state WHERE id = 1") else {
                throw DatabaseError(message: "Missing device state")
            }
            let deviceSequence: Int64 = state["device_sequence"]
            let receiptSequence: Int64 = state["receipt_sequence"]
            let nextDeviceSequence = deviceSequence + 1
            let nextReceiptSequence = receiptSequence + 1
            let receiptNumber = Self.receiptNumber(sequence: nextReceiptSequence, date: now)
            let saleId = UUID()
            let paymentId = UUID()
            let change = try request.amountTendered.subtracting(subtotal)

            try db.execute(sql: """
                INSERT INTO sales (
                    id, receipt_number, device_sequence, shift_id, status, currency,
                    subtotal_minor, discount_total_minor, tax_total_minor, rounding_total_minor,
                    grand_total_minor, cost_total_minor, business_date, occurred_at,
                    organization_id, shop_id, user_id, device_id
                ) VALUES (?, ?, ?, ?, 'completed', ?, ?, 0, 0, 0, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    saleId.uuidString,
                    receiptNumber,
                    nextDeviceSequence,
                    shiftId,
                    subtotal.currency,
                    subtotal.minorUnits,
                    subtotal.minorUnits,
                    costTotal.minorUnits,
                    Self.businessDate(now),
                    now,
                    context?.organizationId.uuidString,
                    context?.shopId.uuidString,
                    context?.userId.uuidString,
                    context?.deviceId.uuidString
                ])

            for line in preparedLines {
                try db.execute(sql: """
                    INSERT INTO sale_lines (
                        id, sale_id, product_id, barcode_snapshot, product_name_snapshot,
                        sku_snapshot, quantity_micro_units, unit_price_minor, unit_cost_minor,
                        discount_minor, tax_minor, line_total_minor
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, ?)
                    """, arguments: [
                        line.id.uuidString,
                        saleId.uuidString,
                        line.productId.uuidString,
                        line.barcode,
                        line.productName,
                        line.sku,
                        line.quantity.microUnits,
                        line.unitPrice.minorUnits,
                        line.unitCost.minorUnits,
                        line.lineTotal.minorUnits
                    ])

                if line.tracksStock {
                    let ledgerId = UUID()
                    let resultingStock = try line.currentStock.subtracting(line.quantity)
                    if let context {
                        try db.execute(sql: """
                            INSERT INTO org_inventory_movements (id, shop_id, product_id, movement_type, quantity_delta_micro_units, reason, occurred_at)
                            VALUES (?, ?, ?, 'sale', ?, ?, ?)
                            """, arguments: [
                                ledgerId.uuidString,
                                context.shopId.uuidString,
                                line.productId.uuidString,
                                -line.quantity.microUnits,
                                "Sale \(receiptNumber)",
                                now
                            ])
                        try db.execute(sql: """
                            INSERT INTO org_inventory_balances (shop_id, product_id, quantity_micro_units, updated_at)
                            VALUES (?, ?, ?, ?)
                            ON CONFLICT(shop_id, product_id) DO UPDATE SET
                                quantity_micro_units = excluded.quantity_micro_units,
                                updated_at = excluded.updated_at
                            """, arguments: [
                                context.shopId.uuidString,
                                line.productId.uuidString,
                                resultingStock.microUnits,
                                now
                            ])
                    } else {
                        try db.execute(sql: """
                            INSERT INTO stock_ledger_entries (
                                id, product_id, movement_type, quantity_delta_micro_units,
                                occurred_at, reference_type, reference_id
                            ) VALUES (?, ?, 'sale', ?, ?, 'sale', ?)
                            """, arguments: [
                                ledgerId.uuidString,
                                line.productId.uuidString,
                                -line.quantity.microUnits,
                                now,
                                saleId.uuidString
                            ])
                        try db.execute(sql: """
                            UPDATE stock_balances
                            SET quantity_micro_units = ?, last_ledger_entry_id = ?, updated_at = ?
                            WHERE product_id = ?
                            """, arguments: [
                                resultingStock.microUnits,
                                ledgerId.uuidString,
                                now,
                                line.productId.uuidString
                            ])
                    }
                }
            }

            try db.execute(sql: """
                INSERT INTO sale_payments (
                    id, sale_id, payment_method, amount_minor, amount_tendered_minor,
                    change_minor, currency, status, paid_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 'completed', ?)
                """, arguments: [
                    paymentId.uuidString,
                    saleId.uuidString,
                    request.paymentMethod.rawValue,
                    subtotal.minorUnits,
                    request.amountTendered.minorUnits,
                    change.minorUnits,
                    subtotal.currency,
                    now
                ])

            let payload = SaleSyncPayload(
                eventId: UUID(),
                type: "sale.completed",
                deviceId: context?.deviceId ?? Self.dashboardDeviceId,
                organizationId: context?.organizationId ?? Self.dashboardOrganizationId,
                locationId: context?.shopId ?? Self.dashboardLocationId,
                sequence: nextDeviceSequence,
                occurredAt: now,
                payload: SaleSyncPayload.Payload(
                    saleId: saleId,
                    receiptNumber: receiptNumber,
                    occurredAt: now,
                    paymentMethod: request.paymentMethod.rawValue,
                    grossTotal: .init(currency: subtotal.currency, minorUnits: subtotal.minorUnits),
                    discountTotal: .init(currency: subtotal.currency, minorUnits: 0),
                    amountTendered: .init(currency: request.amountTendered.currency, minorUnits: request.amountTendered.minorUnits),
                    change: .init(currency: change.currency, minorUnits: change.minorUnits),
                    lines: preparedLines.map {
                        SaleSyncPayload.Line(
                            lineId: $0.id,
                            masterItemId: $0.productId,
                            organizationItemId: $0.productId,
                            productName: $0.productName,
                            sku: $0.sku,
                            quantity: .init(microUnits: $0.quantity.microUnits),
                            unitPrice: .init(currency: $0.unitPrice.currency, minorUnits: $0.unitPrice.minorUnits),
                            unitCost: .init(currency: $0.unitCost.currency, minorUnits: $0.unitCost.minorUnits),
                            lineTotal: .init(currency: $0.lineTotal.currency, minorUnits: $0.lineTotal.minorUnits)
                        )
                    }
                )
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let payloadData = try encoder.encode(payload)
            let payloadJSON = String(decoding: payloadData, as: UTF8.self)
            let payloadHash = SHA256.hash(data: payloadData).map { String(format: "%02x", $0) }.joined()

            try db.execute(sql: """
                INSERT INTO audit_events (id, action, entity_type, entity_id, after_json, created_at)
                VALUES (?, 'sale.create', 'sale', ?, ?, ?)
                """, arguments: [UUID().uuidString, saleId.uuidString, payloadJSON, now])
            try db.execute(sql: """
                INSERT INTO sync_outbox (
                    event_id, device_sequence, entity_type, entity_id, operation,
                    schema_version, payload_json, payload_hash, occurred_at, status,
                    attempt_count, created_at
                ) VALUES (?, ?, 'sale', ?, 'create', 1, ?, ?, ?, 'pending', 0, ?)
                """, arguments: [
                    payload.eventId.uuidString,
                    nextDeviceSequence,
                    saleId.uuidString,
                    payloadJSON,
                    payloadHash,
                    now,
                    now
                ])
            try db.execute(sql: """
                UPDATE device_state
                SET device_sequence = ?, receipt_sequence = ?
                WHERE id = 1
                """, arguments: [nextDeviceSequence, nextReceiptSequence])

            return CompletedSale(
                id: saleId,
                receiptNumber: receiptNumber,
                occurredAt: now,
                subtotal: subtotal,
                grandTotal: subtotal,
                amountTendered: request.amountTendered,
                change: change,
                paymentMethod: request.paymentMethod,
                lines: preparedLines.map {
                    CompletedSaleLine(
                        id: $0.id,
                        productName: $0.productName,
                        quantity: $0.quantity,
                        unitPrice: $0.unitPrice,
                        lineTotal: $0.lineTotal
                    )
                }
            )
        }
    }

    func fetchSales(shopID: UUID? = nil) throws -> [SaleSummary] {
        try writer.read { db in
            let shopFilter = shopID == nil ? "" : "WHERE s.shop_id = ?"
            let arguments: StatementArguments = shopID == nil ? [] : [shopID!.uuidString]
            let rows = try Row.fetchAll(db, sql: """
                SELECT s.id, s.receipt_number, s.occurred_at, s.grand_total_minor,
                       s.currency, s.status, p.payment_method, os.code AS shop_code,
                       COALESCE(SUM(sl.quantity_micro_units), 0) AS item_micro_units
                FROM sales s
                JOIN sale_payments p ON p.sale_id = s.id
                LEFT JOIN sale_lines sl ON sl.sale_id = s.id
                LEFT JOIN org_shops os ON os.id = s.shop_id
                \(shopFilter)
                GROUP BY s.id, p.id
                ORDER BY s.occurred_at DESC
                """, arguments: arguments)
            return try rows.map { row in
                guard let id = UUID(uuidString: row["id"]) else {
                    throw DatabaseError(message: "Invalid sale identifier")
                }
                let methodRaw: String = row["payment_method"]
                return SaleSummary(
                    id: id,
                    receiptNumber: row["receipt_number"],
                    occurredAt: row["occurred_at"],
                    grandTotal: try Money(minorUnits: row["grand_total_minor"], currency: row["currency"]),
                    paymentMethod: PaymentMethod(rawValue: methodRaw) ?? .cash,
                    itemCount: Int((row["item_micro_units"] as Int64) / Quantity.scale),
                    status: row["status"],
                    shopCode: row["shop_code"]
                )
            }
        }
    }

    func saleCount() throws -> Int {
        try writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sales") ?? 0 }
    }

    func paymentCount() throws -> Int {
        try writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sale_payments") ?? 0 }
    }

    func outboxCount() throws -> Int {
        try writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox") ?? 0 }
    }

    func pendingOutboxCount() throws -> Int {
        try writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE status = 'pending'") ?? 0 }
    }

    func auditEventCount() throws -> Int {
        try writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM audit_events") ?? 0 }
    }

    private static func receiptNumber(sequence: Int64, date: Date) -> String {
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        return "ZF-DEMO-IPHN01-\(year)-\(String(format: "%08lld", sequence))"
    }

    private static let dashboardOrganizationId = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
    private static let dashboardLocationId = UUID(uuidString: "21000000-0000-4000-8000-000000000001")!
    private static let dashboardDeviceId = UUID(uuidString: "60000000-0000-4000-8000-000000000001")!

    private static func businessDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Yangon")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct PreparedSaleLine {
    let id: UUID
    let productId: UUID
    let productName: String
    let sku: String
    let barcode: String?
    let quantity: Quantity
    let unitPrice: Money
    let unitCost: Money
    let lineTotal: Money
    let currentStock: Quantity
    let tracksStock: Bool
}

private struct SaleSyncPayload: Codable {
    struct MoneyAmount: Codable {
        let currency: String
        let minorUnits: Int64
    }

    struct QuantityAmount: Codable {
        let microUnits: Int64
    }

    struct Line: Codable {
        let lineId: UUID
        let masterItemId: UUID
        let organizationItemId: UUID
        let productName: String
        let sku: String
        let quantity: QuantityAmount
        let unitPrice: MoneyAmount
        let unitCost: MoneyAmount
        let lineTotal: MoneyAmount
    }

    struct Payload: Codable {
        let saleId: UUID
        let receiptNumber: String
        let occurredAt: Date
        let paymentMethod: String
        let grossTotal: MoneyAmount
        let discountTotal: MoneyAmount
        let amountTendered: MoneyAmount
        let change: MoneyAmount
        let lines: [Line]
    }

    let eventId: UUID
    let type: String
    let deviceId: UUID
    let organizationId: UUID
    let locationId: UUID
    let sequence: Int64
    let occurredAt: Date
    let payload: Payload
}

struct PendingSyncEvent: Equatable, Sendable {
    let eventId: UUID
    let deviceSequence: Int64
    let payloadJSON: String
}

extension AppDatabase {
    func fetchPendingSyncEvents(limit: Int = 50, now: Date = Date()) throws -> [PendingSyncEvent] {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT event_id, device_sequence, payload_json
                FROM sync_outbox
                WHERE status = 'pending'
                  AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
                ORDER BY device_sequence
                LIMIT ?
                """, arguments: [now, limit])
            return try rows.map { row in
                guard let eventId = UUID(uuidString: row["event_id"]) else {
                    throw DatabaseError(message: "Invalid sync event identifier")
                }
                return PendingSyncEvent(
                    eventId: eventId,
                    deviceSequence: row["device_sequence"],
                    payloadJSON: row["payload_json"]
                )
            }
        }
    }

    func markSyncEventsAcknowledged(_ eventIds: [UUID], now: Date = Date()) throws {
        guard !eventIds.isEmpty else { return }
        try writer.write { db in
            for eventId in eventIds {
                try db.execute(sql: """
                    UPDATE sync_outbox
                    SET status = 'acknowledged', acknowledged_at = ?, last_error_code = NULL
                    WHERE event_id = ?
                    """, arguments: [now, eventId.uuidString])
            }
        }
    }

    func markSyncEventsFailed(_ eventIds: [UUID], errorCode: String, now: Date = Date()) throws {
        guard !eventIds.isEmpty else { return }
        let retryAt = now.addingTimeInterval(60)
        try writer.write { db in
            for eventId in eventIds {
                try db.execute(sql: """
                    UPDATE sync_outbox
                    SET attempt_count = attempt_count + 1,
                        last_error_code = ?,
                        next_attempt_at = ?
                    WHERE event_id = ? AND status = 'pending'
                    """, arguments: [errorCode, retryAt, eventId.uuidString])
            }
        }
    }
}
