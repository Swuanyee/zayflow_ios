import Foundation
import GRDB
import ZayFlowCore

final class AppDatabase: @unchecked Sendable {
    enum SecurityError: Error {
        case sqlCipherUnavailable
    }

    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
        try seedDemoStoreIfNeeded()
    }

    static func live() throws -> AppDatabase {
        let fileManager = FileManager.default
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("ZayFlow", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )

        let queue = try encryptedQueue(
            path: directory.appendingPathComponent("zayflow-v2.sqlite").path,
            passphrase: DatabaseKeyStore().loadOrCreate()
        )
        return try AppDatabase(writer: queue)
    }

    static func inMemory() throws -> AppDatabase {
        try AppDatabase(writer: encryptedQueue(path: nil, passphrase: testPassphrase))
    }

    static func atPath(_ path: String, passphrase: Data = testPassphrase) throws -> AppDatabase {
        try AppDatabase(writer: encryptedQueue(path: path, passphrase: passphrase))
    }

    private static let testPassphrase = Data("zayflow-test-database-key-32bytes".utf8)

    private static func encryptedQueue(path: String?, passphrase: Data) throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.label = "ZayFlow encrypted operational database"
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in
            try db.usePassphrase(passphrase)
            guard let cipherVersion = try String.fetchOne(db, sql: "PRAGMA cipher_version"),
                  !cipherVersion.isEmpty else {
                throw SecurityError.sqlCipherUnavailable
            }
            try db.execute(sql: "PRAGMA cipher_memory_security = ON")
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        if let path {
            return try DatabaseQueue(path: path, configuration: configuration)
        }
        return try DatabaseQueue(configuration: configuration)
    }

    func fetchProducts() throws -> [StoreProduct] {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT p.*, b.barcode, COALESCE(sb.quantity_micro_units, 0) AS stock_micro_units
                FROM products p
                LEFT JOIN product_barcodes b ON b.product_id = p.id AND b.is_primary = 1
                LEFT JOIN stock_balances sb ON sb.product_id = p.id
                WHERE p.active = 1
                ORDER BY p.name COLLATE NOCASE
                """)
            return try rows.map(StoreProduct.init(row:))
        }
    }

    func product(barcode: String) throws -> StoreProduct? {
        try writer.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT p.*, b.barcode, COALESCE(sb.quantity_micro_units, 0) AS stock_micro_units
                FROM products p
                JOIN product_barcodes b ON b.product_id = p.id
                LEFT JOIN stock_balances sb ON sb.product_id = p.id
                WHERE b.normalized_barcode = ? AND p.active = 1
                LIMIT 1
                """, arguments: [barcode.uppercased()]) else { return nil }
            return try StoreProduct(row: row)
        }
    }

    func productCount() throws -> Int {
        try writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM products") ?? 0
        }
    }

    func ledgerEntryCount() throws -> Int {
        try writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM stock_ledger_entries") ?? 0
        }
    }

    private func seedDemoStoreIfNeeded() throws {
        let catalog = try DemoCatalog.loadFromBundle()
        try writer.write { db in
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM products") == 0 else { return }

            for (index, product) in catalog.products.enumerated() {
                try db.execute(sql: """
                    INSERT INTO products (
                        id, name, local_name, sku, category, product_type, track_stock,
                        allow_negative_stock, low_stock_micro_units, unit_price_minor,
                        unit_cost_minor, currency, active
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
                    """, arguments: [
                        product.id.uuidString,
                        product.name,
                        product.localName,
                        product.sku,
                        product.category,
                        product.type.rawValue,
                        product.trackStock,
                        product.allowNegativeStock,
                        product.lowStockThreshold?.microUnits,
                        product.unitPrice.minorUnits,
                        product.unitCost?.minorUnits ?? 0,
                        product.unitPrice.currency
                    ])

                for barcode in product.barcodes {
                    try db.execute(sql: """
                        INSERT INTO product_barcodes (
                            id, product_id, barcode, normalized_barcode, is_primary
                        ) VALUES (?, ?, ?, ?, ?)
                        """, arguments: [
                            UUID().uuidString,
                            product.id.uuidString,
                            barcode.barcode,
                            barcode.barcode.uppercased(),
                            barcode.isPrimary
                        ])
                }

                let openingQuantity = Quantity.units(Int64(8 + ((index * 7) % 48)))
                let ledgerId = UUID().uuidString
                try db.execute(sql: """
                    INSERT INTO stock_ledger_entries (
                        id, product_id, movement_type, quantity_delta_micro_units,
                        occurred_at, reference_type
                    ) VALUES (?, ?, 'opening_stock', ?, ?, 'demo_import')
                    """, arguments: [
                        ledgerId,
                        product.id.uuidString,
                        openingQuantity.microUnits,
                        Date()
                    ])
                try db.execute(sql: """
                    INSERT INTO stock_balances (product_id, quantity_micro_units, last_ledger_entry_id, updated_at)
                    VALUES (?, ?, ?, ?)
                    """, arguments: [
                        product.id.uuidString,
                        openingQuantity.microUnits,
                        ledgerId,
                        Date()
                    ])
            }

            try db.execute(
                sql: "INSERT INTO app_metadata (key, value) VALUES ('demo_catalog_version', '1')"
            )
        }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_operational_catalog") { db in
            try db.create(table: "app_metadata") { table in
                table.column("key", .text).primaryKey()
                table.column("value", .text).notNull()
            }
            try db.create(table: "products") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("local_name", .text)
                table.column("sku", .text).notNull().unique()
                table.column("category", .text).notNull()
                table.column("product_type", .text).notNull()
                table.column("track_stock", .boolean).notNull()
                table.column("allow_negative_stock", .boolean).notNull()
                table.column("low_stock_micro_units", .integer)
                table.column("unit_price_minor", .integer).notNull()
                table.column("unit_cost_minor", .integer).notNull()
                table.column("currency", .text).notNull()
                table.column("active", .boolean).notNull().defaults(to: true)
            }
            try db.create(index: "products_name", on: "products", columns: ["name"])
            try db.create(index: "products_category", on: "products", columns: ["category"])
            try db.create(table: "product_barcodes") { table in
                table.column("id", .text).primaryKey()
                table.column("product_id", .text).notNull()
                    .references("products", onDelete: .cascade)
                table.column("barcode", .text).notNull()
                table.column("normalized_barcode", .text).notNull().unique()
                table.column("is_primary", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "product_barcodes_product", on: "product_barcodes", columns: ["product_id"])
            try db.create(table: "stock_ledger_entries") { table in
                table.column("id", .text).primaryKey()
                table.column("product_id", .text).notNull()
                    .references("products", onDelete: .restrict)
                table.column("movement_type", .text).notNull()
                table.column("quantity_delta_micro_units", .integer).notNull()
                table.column("occurred_at", .datetime).notNull()
                table.column("reference_type", .text).notNull()
                table.column("reference_id", .text)
            }
            try db.create(index: "stock_ledger_product_occurred", on: "stock_ledger_entries", columns: ["product_id", "occurred_at"])
            try db.create(table: "stock_balances") { table in
                table.column("product_id", .text).primaryKey()
                    .references("products", onDelete: .cascade)
                table.column("quantity_micro_units", .integer).notNull()
                table.column("last_ledger_entry_id", .text).notNull()
                    .references("stock_ledger_entries", onDelete: .restrict)
                table.column("updated_at", .datetime).notNull()
            }
        }
        migrator.registerMigration("v2_atomic_sales") { db in
            try db.create(table: "registers") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("code", .text).notNull().unique()
            }
            try db.create(table: "register_shifts") { table in
                table.column("id", .text).primaryKey()
                table.column("register_id", .text).notNull().references("registers", onDelete: .restrict)
                table.column("status", .text).notNull()
                table.column("opening_cash_minor", .integer).notNull()
                table.column("currency", .text).notNull()
                table.column("opened_at", .datetime).notNull()
                table.column("closed_at", .datetime)
            }
            try db.create(table: "device_state") { table in
                table.column("id", .integer).primaryKey()
                table.column("device_sequence", .integer).notNull()
                table.column("receipt_sequence", .integer).notNull()
            }
            try db.create(table: "sales") { table in
                table.column("id", .text).primaryKey()
                table.column("receipt_number", .text).notNull().unique()
                table.column("device_sequence", .integer).notNull().unique()
                table.column("shift_id", .text).notNull().references("register_shifts", onDelete: .restrict)
                table.column("status", .text).notNull()
                table.column("currency", .text).notNull()
                table.column("subtotal_minor", .integer).notNull()
                table.column("discount_total_minor", .integer).notNull()
                table.column("tax_total_minor", .integer).notNull()
                table.column("rounding_total_minor", .integer).notNull()
                table.column("grand_total_minor", .integer).notNull()
                table.column("cost_total_minor", .integer).notNull()
                table.column("business_date", .text).notNull()
                table.column("occurred_at", .datetime).notNull()
            }
            try db.create(index: "sales_occurred_at", on: "sales", columns: ["occurred_at"])
            try db.create(table: "sale_lines") { table in
                table.column("id", .text).primaryKey()
                table.column("sale_id", .text).notNull().references("sales", onDelete: .restrict)
                table.column("product_id", .text).notNull().references("products", onDelete: .restrict)
                table.column("barcode_snapshot", .text)
                table.column("product_name_snapshot", .text).notNull()
                table.column("sku_snapshot", .text).notNull()
                table.column("quantity_micro_units", .integer).notNull()
                table.column("unit_price_minor", .integer).notNull()
                table.column("unit_cost_minor", .integer).notNull()
                table.column("discount_minor", .integer).notNull()
                table.column("tax_minor", .integer).notNull()
                table.column("line_total_minor", .integer).notNull()
            }
            try db.create(index: "sale_lines_sale", on: "sale_lines", columns: ["sale_id"])
            try db.create(table: "sale_payments") { table in
                table.column("id", .text).primaryKey()
                table.column("sale_id", .text).notNull().references("sales", onDelete: .restrict)
                table.column("payment_method", .text).notNull()
                table.column("amount_minor", .integer).notNull()
                table.column("amount_tendered_minor", .integer).notNull()
                table.column("change_minor", .integer).notNull()
                table.column("currency", .text).notNull()
                table.column("status", .text).notNull()
                table.column("paid_at", .datetime).notNull()
            }
            try db.create(table: "audit_events") { table in
                table.column("id", .text).primaryKey()
                table.column("action", .text).notNull()
                table.column("entity_type", .text).notNull()
                table.column("entity_id", .text).notNull()
                table.column("after_json", .text)
                table.column("created_at", .datetime).notNull()
            }
            try db.create(table: "sync_outbox") { table in
                table.column("event_id", .text).primaryKey()
                table.column("device_sequence", .integer).notNull().unique()
                table.column("entity_type", .text).notNull()
                table.column("entity_id", .text).notNull()
                table.column("operation", .text).notNull()
                table.column("schema_version", .integer).notNull()
                table.column("payload_json", .text).notNull()
                table.column("payload_hash", .text).notNull()
                table.column("occurred_at", .datetime).notNull()
                table.column("status", .text).notNull()
                table.column("attempt_count", .integer).notNull()
                table.column("next_attempt_at", .datetime)
                table.column("last_error_code", .text)
                table.column("created_at", .datetime).notNull()
                table.column("acknowledged_at", .datetime)
            }
            try db.create(index: "sync_outbox_status_sequence", on: "sync_outbox", columns: ["status", "device_sequence"])

            let registerId = "30000000-0000-4000-8000-000000000001"
            let shiftId = "30000000-0000-4000-8000-000000000002"
            try db.execute(sql: "INSERT INTO registers (id, name, code) VALUES (?, 'Main Register', 'IPHN01')", arguments: [registerId])
            try db.execute(sql: """
                INSERT INTO register_shifts (id, register_id, status, opening_cash_minor, currency, opened_at)
                VALUES (?, ?, 'open', 10000000, 'MMK', ?)
                """, arguments: [shiftId, registerId, Date()])
            try db.execute(sql: "INSERT INTO device_state (id, device_sequence, receipt_sequence) VALUES (1, 0, 0)")
        }
        return migrator
    }
}

struct StoreProduct: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let localName: String?
    let sku: String
    let category: String
    let barcode: String?
    let unitPrice: Money
    let unitCost: Money
    let stockQuantity: Quantity
    let lowStockThreshold: Quantity
    let allowNegativeStock: Bool

    init(row: Row) throws {
        guard let id = UUID(uuidString: row["id"]) else {
            throw DatabaseError(message: "Invalid product identifier")
        }
        self.id = id
        name = row["name"]
        localName = row["local_name"]
        sku = row["sku"]
        category = row["category"]
        barcode = row["barcode"]
        let currency: String = row["currency"]
        unitPrice = try Money(minorUnits: row["unit_price_minor"], currency: currency)
        unitCost = try Money(minorUnits: row["unit_cost_minor"], currency: currency)
        stockQuantity = Quantity(microUnits: row["stock_micro_units"])
        lowStockThreshold = Quantity(microUnits: row["low_stock_micro_units"] ?? 0)
        allowNegativeStock = row["allow_negative_stock"]
    }
}
