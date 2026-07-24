import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        @Bindable var model = model
        Group {
            if !model.isAuthenticated {
                SignInView()
            } else if model.selectedMode == .organisationDashboard {
                NavigationStack { OrganisationDashboardView() }
            } else if horizontalSizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .sheet(isPresented: $model.isPOSShopPickerPresented) {
            POSShopPickerView()
        }
    }

    private var iPhoneLayout: some View {
        @Bindable var model = model
        return TabView(selection: $model.selectedSection) {
            ForEach(model.availableSections) { section in
                NavigationStack { view(for: section) }
                    .tabItem { Label(section.rawValue, systemImage: section.symbol) }
                    .tag(section)
            }
        }
        .safeAreaInset(edge: .top) { modeSwitcher }
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                modeSwitcher

                HStack(spacing: 12) {
                    Image("ZayFlowLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("ZayFlow")
                        .font(.headline)
                    Text(model.session?.shop.map { "\($0.name) · \($0.code)" } ?? "Choose POS shop")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                    Spacer()
                }
                .padding(18)

                List(model.availableSections, selection: selectionBinding) { section in
                    Label(section.rawValue, systemImage: section.symbol)
                        .font(.body.weight(.semibold))
                        .padding(.vertical, 8)
                        .tag(section)
                }
                .listStyle(.sidebar)

                SyncStatusView(compact: false)
                    .padding(16)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 280)
        } detail: {
            NavigationStack { selectedView }
        }
    }

    private var selectionBinding: Binding<AppModel.Section?> {
        Binding(
            get: { model.selectedSection },
            set: { if let value = $0 { model.selectedSection = value } }
        )
    }

    @ViewBuilder
    private var selectedView: some View {
        switch model.selectedSection {
        case .sell: SellView()
        case .stock: StockView()
        case .activity: ActivityView()
        case .reports: ReportsView()
        case .more: MoreView()
        }
    }

    @ViewBuilder
    private func view(for section: AppModel.Section) -> some View {
        switch section {
        case .sell: SellView()
        case .stock: StockView()
        case .activity: ActivityView()
        case .reports: ReportsView()
        case .more: MoreView()
        }
    }

    private var modeSwitcher: some View {
        HStack(spacing: 10) {
            Picker("Mode", selection: modeBinding) {
                Text("POS").tag(LoginMode.pos)
                if model.canUseOrganisationDashboard {
                    Text("Organisation").tag(LoginMode.organisationDashboard)
                }
            }
            .pickerStyle(.segmented)
            if model.selectedMode == .pos, let shop = model.session?.shop {
                Text(shop.code)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(ZayFlowTheme.brand.opacity(0.12), in: Capsule())
                    .foregroundStyle(ZayFlowTheme.brand)
            }
            if model.selectedMode == .pos, (model.session?.permittedShops.count ?? 0) > 1 {
                Button("Change Shop") { model.isPOSShopPickerPresented = true }
                    .font(.caption.weight(.semibold))
            }
            Button("Sign Out") { model.signOut() }
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private var modeBinding: Binding<LoginMode> {
        Binding(
            get: { model.selectedMode },
            set: { model.switchMode($0) }
        )
    }
}

private struct POSShopPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let error = model.lastError {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Section("Choose a shop for POS") {
                    ForEach(model.session?.permittedShops ?? []) { shop in
                        Button {
                            model.switchToPOS(shop: shop)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "building.2.fill")
                                    .foregroundStyle(ZayFlowTheme.brand)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(shop.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(shop.code)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.session?.shop?.id == shop.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(ZayFlowTheme.brand)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Open POS")
            .toolbar {
                Button("Cancel") {
                    model.isPOSShopPickerPresented = false
                    dismiss()
                }
            }
        }
    }
}

struct SyncStatusView: View {
    let compact: Bool

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(ZayFlowTheme.brand.opacity(0.14))
                Image(systemName: "checkmark.icloud.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ZayFlowTheme.brand)
            }
            .frame(width: compact ? 28 : 34, height: compact ? 28 : 34)

            if !compact {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ready offline")
                        .font(.caption.weight(.semibold))
                    Text("Demo data is on this device")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ready for offline use")
    }
}
