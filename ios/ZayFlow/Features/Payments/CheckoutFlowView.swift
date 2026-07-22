import SwiftUI
import ZayFlowCore

struct CheckoutFlowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var paymentMethod: PaymentMethod = .cash
    @State private var amountText: String
    @State private var completedSale: CompletedSale?
    @State private var errorMessage: String?
    @State private var isCompleting = false

    init(total: Money? = nil) {
        let initial = total?.minorUnits ?? 0
        _amountText = State(initialValue: String(initial / Money.scale))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let completedSale {
                    ReceiptView(sale: completedSale) {
                        model.isCartPresented = false
                        dismiss()
                    }
                } else {
                    paymentView
                }
            }
            .navigationTitle(completedSale == nil ? "Payment" : "Sale complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if completedSale == nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                            .disabled(isCompleting)
                    }
                }
            }
        }
        .onAppear {
            if amountText == "0" {
                amountText = String(model.cartTotal.minorUnits / Money.scale)
            }
        }
        .alert("Could not complete sale", isPresented: errorPresentation) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please review the payment and try again.")
        }
    }

    private var paymentView: some View {
        ScrollView {
            VStack(spacing: 20) {
                amountDueCard
                paymentMethods

                if paymentMethod == .cash {
                    cashEntry
                } else {
                    qrPayment
                }

                completeButton
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var amountDueCard: some View {
        SurfaceCard {
            VStack(spacing: 8) {
                Text("Amount due")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(model.cartTotal.displayString)
                    .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(ZayFlowTheme.brandDark)
                    .minimumScaleFactor(0.7)
                Text("\(model.cartCount) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var paymentMethods: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Payment method")
                .font(.headline)
            HStack(spacing: 12) {
                ForEach(PaymentMethod.allCases) { method in
                    Button {
                        paymentMethod = method
                        if method == .qr {
                            amountText = String(model.cartTotal.minorUnits / Money.scale)
                        }
                    } label: {
                        VStack(spacing: 9) {
                            Image(systemName: method.symbol)
                                .font(.title2)
                            Text(method.title)
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .background(
                            paymentMethod == method ? ZayFlowTheme.mintSurface : Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .stroke(paymentMethod == method ? ZayFlowTheme.brand : Color.primary.opacity(0.06), lineWidth: 2)
                        }
                        .foregroundStyle(paymentMethod == method ? ZayFlowTheme.brandDark : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var cashEntry: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cash received")
                .font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("0", text: $amountText)
                    .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                Text("Ks")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08)) }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(quickCashAmounts, id: \.self) { amount in
                        Button {
                            amountText = String(amount)
                        } label: {
                            Text(Money.mmk(amount).displayString)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .padding(.horizontal, 14)
                                .frame(minHeight: 42)
                                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Label("Change", systemImage: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(change.displayString)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(change.minorUnits >= 0 ? ZayFlowTheme.brandDark : ZayFlowTheme.danger)
            }
            .padding(.top, 4)
        }
    }

    private var qrPayment: some View {
        SurfaceCard {
            HStack(spacing: 15) {
                Image(systemName: "qrcode")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.indigo)
                    .frame(width: 62, height: 62)
                    .background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Confirm QR payment")
                        .font(.headline)
                    Text("Verify the payment on the merchant device before completing the sale.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var completeButton: some View {
        Button(action: completeSale) {
            HStack {
                if isCompleting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(isCompleting ? "Saving sale" : "Complete sale")
                Spacer()
                Text(model.cartTotal.displayString)
            }
            .font(.headline)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(ZayFlowTheme.brand, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(isCompleting || !paymentIsValid)
        .opacity(paymentIsValid ? 1 : 0.5)
    }

    private var enteredAmount: Money {
        let cleaned = amountText.filter(\.isNumber)
        return Money.mmk(Int64(cleaned) ?? 0)
    }

    private var change: Money {
        (try? enteredAmount.subtracting(model.cartTotal)) ?? .mmk(0)
    }

    private var paymentIsValid: Bool {
        paymentMethod == .qr || enteredAmount.minorUnits >= model.cartTotal.minorUnits
    }

    private var quickCashAmounts: [Int64] {
        let total = model.cartTotal.minorUnits / Money.scale
        func roundUp(_ value: Int64, to increment: Int64) -> Int64 {
            ((value + increment - 1) / increment) * increment
        }
        return Array(Set([total, roundUp(total, to: 1_000), roundUp(total, to: 5_000), roundUp(total, to: 10_000)]))
            .sorted()
    }

    private var errorPresentation: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func completeSale() {
        isCompleting = true
        defer { isCompleting = false }
        do {
            let tendered = paymentMethod == .qr ? model.cartTotal : enteredAmount
            completedSale = try model.completeSale(paymentMethod: paymentMethod, amountTendered: tendered)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

private struct ReceiptView: View {
    let sale: CompletedSale
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    Circle().fill(ZayFlowTheme.mintSurface)
                    Image(systemName: "checkmark")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(ZayFlowTheme.brand)
                }
                .frame(width: 92, height: 92)
                .padding(.top, 14)

                VStack(spacing: 5) {
                    Text("Sale completed")
                        .font(.title.weight(.bold))
                    Text(sale.receiptNumber)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                SurfaceCard {
                    VStack(spacing: 13) {
                        receiptRow("Total", sale.grandTotal.displayString, prominent: true)
                        Divider()
                        receiptRow(sale.paymentMethod.title, sale.amountTendered.displayString)
                        if sale.change.minorUnits > 0 {
                            receiptRow("Change", sale.change.displayString)
                        }
                        receiptRow("Items", "\(sale.lines.reduce(0) { $0 + Int($1.quantity.microUnits / Quantity.scale) })")
                    }
                }

                VStack(spacing: 9) {
                    ForEach(sale.lines) { line in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(line.productName)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(line.quantity.decimalString) x \(line.unitPrice.displayString)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(line.lineTotal.displayString)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                        .padding(14)
                        .background(.background, in: RoundedRectangle(cornerRadius: 14))
                    }
                }

                HStack(spacing: 12) {
                    Button {} label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.bordered)

                    Button(action: done) {
                        Text("Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("receipt-done")
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func receiptRow(_ title: String, _ value: String, prominent: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(prominent ? .headline : .subheadline)
                .foregroundStyle(prominent ? .primary : .secondary)
            Spacer()
            Text(value)
                .font(prominent ? .title3.weight(.bold).monospacedDigit() : .subheadline.weight(.semibold).monospacedDigit())
        }
    }
}
