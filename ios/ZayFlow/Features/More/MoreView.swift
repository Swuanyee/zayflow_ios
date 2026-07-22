import SwiftUI

struct MoreView: View {
    @State private var allowNegativeStock = false
    @State private var showStockOnSell = true
    @State private var autoSync = true

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image("ZayFlowLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ZayFlow Demo Store")
                            .font(.headline)
                        Text("Yangon  |  MMK")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Store operations") {
                navigationRow("Register shift", "Open", "lock.open.fill", ZayFlowTheme.brand)
                navigationRow("Products", "16", "shippingbox.fill", .blue)
                navigationRow("Customers", nil, "person.2.fill", .purple)
                navigationRow("Payment methods", "Cash, QR", "creditcard.fill", .orange)
            }

            Section("Checkout preferences") {
                Toggle("Show stock while selling", isOn: $showStockOnSell)
                Toggle("Allow negative stock", isOn: $allowNegativeStock)
            }

            Section("Device and sync") {
                Toggle("Sync automatically", isOn: $autoSync)
                navigationRow("Sync status", "Ready offline", "checkmark.icloud.fill", ZayFlowTheme.brand)
                navigationRow("Barcode scanner", "Not tested", "barcode.viewfinder", .indigo)
                navigationRow("Receipt printer", "Not connected", "printer.fill", .gray)
            }

            Section("Data") {
                navigationRow("Export data", nil, "square.and.arrow.up.fill", .blue)
                navigationRow("Reset demo store", nil, "arrow.counterclockwise", ZayFlowTheme.warning)
            }

            Section {
                HStack {
                    Text("ZayFlow")
                    Spacer()
                    Text("Development build")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("More")
    }

    private func navigationRow(_ title: String, _ value: String?, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(title)
            Spacer()
            if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
