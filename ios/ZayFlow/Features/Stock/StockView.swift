import SwiftUI

struct StockView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""

    var filteredProducts: [StoreProduct] {
        guard !searchText.isEmpty else { return model.products }
        return model.products.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.sku.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                summary
                LazyVStack(spacing: 10) {
                    ForEach(filteredProducts) { product in
                        stockRow(product)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Stock")
        .searchable(text: $searchText, prompt: "Search stock")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Receive stock", systemImage: "tray.and.arrow.down.fill") {}
                    Button("Adjust stock", systemImage: "slider.horizontal.3") {}
                    Button("Start stock count", systemImage: "checklist") {}
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            metric(title: "Products", value: "\(model.products.count)", symbol: "shippingbox.fill", color: ZayFlowTheme.brand)
            metric(title: "Low stock", value: "\(model.lowStockProducts.count)", symbol: "exclamationmark.triangle.fill", color: ZayFlowTheme.warning)
        }
    }

    private func metric(title: String, value: String, symbol: String, color: Color) -> some View {
        SurfaceCard {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text(value).font(.title2.weight(.bold).monospacedDigit())
                    Text(title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stockRow(_ product: StoreProduct) -> some View {
        let low = product.stockQuantity <= product.lowStockThreshold
        return HStack(spacing: 14) {
            ProductArtwork(product: product)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text("\(product.sku)  |  \(product.category)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(product.stockQuantity.decimalString)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(low ? ZayFlowTheme.warning : .primary)
                Text(low ? "Low stock" : "In stock")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(low ? ZayFlowTheme.warning : ZayFlowTheme.brand)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.05)) }
    }
}
