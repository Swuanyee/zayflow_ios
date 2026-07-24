import CryptoKit
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

    func fetchProducts(shopID: UUID? = nil, deviceID: UUID? = nil) throws -> [StoreProduct] {
        try writer.read { db in
            if let shopID {
                let restrictionSQL = deviceID == nil ? "" : """
                    AND (
                        NOT EXISTS (SELECT 1 FROM org_device_category_permissions dcp WHERE dcp.device_id = ?)
                        OR EXISTS (SELECT 1 FROM org_device_category_permissions dcp WHERE dcp.device_id = ? AND dcp.category = p.category)
                    )
                    """
                var arguments: StatementArguments = [shopID.uuidString]
                if let deviceID {
                    arguments += [deviceID.uuidString, deviceID.uuidString]
                }
                let rows = try Row.fetchAll(db, sql: """
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
                    WHERE sp.shop_id = ? AND sp.enabled = 1 AND p.active = 1
                    \(restrictionSQL)
                    ORDER BY p.name COLLATE NOCASE
                    """, arguments: arguments)
                return try rows.map(StoreProduct.init(row:))
            }
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

    func product(barcode: String, shopID: UUID? = nil, deviceID: UUID? = nil) throws -> StoreProduct? {
        try writer.read { db in
            if let shopID {
                let restrictionSQL = deviceID == nil ? "" : """
                    AND (
                        NOT EXISTS (SELECT 1 FROM org_device_category_permissions dcp WHERE dcp.device_id = ?)
                        OR EXISTS (SELECT 1 FROM org_device_category_permissions dcp WHERE dcp.device_id = ? AND dcp.category = p.category)
                    )
                    """
                var arguments: StatementArguments = [shopID.uuidString, barcode.uppercased()]
                if let deviceID {
                    arguments += [deviceID.uuidString, deviceID.uuidString]
                }
                guard let row = try Row.fetchOne(db, sql: """
                    SELECT p.id, p.name, p.local_name, p.sku, p.category, p.product_type,
                           p.track_stock, p.allow_negative_stock, p.unit_cost_minor, p.currency,
                           COALESCE(sp.price_override_minor, p.unit_price_minor) AS unit_price_minor,
                           sp.low_stock_micro_units AS low_stock_micro_units,
                           b.barcode,
                           COALESCE(ib.quantity_micro_units, 0) AS stock_micro_units
                    FROM product_barcodes b
                    JOIN products p ON p.id = b.product_id
                    JOIN org_shop_products sp ON sp.product_id = p.id AND sp.shop_id = ?
                    LEFT JOIN org_inventory_balances ib ON ib.shop_id = sp.shop_id AND ib.product_id = sp.product_id
                    WHERE b.normalized_barcode = ? AND sp.enabled = 1 AND p.active = 1
                    \(restrictionSQL)
                    LIMIT 1
                    """, arguments: arguments) else { return nil }
                return try StoreProduct(row: row)
            }
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
            if try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM products") == 0 {
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

            if try String.fetchOne(db, sql: "SELECT value FROM app_metadata WHERE key = 'organisation_demo_version'") != "1" {
                try Self.seedOrganisationDemo(db)
                try db.execute(sql: "INSERT OR REPLACE INTO app_metadata (key, value) VALUES ('organisation_demo_version', '1')")
            }
        }
    }

    private static func seedOrganisationDemo(_ db: Database) throws {
        let now = Date()
        let organizationId = "20000000-0000-4000-8000-000000000001"
        try db.execute(sql: """
            INSERT OR IGNORE INTO org_organizations (id, code, name, currency, timezone, status)
            VALUES (?, 'DEMO', 'ZayFlow Demo Store', 'MMK', 'Asia/Yangon', 'active')
            """, arguments: [organizationId])

        let shops: [(String, String, String, String)] = [
            ("21000000-0000-4000-8000-000000000001", "YGN-MAIN", "Yangon Main", "Downtown Yangon"),
            ("21000000-0000-4000-8000-000000000002", "HLEDAN", "Hledan Express", "Hledan Centre"),
            ("21000000-0000-4000-8000-000000000003", "TAMWE", "Tamwe Market", "Tamwe Township")
        ]
        for shop in shops {
            try db.execute(sql: """
                INSERT OR IGNORE INTO org_shops (id, organization_id, code, name, city, address, status, created_at, updated_at)
                VALUES (?, ?, ?, ?, 'Yangon', ?, 'active', ?, ?)
                """, arguments: [shop.0, organizationId, shop.1, shop.2, shop.3, now, now])
        }

        let users: [(String, String, String, String, String, Bool, Bool, [String])] = [
            ("80000000-0000-4000-8000-000000000001", "OWNER", "Demo Owner", "owner", "demo", true, true, shops.map(\.0)),
            ("80000000-0000-4000-8000-000000000002", "ADMIN", "Demo Admin", "admin", "demo", true, true, shops.map(\.0)),
            ("80000000-0000-4000-8000-000000000003", "MANAGER", "Demo Manager", "manager", "demo", true, true, [shops[0].0, shops[1].0]),
            ("80000000-0000-4000-8000-000000000004", "CASHIER", "Demo Cashier", "cashier", "demo", true, false, [shops[0].0])
        ]
        for user in users {
            try db.execute(sql: """
                INSERT OR IGNORE INTO org_users (
                    id, organization_id, user_code, display_name, role, status,
                    can_sell, can_intake, password_hash, must_change_password, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, 'active', ?, ?, ?, 0, ?, ?)
                """, arguments: [
                    user.0, organizationId, user.1, user.2, user.3, user.5, user.6,
                    passwordHash(orgCode: "DEMO", userCode: user.1, password: user.4), now, now
                ])
                for shopId in user.7 {
                    try db.execute(sql: """
                        INSERT OR IGNORE INTO org_user_shop_memberships (user_id, shop_id, created_at)
                        VALUES (?, ?, ?)
                        """, arguments: [user.0, shopId, now])
                }
        }

        let productRows = try Row.fetchAll(db, sql: "SELECT id, unit_price_minor, unit_cost_minor FROM products WHERE active = 1 ORDER BY name COLLATE NOCASE")
        for (index, row) in productRows.enumerated() {
            let productId: String = row["id"]
            for (shopIndex, shop) in shops.enumerated() {
                let assigned = shopIndex == 0 || index % (shopIndex + 2) != 0
                guard assigned else { continue }
                let price: Int64 = row["unit_price_minor"]
                let cost: Int64 = row["unit_cost_minor"]
                let quantity = Quantity.units(Int64(16 + ((index * 9 + shopIndex * 11) % 64)))
                try db.execute(sql: """
                    INSERT OR IGNORE INTO org_shop_products (
                        shop_id, product_id, enabled, price_override_minor, low_stock_micro_units, created_at, updated_at
                    ) VALUES (?, ?, 1, ?, ?, ?, ?)
                    """, arguments: [shop.0, productId, price + Int64(shopIndex * 25000), Quantity.units(8 + Int64(shopIndex * 3)).microUnits, now, now])
                try db.execute(sql: """
                    INSERT OR IGNORE INTO org_inventory_balances (shop_id, product_id, quantity_micro_units, updated_at)
                    VALUES (?, ?, ?, ?)
                    """, arguments: [shop.0, productId, quantity.microUnits, now])
                try db.execute(sql: """
                    INSERT INTO org_inventory_movements (id, shop_id, product_id, movement_type, quantity_delta_micro_units, reason, occurred_at)
                    VALUES (?, ?, ?, 'opening_stock', ?, 'Demo opening balance', ?)
                    """, arguments: [UUID().uuidString, shop.0, productId, quantity.microUnits, now])

                for dayOffset in 0..<90 {
                    let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: -dayOffset, to: now) ?? now
                    let units = Int64((index + 1 + shopIndex * 3 + dayOffset) % 7)
                    let revenue = units * (price + Int64(shopIndex * 25000))
                    let costTotal = units * cost
                    let inventoryUnits = max(0, quantity.microUnits / Quantity.scale - Int64(dayOffset % 12))
                    try db.execute(sql: """
                        INSERT INTO org_daily_metrics (
                            id, metric_date, shop_id, product_id, category, revenue_minor,
                            cost_minor, units_micro_units, transaction_count, inventory_value_minor
                        ) VALUES (?, ?, ?, ?, (SELECT category FROM products WHERE id = ?), ?, ?, ?, ?, ?)
                        """, arguments: [
                            UUID().uuidString, organisationBusinessDate(date), shop.0, productId, productId,
                            revenue, costTotal, units * Quantity.scale, units > 0 ? 1 : 0, inventoryUnits * cost
                        ])
                }
            }
        }
    }

    private static func passwordHash(orgCode: String, userCode: String, password: String) -> String {
        let normalized = "zayflow-demo:\(orgCode.uppercased()):\(userCode.uppercased()):\(password)"
        return SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func organisationBusinessDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Yangon")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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
        migrator.registerMigration("v3_organisation_dashboard") { db in
            try db.create(table: "org_organizations") { table in
                table.column("id", .text).primaryKey()
                table.column("code", .text).notNull().unique()
                table.column("name", .text).notNull()
                table.column("currency", .text).notNull()
                table.column("timezone", .text).notNull()
                table.column("status", .text).notNull()
            }
            try db.create(table: "org_shops") { table in
                table.column("id", .text).primaryKey()
                table.column("organization_id", .text).notNull().references("org_organizations", onDelete: .cascade)
                table.column("code", .text).notNull().unique()
                table.column("name", .text).notNull()
                table.column("city", .text).notNull()
                table.column("address", .text)
                table.column("status", .text).notNull()
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "org_users") { table in
                table.column("id", .text).primaryKey()
                table.column("organization_id", .text).notNull().references("org_organizations", onDelete: .cascade)
                table.column("user_code", .text).notNull().unique()
                table.column("display_name", .text).notNull()
                table.column("role", .text).notNull()
                table.column("status", .text).notNull()
                table.column("can_sell", .boolean).notNull()
                table.column("can_intake", .boolean).notNull()
                table.column("password_hash", .text).notNull()
                table.column("must_change_password", .boolean).notNull()
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "org_user_shop_memberships") { table in
                table.column("user_id", .text).notNull().references("org_users", onDelete: .cascade)
                table.column("shop_id", .text).notNull().references("org_shops", onDelete: .cascade)
                table.column("created_at", .datetime).notNull()
                table.primaryKey(["user_id", "shop_id"])
            }
            try db.create(table: "org_shop_products") { table in
                table.column("shop_id", .text).notNull().references("org_shops", onDelete: .cascade)
                table.column("product_id", .text).notNull().references("products", onDelete: .cascade)
                table.column("enabled", .boolean).notNull()
                table.column("price_override_minor", .integer)
                table.column("low_stock_micro_units", .integer).notNull()
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
                table.primaryKey(["shop_id", "product_id"])
            }
            try db.create(table: "org_inventory_balances") { table in
                table.column("shop_id", .text).notNull().references("org_shops", onDelete: .cascade)
                table.column("product_id", .text).notNull().references("products", onDelete: .cascade)
                table.column("quantity_micro_units", .integer).notNull()
                table.column("updated_at", .datetime).notNull()
                table.primaryKey(["shop_id", "product_id"])
            }
            try db.create(table: "org_inventory_movements") { table in
                table.column("id", .text).primaryKey()
                table.column("shop_id", .text).notNull().references("org_shops", onDelete: .cascade)
                table.column("product_id", .text).notNull().references("products", onDelete: .restrict)
                table.column("movement_type", .text).notNull()
                table.column("quantity_delta_micro_units", .integer).notNull()
                table.column("reason", .text).notNull()
                table.column("occurred_at", .datetime).notNull()
            }
            try db.create(index: "org_inventory_movements_shop_date", on: "org_inventory_movements", columns: ["shop_id", "occurred_at"])
            try db.create(table: "org_daily_metrics") { table in
                table.column("id", .text).primaryKey()
                table.column("metric_date", .text).notNull()
                table.column("shop_id", .text).notNull().references("org_shops", onDelete: .cascade)
                table.column("product_id", .text).notNull().references("products", onDelete: .cascade)
                table.column("category", .text).notNull()
                table.column("revenue_minor", .integer).notNull()
                table.column("cost_minor", .integer).notNull()
                table.column("units_micro_units", .integer).notNull()
                table.column("transaction_count", .integer).notNull()
                table.column("inventory_value_minor", .integer).notNull()
            }
            try db.create(index: "org_daily_metrics_date_shop", on: "org_daily_metrics", columns: ["metric_date", "shop_id"])
        }
        migrator.registerMigration("v4_shop_scoped_pos_sales") { db in
            try db.alter(table: "sales") { table in
                table.add(column: "organization_id", .text)
                table.add(column: "shop_id", .text)
                table.add(column: "user_id", .text)
                table.add(column: "device_id", .text)
            }
            try db.create(index: "sales_shop_occurred", on: "sales", columns: ["shop_id", "occurred_at"])
            try db.execute(sql: """
                UPDATE sales
                SET organization_id = COALESCE(organization_id, '20000000-0000-4000-8000-000000000001'),
                    shop_id = COALESCE(shop_id, '21000000-0000-4000-8000-000000000001'),
                    user_id = COALESCE(user_id, '80000000-0000-4000-8000-000000000001'),
                    device_id = COALESCE(device_id, '60000000-0000-4000-8000-000000000001')
                """)
        }
        migrator.registerMigration("v5_device_category_restrictions") { db in
            try db.create(table: "org_pos_devices") { table in
                table.column("id", .text).primaryKey()
                table.column("organization_id", .text).notNull().references("org_organizations", onDelete: .cascade)
                table.column("shop_id", .text).references("org_shops", onDelete: .setNull)
                table.column("label", .text).notNull()
                table.column("platform", .text).notNull()
                table.column("status", .text).notNull()
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
            }
            try db.create(index: "org_pos_devices_shop_status", on: "org_pos_devices", columns: ["shop_id", "status"])
            try db.create(table: "org_device_category_permissions") { table in
                table.column("device_id", .text).notNull().references("org_pos_devices", onDelete: .cascade)
                table.column("category", .text).notNull()
                table.primaryKey(["device_id", "category"])
            }
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

struct OrganisationSnapshot: Equatable, Sendable {
    let shops: [OrganisationShop]
    let users: [OrganisationUser]
    let devices: [OrganisationDevice]
    let catalog: [OrganisationCatalogItem]
    let inventory: [OrganisationInventoryItem]
    let dailyMetrics: [OrganisationDailyMetric]

    var overview: OrganisationOverview {
        let revenue = dailyMetrics.reduce(Int64(0)) { $0 + $1.revenue.minorUnits }
        let cost = dailyMetrics.reduce(Int64(0)) { $0 + $1.cost.minorUnits }
        let units = dailyMetrics.reduce(Int64(0)) { $0 + $1.units.microUnits }
        let transactions = dailyMetrics.reduce(0) { $0 + $1.transactionCount }
        let inventoryValue = inventory.reduce(Int64(0)) { partial, item in
            partial + item.unitCost.minorUnits * (item.quantity.microUnits / Quantity.scale)
        }
        return OrganisationOverview(
            revenue: (try? Money(minorUnits: revenue, currency: "MMK")) ?? .mmk(0),
            grossProfit: (try? Money(minorUnits: revenue - cost, currency: "MMK")) ?? .mmk(0),
            inventoryValue: (try? Money(minorUnits: inventoryValue, currency: "MMK")) ?? .mmk(0),
            unitsSold: Quantity(microUnits: units),
            transactions: transactions,
            lowStockCount: inventory.filter(\.isLowStock).count
        )
    }
}

struct OrganisationOverview: Equatable, Sendable {
    let revenue: Money
    let grossProfit: Money
    let inventoryValue: Money
    let unitsSold: Quantity
    let transactions: Int
    let lowStockCount: Int

    var grossMarginText: String {
        guard revenue.minorUnits > 0 else { return "0%" }
        return "\((Double(grossProfit.minorUnits) / Double(revenue.minorUnits) * 100).formatted(.number.precision(.fractionLength(1))))%"
    }
}

struct OrganisationShop: Identifiable, Equatable, Sendable {
    let id: UUID
    let code: String
    let name: String
    let city: String
    let address: String?
    let status: String
    let itemCount: Int
    let inventoryValue: Money
    let lowStockCount: Int
    let userCount: Int
}

struct OrganisationUser: Identifiable, Equatable, Sendable {
    let id: UUID
    let userCode: String
    let displayName: String
    let role: UserRole
    let status: String
    let canSell: Bool
    let canIntake: Bool
    let shopCodes: [String]
}

struct OrganisationDevice: Identifiable, Equatable, Sendable {
    let id: UUID
    let label: String
    let platform: String
    let status: String
    let shopCode: String?
    let allowedCategories: [String]

    var isUnrestricted: Bool { allowedCategories.isEmpty }
}

struct OrganisationCatalogItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let sku: String
    let category: String
    let barcode: String?
    let unitPrice: Money
    let unitCost: Money
    let assignedShopCodes: [String]
    let active: Bool
}

struct OrganisationInventoryItem: Identifiable, Equatable, Sendable {
    var id: String { "\(shop.id.uuidString)-\(productId.uuidString)" }
    let shop: AuthSession.Shop
    let productId: UUID
    let productName: String
    let sku: String
    let category: String
    let quantity: Quantity
    let lowStockThreshold: Quantity
    let unitCost: Money

    var isLowStock: Bool { quantity <= lowStockThreshold }
    var value: Money {
        (try? unitCost.multiplied(by: quantity)) ?? .mmk(0)
    }
}

struct OrganisationDailyMetric: Identifiable, Equatable, Sendable {
    var id: String { "\(date)-\(shopCode)-\(category)" }
    let date: String
    let shopCode: String
    let category: String
    let revenue: Money
    let cost: Money
    let units: Quantity
    let transactionCount: Int
}

enum OrganisationWriteError: LocalizedError {
    case duplicateCode(String)
    case missingShop
    case missingProduct

    var errorDescription: String? {
        switch self {
        case .duplicateCode(let code): "\(code) already exists."
        case .missingShop: "Choose at least one shop."
        case .missingProduct: "The selected item is no longer available."
        }
    }
}

extension AppDatabase {
    func fetchOrganisationSnapshot(permittedShopIDs: [UUID]) throws -> OrganisationSnapshot {
        try writer.read { db in
            let shopFilter = Self.shopFilter(permittedShopIDs)
            let shops = try Self.fetchOrganisationShops(db, shopFilter: shopFilter)
            let users = try Self.fetchOrganisationUsers(db, shopFilter: shopFilter)
            let devices = try Self.fetchOrganisationDevices(db, shopFilter: shopFilter)
            let catalog = try Self.fetchOrganisationCatalog(db, shopFilter: shopFilter)
            let inventory = try Self.fetchOrganisationInventory(db, shopFilter: shopFilter)
            let metrics = try Self.fetchOrganisationMetrics(db, shopFilter: shopFilter)
            return OrganisationSnapshot(shops: shops, users: users, devices: devices, catalog: catalog, inventory: inventory, dailyMetrics: metrics)
        }
    }

    func registerLocalDevice(deviceID: UUID, organizationID: UUID, shopID: UUID?, label: String, platform: String = "ios") throws {
        let now = Date()
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO org_pos_devices (id, organization_id, shop_id, label, platform, status, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, 'active', ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    organization_id = excluded.organization_id,
                    shop_id = COALESCE(excluded.shop_id, org_pos_devices.shop_id),
                    label = excluded.label,
                    platform = excluded.platform,
                    status = 'active',
                    updated_at = excluded.updated_at
                """, arguments: [deviceID.uuidString, organizationID.uuidString, shopID?.uuidString, label, platform, now, now])
        }
    }

    func updateDeviceCategoryRestrictions(deviceID: UUID, categories: Set<String>) throws {
        let now = Date()
        let normalized = categories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.sorted()
        try writer.write { db in
            try db.execute(sql: "DELETE FROM org_device_category_permissions WHERE device_id = ?", arguments: [deviceID.uuidString])
            for category in normalized {
                try db.execute(sql: "INSERT INTO org_device_category_permissions (device_id, category) VALUES (?, ?)", arguments: [deviceID.uuidString, category])
            }
            try db.execute(sql: "UPDATE org_pos_devices SET updated_at = ? WHERE id = ?", arguments: [now, deviceID.uuidString])
            try Self.insertOrganisationEvent(db, entityType: "device", entityId: deviceID, operation: "categories_updated", payload: ["categories": normalized], now: now)
        }
    }

    func authenticateLocalDemo(mode: LoginMode, orgId: String, shopId: String?, userId: String, password: String) throws -> AuthSession? {
        try writer.read { db in
            let orgCode = orgId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let userCode = userId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard let org = try Row.fetchOne(db, sql: "SELECT * FROM org_organizations WHERE code = ? AND status = 'active'", arguments: [orgCode]),
                  let userRow = try Row.fetchOne(db, sql: "SELECT * FROM org_users WHERE organization_id = ? AND user_code = ? AND status = 'active'", arguments: [org["id"] as String, userCode]) else {
                return nil
            }
            guard userRow["password_hash"] == Self.passwordHash(orgCode: orgCode, userCode: userCode, password: password) else { return nil }
            let role = UserRole(rawValue: userRow["role"] as String) ?? .cashier
            guard mode == .pos || role.canUseOrganisationDashboard else { return nil }

            let permittedRows: [Row]
            if role == .owner || role == .admin {
                permittedRows = try Row.fetchAll(db, sql: "SELECT * FROM org_shops WHERE organization_id = ? AND status = 'active' ORDER BY name", arguments: [org["id"] as String])
            } else {
                permittedRows = try Row.fetchAll(db, sql: """
                    SELECT s.* FROM org_shops s
                    JOIN org_user_shop_memberships m ON m.shop_id = s.id
                    WHERE m.user_id = ? AND s.status = 'active'
                    ORDER BY s.name
                    """, arguments: [userRow["id"] as String])
            }
            let permittedShops = try permittedRows.map(Self.authShop)
            let selectedShop: AuthSession.Shop?
            if mode == .pos {
                let normalizedShop = shopId?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard let normalizedShop,
                      let shop = permittedShops.first(where: { $0.code == normalizedShop || $0.id.uuidString.uppercased() == normalizedShop }) else { return nil }
                selectedShop = shop
            } else {
                selectedShop = nil
            }

            let installationId = UserDefaults.standard.string(forKey: "deviceInstallationId") ?? UUID().uuidString
            UserDefaults.standard.set(installationId, forKey: "deviceInstallationId")
            let now = Date()
            return AuthSession(
                mode: mode,
                organization: AuthSession.Organization(id: try Self.uuid(org["id"]), code: org["code"], name: org["name"]),
                shop: selectedShop,
                user: AuthSession.User(
                    id: try Self.uuid(userRow["id"]),
                    userCode: userRow["user_code"],
                    displayName: userRow["display_name"],
                    role: role,
                    canSell: userRow["can_sell"],
                    canIntake: userRow["can_intake"]
                ),
                permittedShops: permittedShops,
                device: AuthSession.Device(installationId: installationId, requiresFullSyncBy: now.addingTimeInterval(7 * 86_400)),
                issuedAt: now
            )
        }
    }

    func addOrganisationShop(code: String, name: String, city: String, address: String?) throws {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        try writer.write { db in
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM org_shops WHERE code = ?", arguments: [normalizedCode]) == 0 else {
                throw OrganisationWriteError.duplicateCode(normalizedCode)
            }
            let id = UUID()
            try db.execute(sql: """
                INSERT INTO org_shops (id, organization_id, code, name, city, address, status, created_at, updated_at)
                VALUES (?, '20000000-0000-4000-8000-000000000001', ?, ?, ?, ?, 'active', ?, ?)
                """, arguments: [id.uuidString, normalizedCode, trimmedName, trimmedCity, address, now, now])
            try Self.assignPrivilegedUsersToShop(db, shopId: id, now: now)
            try Self.insertOrganisationEvent(db, entityType: "shop", entityId: id, operation: "create", payload: ["code": normalizedCode, "name": trimmedName], now: now)
        }
    }

    func addOrganisationCatalogItem(name: String, sku: String, category: String, priceMajor: Int64, costMajor: Int64, shopIDs: [UUID], openingStock: Int64) throws {
        guard !shopIDs.isEmpty else { throw OrganisationWriteError.missingShop }
        let now = Date()
        let id = UUID()
        let normalizedSKU = sku.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        try writer.write { db in
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM products WHERE sku = ?", arguments: [normalizedSKU]) == 0 else {
                throw OrganisationWriteError.duplicateCode(normalizedSKU)
            }
            try db.execute(sql: """
                INSERT INTO products (
                    id, name, sku, category, product_type, track_stock, allow_negative_stock,
                    low_stock_micro_units, unit_price_minor, unit_cost_minor, currency, active
                ) VALUES (?, ?, ?, ?, 'stock', 1, 0, ?, ?, ?, 'MMK', 1)
                """, arguments: [id.uuidString, name, normalizedSKU, category, Quantity.units(8).microUnits, priceMajor * Money.scale, costMajor * Money.scale])
            for shopId in shopIDs {
                try db.execute(sql: """
                    INSERT INTO org_shop_products (shop_id, product_id, enabled, price_override_minor, low_stock_micro_units, created_at, updated_at)
                    VALUES (?, ?, 1, ?, ?, ?, ?)
                    """, arguments: [shopId.uuidString, id.uuidString, priceMajor * Money.scale, Quantity.units(8).microUnits, now, now])
                try db.execute(sql: """
                    INSERT INTO org_inventory_balances (shop_id, product_id, quantity_micro_units, updated_at)
                    VALUES (?, ?, ?, ?)
                    """, arguments: [shopId.uuidString, id.uuidString, Quantity.units(openingStock).microUnits, now])
                try db.execute(sql: """
                    INSERT INTO org_inventory_movements (id, shop_id, product_id, movement_type, quantity_delta_micro_units, reason, occurred_at)
                    VALUES (?, ?, ?, 'opening_stock', ?, 'New catalog item', ?)
                    """, arguments: [UUID().uuidString, shopId.uuidString, id.uuidString, Quantity.units(openingStock).microUnits, now])
            }
            try Self.insertOrganisationEvent(db, entityType: "catalog_item", entityId: id, operation: "create", payload: ["sku": normalizedSKU, "name": name], now: now)
        }
    }

    func adjustOrganisationInventory(shopID: UUID, productID: UUID, deltaUnits: Int64, reason: String) throws {
        let now = Date()
        try writer.write { db in
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM org_shop_products WHERE shop_id = ? AND product_id = ?", arguments: [shopID.uuidString, productID.uuidString]) == 1 else {
                throw OrganisationWriteError.missingProduct
            }
            try db.execute(sql: """
                INSERT INTO org_inventory_balances (shop_id, product_id, quantity_micro_units, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(shop_id, product_id) DO UPDATE SET
                    quantity_micro_units = quantity_micro_units + excluded.quantity_micro_units,
                    updated_at = excluded.updated_at
                """, arguments: [shopID.uuidString, productID.uuidString, Quantity.units(deltaUnits).microUnits, now])
            try db.execute(sql: """
                INSERT INTO org_inventory_movements (id, shop_id, product_id, movement_type, quantity_delta_micro_units, reason, occurred_at)
                VALUES (?, ?, ?, 'adjustment', ?, ?, ?)
                """, arguments: [UUID().uuidString, shopID.uuidString, productID.uuidString, Quantity.units(deltaUnits).microUnits, reason, now])
            try Self.insertOrganisationEvent(db, entityType: "inventory", entityId: productID, operation: "adjust", payload: ["shopId": shopID.uuidString, "deltaUnits": deltaUnits], now: now)
        }
    }

    func addOrganisationUser(userCode: String, displayName: String, role: UserRole, password: String, shopIDs: [UUID], canSell: Bool, canIntake: Bool) throws {
        let normalizedUser = userCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let now = Date()
        let id = UUID()
        try writer.write { db in
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM org_users WHERE user_code = ?", arguments: [normalizedUser]) == 0 else {
                throw OrganisationWriteError.duplicateCode(normalizedUser)
            }
            try db.execute(sql: """
                INSERT INTO org_users (
                    id, organization_id, user_code, display_name, role, status,
                    can_sell, can_intake, password_hash, must_change_password, created_at, updated_at
                ) VALUES (?, '20000000-0000-4000-8000-000000000001', ?, ?, ?, 'active', ?, ?, ?, 0, ?, ?)
                """, arguments: [
                    id.uuidString, normalizedUser, displayName, role.rawValue, canSell, canIntake,
                    Self.passwordHash(orgCode: "DEMO", userCode: normalizedUser, password: password), now, now
                ])
            let assignedShopIDs: [UUID]
            if role == .owner || role == .admin {
                assignedShopIDs = try Row.fetchAll(db, sql: "SELECT id FROM org_shops WHERE status = 'active'").compactMap { try? Self.uuid($0["id"] as String) }
            } else {
                assignedShopIDs = shopIDs
            }
            for shopId in assignedShopIDs {
                try db.execute(sql: "INSERT OR IGNORE INTO org_user_shop_memberships (user_id, shop_id, created_at) VALUES (?, ?, ?)", arguments: [id.uuidString, shopId.uuidString, now])
            }
            try Self.insertOrganisationEvent(db, entityType: "user", entityId: id, operation: "create", payload: ["userCode": normalizedUser, "role": role.rawValue], now: now)
        }
    }

    private static func fetchOrganisationShops(_ db: Database, shopFilter: String) throws -> [OrganisationShop] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT s.*,
                   COUNT(DISTINCT sp.product_id) AS item_count,
                   COALESCE(SUM(ib.quantity_micro_units / ? * p.unit_cost_minor), 0) AS inventory_value_minor,
                   SUM(CASE WHEN COALESCE(ib.quantity_micro_units, 0) <= COALESCE(sp.low_stock_micro_units, 0) THEN 1 ELSE 0 END) AS low_stock_count,
                   COUNT(DISTINCT m.user_id) AS user_count
            FROM org_shops s
            LEFT JOIN org_shop_products sp ON sp.shop_id = s.id AND sp.enabled = 1
            LEFT JOIN products p ON p.id = sp.product_id
            LEFT JOIN org_inventory_balances ib ON ib.shop_id = s.id AND ib.product_id = sp.product_id
            LEFT JOIN org_user_shop_memberships m ON m.shop_id = s.id
            WHERE s.status = 'active' \(shopFilter)
            GROUP BY s.id
            ORDER BY s.name COLLATE NOCASE
            """, arguments: [Quantity.scale])
        return try rows.map { row in
            OrganisationShop(
                id: try uuid(row["id"]), code: row["code"], name: row["name"], city: row["city"], address: row["address"], status: row["status"],
                itemCount: row["item_count"], inventoryValue: try Money(minorUnits: row["inventory_value_minor"], currency: "MMK"),
                lowStockCount: row["low_stock_count"] ?? 0, userCount: row["user_count"]
            )
        }
    }

    private static func fetchOrganisationUsers(_ db: Database, shopFilter: String) throws -> [OrganisationUser] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT u.*, GROUP_CONCAT(s.code, ',') AS shop_codes
            FROM org_users u
            LEFT JOIN org_user_shop_memberships m ON m.user_id = u.id
            LEFT JOIN org_shops s ON s.id = m.shop_id
            WHERE u.status = 'active'
            GROUP BY u.id
            ORDER BY u.display_name COLLATE NOCASE
            """)
        return try rows.map { row in
            let codes = (row["shop_codes"] as String?)?.split(separator: ",").map(String.init).sorted() ?? []
            return OrganisationUser(
                id: try uuid(row["id"]), userCode: row["user_code"], displayName: row["display_name"],
                role: UserRole(rawValue: row["role"] as String) ?? .cashier, status: row["status"],
                canSell: row["can_sell"], canIntake: row["can_intake"], shopCodes: codes
            )
        }
    }

    private static func fetchOrganisationDevices(_ db: Database, shopFilter: String) throws -> [OrganisationDevice] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT d.*, s.code AS shop_code, GROUP_CONCAT(cp.category, ',') AS categories
            FROM org_pos_devices d
            LEFT JOIN org_shops s ON s.id = d.shop_id
            LEFT JOIN org_device_category_permissions cp ON cp.device_id = d.id
            WHERE d.status = 'active' \(shopFilter.replacingOccurrences(of: "s.id", with: "d.shop_id"))
            GROUP BY d.id
            ORDER BY d.label COLLATE NOCASE
            """)
        return try rows.map { row in
            OrganisationDevice(
                id: try uuid(row["id"]),
                label: row["label"],
                platform: row["platform"],
                status: row["status"],
                shopCode: row["shop_code"],
                allowedCategories: (row["categories"] as String?)?.split(separator: ",").map(String.init).sorted() ?? []
            )
        }
    }

    private static func fetchOrganisationCatalog(_ db: Database, shopFilter: String) throws -> [OrganisationCatalogItem] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT p.*, b.barcode, GROUP_CONCAT(s.code, ',') AS shop_codes
            FROM products p
            LEFT JOIN product_barcodes b ON b.product_id = p.id AND b.is_primary = 1
            LEFT JOIN org_shop_products sp ON sp.product_id = p.id AND sp.enabled = 1
            LEFT JOIN org_shops s ON s.id = sp.shop_id
            WHERE p.active = 1
            GROUP BY p.id
            ORDER BY p.name COLLATE NOCASE
            """)
        return try rows.map { row in
            OrganisationCatalogItem(
                id: try uuid(row["id"]), name: row["name"], sku: row["sku"], category: row["category"], barcode: row["barcode"],
                unitPrice: try Money(minorUnits: row["unit_price_minor"], currency: row["currency"]),
                unitCost: try Money(minorUnits: row["unit_cost_minor"], currency: row["currency"]),
                assignedShopCodes: (row["shop_codes"] as String?)?.split(separator: ",").map(String.init).sorted() ?? [],
                active: row["active"]
            )
        }
    }

    private static func fetchOrganisationInventory(_ db: Database, shopFilter: String) throws -> [OrganisationInventoryItem] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT s.id AS shop_id, s.code AS shop_code, s.name AS shop_name,
                   p.id AS product_id, p.name, p.sku, p.category, p.unit_cost_minor, p.currency,
                   COALESCE(ib.quantity_micro_units, 0) AS quantity_micro_units,
                   sp.low_stock_micro_units
            FROM org_shop_products sp
            JOIN org_shops s ON s.id = sp.shop_id
            JOIN products p ON p.id = sp.product_id
            LEFT JOIN org_inventory_balances ib ON ib.shop_id = sp.shop_id AND ib.product_id = sp.product_id
            WHERE sp.enabled = 1 AND s.status = 'active' \(shopFilter)
            ORDER BY s.name COLLATE NOCASE, p.name COLLATE NOCASE
            """)
        return try rows.map { row in
            OrganisationInventoryItem(
                shop: AuthSession.Shop(id: try uuid(row["shop_id"]), code: row["shop_code"], name: row["shop_name"]),
                productId: try uuid(row["product_id"]), productName: row["name"], sku: row["sku"], category: row["category"],
                quantity: Quantity(microUnits: row["quantity_micro_units"]), lowStockThreshold: Quantity(microUnits: row["low_stock_micro_units"]),
                unitCost: try Money(minorUnits: row["unit_cost_minor"], currency: row["currency"])
            )
        }
    }

    private static func fetchOrganisationMetrics(_ db: Database, shopFilter: String) throws -> [OrganisationDailyMetric] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT m.metric_date, s.code AS shop_code, m.category,
                   SUM(m.revenue_minor) AS revenue_minor, SUM(m.cost_minor) AS cost_minor,
                   SUM(m.units_micro_units) AS units_micro_units, SUM(m.transaction_count) AS transaction_count
            FROM org_daily_metrics m
            JOIN org_shops s ON s.id = m.shop_id
            WHERE m.metric_date >= date('now', '-89 days') \(shopFilter.replacingOccurrences(of: "s.id", with: "m.shop_id"))
            GROUP BY m.metric_date, s.code, m.category
            ORDER BY m.metric_date
            """)
        return try rows.map { row in
            OrganisationDailyMetric(
                date: row["metric_date"], shopCode: row["shop_code"], category: row["category"],
                revenue: try Money(minorUnits: row["revenue_minor"], currency: "MMK"),
                cost: try Money(minorUnits: row["cost_minor"], currency: "MMK"),
                units: Quantity(microUnits: row["units_micro_units"]), transactionCount: row["transaction_count"]
            )
        }
    }

    private static func assignPrivilegedUsersToShop(_ db: Database, shopId: UUID, now: Date) throws {
        let userRows = try Row.fetchAll(db, sql: "SELECT id FROM org_users WHERE role IN ('owner', 'admin') AND status = 'active'")
        for row in userRows {
            try db.execute(sql: "INSERT OR IGNORE INTO org_user_shop_memberships (user_id, shop_id, created_at) VALUES (?, ?, ?)", arguments: [row["id"] as String, shopId.uuidString, now])
        }
    }

    private static func insertOrganisationEvent(_ db: Database, entityType: String, entityId: UUID, operation: String, payload: [String: Any], now: Date) throws {
        let eventId = UUID()
        let sequence = (try Int64.fetchOne(db, sql: "SELECT device_sequence FROM device_state WHERE id = 1") ?? 0) + 1
        let organizationId = try String.fetchOne(db, sql: "SELECT id FROM org_organizations WHERE code = 'DEMO' LIMIT 1") ?? "20000000-0000-4000-8000-000000000001"
        let locationId = try String.fetchOne(db, sql: "SELECT id FROM org_shops WHERE status = 'active' ORDER BY name LIMIT 1") ?? "21000000-0000-4000-8000-000000000001"
        let deviceId = UserDefaults.standard.string(forKey: "deviceInstallationId") ?? "60000000-0000-4000-8000-000000000001"
        let event: [String: Any] = [
            "eventId": eventId.uuidString,
            "type": "organisation.\(entityType).\(operation)",
            "deviceId": deviceId,
            "organizationId": organizationId,
            "locationId": locationId,
            "sequence": sequence,
            "occurredAt": ISO8601DateFormatter().string(from: now),
            "payload": payload.merging([
                "entityType": entityType,
                "entityId": entityId.uuidString,
                "operation": operation
            ]) { current, _ in current }
        ]
        let data = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
        let payloadJSON = String(decoding: data, as: UTF8.self)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try db.execute(sql: "UPDATE device_state SET device_sequence = ? WHERE id = 1", arguments: [sequence])
        try db.execute(sql: "INSERT INTO audit_events (id, action, entity_type, entity_id, after_json, created_at) VALUES (?, ?, ?, ?, ?, ?)", arguments: [UUID().uuidString, "organisation.\(operation)", entityType, entityId.uuidString, payloadJSON, now])
        try db.execute(sql: """
            INSERT INTO sync_outbox (
                event_id, device_sequence, entity_type, entity_id, operation, schema_version,
                payload_json, payload_hash, occurred_at, status, attempt_count, created_at
            ) VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, 'pending', 0, ?)
            """, arguments: [eventId.uuidString, sequence, entityType, entityId.uuidString, operation, payloadJSON, hash, now, now])
    }

    private static func shopFilter(_ ids: [UUID]) -> String {
        guard !ids.isEmpty else { return "" }
        let quoted = ids.map { "'\($0.uuidString)'" }.joined(separator: ",")
        return "AND s.id IN (\(quoted))"
    }

    private static func authShop(_ row: Row) throws -> AuthSession.Shop {
        AuthSession.Shop(id: try uuid(row["id"]), code: row["code"], name: row["name"])
    }

    private static func uuid(_ value: String) throws -> UUID {
        guard let id = UUID(uuidString: value) else { throw DatabaseError(message: "Invalid UUID") }
        return id
    }
}
