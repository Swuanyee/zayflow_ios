import SwiftUI

struct MoreView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("localCoordinatorBaseURL") private var localCoordinatorBaseURL = "http://localhost:3000"
    @AppStorage("localCoordinatorSharedSecret") private var localCoordinatorSharedSecret = ""
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
                navigationRow("Sync status", "\(model.pendingSyncCount) pending", "checkmark.icloud.fill", model.pendingSyncCount == 0 ? ZayFlowTheme.brand : ZayFlowTheme.warning)
                navigationRow("Barcode scanner", "Not tested", "barcode.viewfinder", .indigo)
                navigationRow("Receipt printer", "Not connected", "printer.fill", .gray)
            }

            Section("Local Wi-Fi coordinator") {
                TextField("Coordinator URL", text: $localCoordinatorBaseURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Shared secret (optional)", text: $localCoordinatorSharedSecret)
                Button {
                    checkLocalCoordinator()
                } label: {
                    Label(model.isCheckingCoordinator ? "Checking..." : "Check coordinator", systemImage: "wifi.router.fill")
                }
                .disabled(model.isCheckingCoordinator || coordinatorHealthURL == nil)
                Button {
                    pushToLocalCoordinator()
                } label: {
                    HStack {
                        Label(model.isSyncing ? "Pushing..." : "Push pending events", systemImage: "arrow.up.arrow.down.circle.fill")
                        Spacer()
                        Text("\(model.pendingSyncCount)")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(model.isSyncing || coordinatorPushURL == nil || model.pendingSyncCount == 0)
                if let message = model.coordinatorHealthMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.contains("unreachable") ? .red : .secondary)
                }
                if let error = model.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Use a local dashboard/coordinator URL on the same Wi-Fi, for example http://192.168.1.20:3000.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .onAppear { model.refreshPendingSyncCount() }
    }

    private var coordinatorPushURL: URL? {
        coordinatorEndpoint(path: "/api/sync/v1/push")
    }

    private var coordinatorHealthURL: URL? {
        coordinatorEndpoint(path: "/api/sync/v1/health")
    }

    private func coordinatorEndpoint(path: String) -> URL? {
        let trimmed = localCoordinatorBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard var components = URLComponents(string: normalized), components.host != nil else { return nil }
        components.path = path
        components.query = nil
        return components.url
    }

    private func pushToLocalCoordinator() {
        guard let url = coordinatorPushURL else { return }
        Task {
            await model.syncPendingOutbox(to: url, sharedSecret: localCoordinatorSharedSecret)
        }
    }

    private func checkLocalCoordinator() {
        guard let url = coordinatorHealthURL else { return }
        Task {
            await model.checkLocalCoordinatorHealth(at: url, sharedSecret: localCoordinatorSharedSecret)
        }
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
