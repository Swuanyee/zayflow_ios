import SwiftUI

struct ReportsView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Store snapshot")
                        .font(.title2.weight(.bold))
                    Text("Live figures calculated from this device")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: columns, spacing: 14) {
                    reportMetric("Sales today", model.salesToday.displayString, "chart.line.uptrend.xyaxis", ZayFlowTheme.brand)
                    reportMetric("Stock value", model.stockValue.displayString, "cube.box.fill", .indigo)
                    reportMetric("Products", "\(model.products.count)", "square.grid.2x2.fill", .blue)
                    reportMetric("Needs attention", "\(model.lowStockProducts.count)", "exclamationmark.triangle.fill", ZayFlowTheme.warning)
                }

                Text("Quick reports")
                    .font(.title3.weight(.bold))

                VStack(spacing: 10) {
                    reportLink("Daily sales", "Sales totals and payment methods", "calendar")
                    reportLink("Product sales", "Best sellers and quantities", "chart.bar.xaxis")
                    reportLink("Stock balance", "Current quantity and value", "shippingbox")
                    reportLink("Stock movement", "Opening stock, sales, and adjustments", "arrow.left.arrow.right")
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Reports")
    }

    private func reportMetric(_ title: String, _ value: String, _ symbol: String, _ color: Color) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 15) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 46, height: 46)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                Text(value)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func reportLink(_ title: String, _ subtitle: String, _ symbol: String) -> some View {
        Button {} label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(ZayFlowTheme.brand)
                    .frame(width: 44, height: 44)
                    .background(ZayFlowTheme.mintSurface, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
    }
}
