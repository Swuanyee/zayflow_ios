import SwiftUI

struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""

    private var filteredSales: [SaleSummary] {
        guard !searchText.isEmpty else { return model.sales }
        return model.sales.filter { $0.receiptNumber.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SurfaceCard {
                    HStack(spacing: 14) {
                        Image(systemName: "clock.badge.checkmark.fill")
                            .font(.title)
                            .foregroundStyle(ZayFlowTheme.brand)
                            .frame(width: 54, height: 54)
                            .background(ZayFlowTheme.mintSurface, in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sales activity")
                                .font(.headline)
                            Text("Completed sales, returns, and held carts will appear here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                HStack(spacing: 10) {
                    filter("Today", selected: true)
                    filter("This week", selected: false)
                    filter("Returns", selected: false)
                    Spacer()
                }

                if filteredSales.isEmpty {
                    ContentUnavailableView {
                        Label(model.sales.isEmpty ? "No sales yet" : "No matching sales", systemImage: "receipt")
                    } description: {
                        Text(model.sales.isEmpty ? "Your first completed sale will be stored on this device and shown here." : "Try another receipt number.")
                    } actions: {
                        if model.sales.isEmpty {
                            Button("Start selling") { model.selectedSection = .sell }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 70)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredSales) { sale in
                            saleRow(sale)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Activity")
        .searchable(text: $searchText, prompt: "Receipt or product")
    }

    private func saleRow(_ sale: SaleSummary) -> some View {
        HStack(spacing: 14) {
            Image(systemName: sale.paymentMethod.symbol)
                .font(.title3)
                .foregroundStyle(ZayFlowTheme.brand)
                .frame(width: 48, height: 48)
                .background(ZayFlowTheme.mintSurface, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(sale.receiptNumber)
                    .font(.subheadline.weight(.semibold).monospaced())
                    .lineLimit(1)
                Text("\(sale.itemCount) items  |  \(sale.paymentMethod.title)  |  \(sale.occurredAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(sale.grandTotal.displayString)
                    .font(.headline.monospacedDigit())
                Text("Completed")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ZayFlowTheme.brand)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 17))
        .overlay { RoundedRectangle(cornerRadius: 17).stroke(Color.primary.opacity(0.05)) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("activity-sale-row")
    }

    private func filter(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 13)
            .frame(minHeight: 38)
            .background(selected ? ZayFlowTheme.brand : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            .foregroundStyle(selected ? .white : .primary)
    }
}
