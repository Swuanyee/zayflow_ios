# ZayFlow

ZayFlow is an offline-first point-of-sale and inventory-management system for iPhone and iPad.

Current implementation priority:

- Native iOS POS foundation first.
- Functional development backend later for sync testing.
- Production backend hardening deferred.

The first executable slice lives in `ios/ZayFlowCore` and contains the POS domain primitives, demo catalogue fixture, and tests.

The iOS project vendors GRDB `v7.11.1` and the SQLCipher Swift package manifest for `4.11.0` under `ios/Vendor`. Their licenses are included. GRDB's package manifest is configured for its documented SQLCipher build path; SwiftPM downloads SQLCipher's checksum-pinned XCFramework on the first build.

## Local Verification

```bash
swift test --package-path ios/ZayFlowCore
```

## Demo Data

The bundled demo catalogue is inspired by publicly visible product/category examples from City Mall Myanmar. It is development fixture data only:

- Product names and observed price snapshots are used for realistic testing.
- Barcodes are synthetic `ZF-DEMO-*` values.
- Fifteen current product images are bundled locally from their exact City Mall source listings; the stale egg listing uses a category fallback.
- Prices are not current City Mall prices.

Image provenance and checksums are recorded in `documentation/demo-data/product-images.md`. These third-party images are intended for internal demonstration; confirm redistribution permission before an external release.
