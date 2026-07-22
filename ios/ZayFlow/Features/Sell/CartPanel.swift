import SwiftUI

struct CartPanel: View {
    @Environment(AppModel.self) private var model
    @State private var isCheckoutPresented = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Current cart")
                        .font(.title3.weight(.bold))
                    Text(model.cartLines.isEmpty ? "Add products to begin" : "\(model.cartCount) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !model.cartLines.isEmpty {
                    Button("Clear", role: .destructive) { model.clearCart() }
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(20)

            Divider()

            if model.cartLines.isEmpty {
                ContentUnavailableView {
                    Label("Cart is ready", systemImage: "cart.badge.plus")
                } description: {
                    Text("Tap a product or scan a barcode to add it here.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.cartLines) { line in
                            cartLine(line)
                            Divider().padding(.leading, 68)
                        }
                    }
                    .padding(.horizontal, 18)
                }

                Divider()
                totals
            }
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $isCheckoutPresented) {
            CheckoutFlowView()
                .environment(model)
                .interactiveDismissDisabled(false)
        }
    }

    private func cartLine(_ line: CartDisplayLine) -> some View {
        HStack(spacing: 12) {
            ProductArtwork(product: line.product)
                .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(line.product.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(line.product.unitPrice.displayString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Text(line.total.displayString)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                HStack(spacing: 4) {
                    quantityButton("minus", action: { model.decrement(line) })
                    Text(line.quantity.decimalString)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .frame(minWidth: 28)
                    quantityButton("plus", action: { model.increment(line) })
                }
            }
        }
        .padding(.vertical, 13)
    }

    private func quantityButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .frame(width: 30, height: 30)
                .background(Color(uiColor: .secondarySystemBackground), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var totals: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Subtotal")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.cartTotal.displayString)
                    .monospacedDigit()
            }
            HStack {
                Text("Total")
                    .font(.title3.weight(.bold))
                Spacer()
                Text(model.cartTotal.displayString)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(ZayFlowTheme.brandDark)
            }
            Button {
                isCheckoutPresented = true
            } label: {
                HStack {
                    Text("Charge")
                    Spacer()
                    Text(model.cartTotal.displayString)
                }
                .font(.headline)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(ZayFlowTheme.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens payment options")
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemBackground))
    }
}
