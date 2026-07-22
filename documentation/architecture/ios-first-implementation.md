# iOS-First Implementation

ZayFlow is being implemented from the local POS core outward.

## Initial Build Order

1. Domain primitives for money, quantity, products, and stock movements.
2. Bundled demo catalogue with realistic Myanmar retail examples.
3. Encrypted local database and migrations.
4. Inventory ledger and rebuildable balances.
5. Atomic offline checkout.
6. Scanner, receipt, shifts, returns, and receivables.
7. Thin development backend for sync protocol testing.

## POSNext-Informed Behaviors

The iOS checkout will include core cashier-speed patterns observed in POSNext:

- Grid and list product views.
- Held carts.
- Walk-in customer.
- Recent and frequent customers.
- Split and partial payments.
- Quick cash buttons.
- Stock-aware cart quantities.
- Shift status and reconciliation.
- Search by name, SKU, category, and barcode.

The implementation will not copy POSNext source code or assets.

## Deferred From The iOS-First Release

- Coupons and promotional engines.
- Gift cards and loyalty wallets.
- Multi-warehouse transfers.
- Batch and serial tracking.
- ERPNext integration.
- Production-grade backend operations.
