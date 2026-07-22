import SwiftUI
import VisionKit

struct SellView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isScannerPresented = false
    @State private var scannerMessage: String?

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 850 {
                HStack(spacing: 0) {
                    productBrowser
                        .frame(maxWidth: .infinity)
                    Divider()
                    CartPanel()
                        .frame(width: min(430, geometry.size.width * 0.38))
                        .background(Color(uiColor: .secondarySystemBackground))
                }
            } else {
                productBrowser
                    .safeAreaInset(edge: .bottom) { compactCartBar }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: cartPresentation) {
            NavigationStack {
                CartPanel()
                    .navigationTitle("Current cart")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { model.isCartPresented = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $isScannerPresented) {
            BarcodeScannerView { barcode in
                if model.addToCart(barcode: barcode) {
                    isScannerPresented = false
                } else {
                    scannerMessage = "No product uses barcode \(barcode)."
                    isScannerPresented = false
                }
            } onCancel: {
                isScannerPresented = false
            }
        }
        .alert("Barcode scanner", isPresented: scannerAlertPresentation) {
            Button("OK", role: .cancel) { scannerMessage = nil }
        } message: {
            Text(scannerMessage ?? "The scanner is unavailable.")
        }
    }

    private var productBrowser: some View {
        @Bindable var model = model
        return ScrollView {
            LazyVStack(spacing: 18, pinnedViews: []) {
                welcomeHeader

                HStack(spacing: 12) {
                    Label("Search products or scan", systemImage: "magnifyingglass")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                    TextField("Search products or scan", text: $model.searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                    if !model.searchText.isEmpty {
                        Button {
                            model.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                    Button(action: openScanner) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.title3.weight(.semibold))
                            .frame(width: 42, height: 42)
                            .background(ZayFlowTheme.brand, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open barcode scanner")
                }
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
                .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.08))
                }

                categoryStrip

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.selectedCategory == "All" ? "All products" : model.selectedCategory)
                            .font(.title3.weight(.bold))
                        Text("\(model.filteredProducts.count) items available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        ForEach(AppModel.ProductSort.allCases) { option in
                            Button {
                                model.productSort = option
                            } label: {
                                if model.productSort == option {
                                    Label(option.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(option.rawValue)
                                }
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                            .font(.subheadline.weight(.semibold))
                    }
                }

                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(model.filteredProducts) { product in
                        ProductCard(product: product) {
                            withAnimation(.snappy) { model.addToCart(product) }
                        }
                    }
                }

                if model.filteredProducts.isEmpty {
                    ContentUnavailableView.search(text: model.searchText)
                        .padding(.vertical, 60)
                }
            }
            .padding(20)
            .padding(.bottom, horizontalSizeClass == .compact ? 74 : 0)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var welcomeHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Good evening")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ZayFlowTheme.brand)
                    .textCase(.uppercase)
                Text("Ready to make a sale?")
                    .font(.title2.weight(.bold))
                Text("Tap an item or scan its barcode.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SyncStatusView(compact: true)
        }
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(model.categories, id: \.self) { category in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { model.selectedCategory = category }
                    } label: {
                        HStack(spacing: 7) {
                            if category != "All" {
                                Image(systemName: ZayFlowTheme.categorySymbol(category))
                            }
                            Text(category)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 42)
                        .background(
                            model.selectedCategory == category ? ZayFlowTheme.brand : Color(uiColor: .secondarySystemGroupedBackground),
                            in: Capsule()
                        )
                        .foregroundStyle(model.selectedCategory == category ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentMargins(.horizontal, 1, for: .scrollContent)
    }

    private var compactCartBar: some View {
        Button {
            model.isCartPresented = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13).fill(.white.opacity(0.18))
                    Image(systemName: "cart.fill")
                        .font(.headline)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.cartCount == 0 ? "Your cart is empty" : "\(model.cartCount) items")
                        .font(.subheadline.weight(.semibold))
                    Text(model.cartCount == 0 ? "Tap products to begin" : "View and edit cart")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Text(model.cartTotal.displayString)
                    .font(.headline.monospacedDigit())
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.bold))
            }
            .padding(10)
            .background(ZayFlowTheme.brandDark, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .shadow(color: ZayFlowTheme.brandDark.opacity(0.22), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 180 : 154, maximum: 240), spacing: 14)]
    }

    private var cartPresentation: Binding<Bool> {
        Binding(get: { model.isCartPresented }, set: { model.isCartPresented = $0 })
    }

    private var scannerAlertPresentation: Binding<Bool> {
        Binding(get: { scannerMessage != nil }, set: { if !$0 { scannerMessage = nil } })
    }

    private func openScanner() {
        guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else {
            scannerMessage = "Camera barcode scanning is not available on this device. You can still search by name, SKU, or barcode."
            return
        }
        isScannerPresented = true
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 8) {
                Image("ZayFlowLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text("Demo Store")
                    .font(.headline)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {} label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
            }
            .accessibilityLabel("Cashier profile")
        }
    }
}

private struct ProductCard: View {
    let product: StoreProduct
    let add: () -> Void

    var body: some View {
        Button(action: add) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    ProductArtwork(product: product)
                        .frame(height: 112)
                    stockBadge
                        .padding(9)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(product.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 38, alignment: .topLeading)
                    Text(product.category)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline) {
                        Text(product.unitPrice.displayString)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(ZayFlowTheme.brandDark)
                        Spacer(minLength: 4)
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(ZayFlowTheme.brand)
                    }
                }
            }
            .padding(11)
            .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.06))
            }
        }
        .buttonStyle(ProductPressStyle())
        .accessibilityLabel("\(product.name), \(product.unitPrice.displayString), \(product.stockQuantity.decimalString) in stock")
        .accessibilityHint("Adds one to the cart")
    }

    private var stockBadge: some View {
        let low = product.stockQuantity <= product.lowStockThreshold
        return Text(low ? "Low \(product.stockQuantity.decimalString)" : "\(product.stockQuantity.decimalString) left")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(low ? ZayFlowTheme.warning : ZayFlowTheme.brand, in: Capsule())
            .foregroundStyle(.white)
    }
}

private struct ProductPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: .black.opacity(configuration.isPressed ? 0.02 : 0.06), radius: 12, y: 5)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
