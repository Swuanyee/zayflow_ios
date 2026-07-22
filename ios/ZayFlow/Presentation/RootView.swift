import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            iPadLayout
        } else {
            iPhoneLayout
        }
    }

    private var iPhoneLayout: some View {
        @Bindable var model = model
        return TabView(selection: $model.selectedSection) {
            NavigationStack { SellView() }
                .tabItem { Label("Sell", systemImage: "cart.fill") }
                .tag(AppModel.Section.sell)
            NavigationStack { StockView() }
                .tabItem { Label("Stock", systemImage: "shippingbox.fill") }
                .tag(AppModel.Section.stock)
            NavigationStack { ActivityView() }
                .tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }
                .tag(AppModel.Section.activity)
            NavigationStack { ReportsView() }
                .tabItem { Label("Reports", systemImage: "chart.bar.fill") }
                .tag(AppModel.Section.reports)
            NavigationStack { MoreView() }
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .tag(AppModel.Section.more)
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image("ZayFlowLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ZayFlow")
                            .font(.headline)
                        Text("Demo Store")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(18)

                List(AppModel.Section.allCases, selection: selectionBinding) { section in
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
