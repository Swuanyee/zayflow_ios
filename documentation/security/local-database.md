# Local Database Security

The iOS implementation uses GRDB, SQLCipher 4.11.0, WAL mode, foreign keys, explicit migrations, and iOS file protection with `completeUntilFirstUserAuthentication`.

## SQLCipher

The SQLCipher package manifest is vendored under `ios/Vendor/SQLCipher.swift` and downloads its checksum-pinned XCFramework on the first build. The vendored GRDB package is configured using its documented `SQLITE_HAS_CODEC` Swift Package Manager setup.

The production database uses a random 256-bit passphrase stored as a this-device-only Keychain item. The passphrase is applied before schema access. Startup also verifies `PRAGMA cipher_version` so the app fails closed if a non-SQLCipher SQLite build is accidentally linked.

Tests verify that the database header is encrypted and schema access without the passphrase fails.
