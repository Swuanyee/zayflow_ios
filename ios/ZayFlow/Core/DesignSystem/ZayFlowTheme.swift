import SwiftUI
import UIKit

enum ZayFlowTheme {
    static let brand = Color(red: 0.05, green: 0.55, blue: 0.47)
    static let brandDark = Color(red: 0.02, green: 0.28, blue: 0.27)
    static let mintSurface = Color(red: 0.91, green: 0.97, blue: 0.95)
    static let warmSurface = Color(red: 0.98, green: 0.96, blue: 0.91)
    static let warning = Color(red: 0.91, green: 0.48, blue: 0.12)
    static let danger = Color(red: 0.78, green: 0.20, blue: 0.22)

    static func categoryColor(_ category: String) -> Color {
        switch category {
        case "Rice and Staples", "Cooking Essentials": .orange
        case "Instant Food", "Snacks and Confectionery": .pink
        case "Coffee and Beverages": .brown
        case "Dairy and Eggs": .blue
        case "Fresh Produce and Meat": .red
        case "Household Cleaning": .indigo
        case "Personal Care": .purple
        case "Baby Products": .teal
        default: brand
        }
    }

    static func categorySymbol(_ category: String) -> String {
        switch category {
        case "Rice and Staples": "takeoutbag.and.cup.and.straw.fill"
        case "Cooking Essentials": "frying.pan.fill"
        case "Instant Food": "cup.and.saucer.fill"
        case "Coffee and Beverages": "mug.fill"
        case "Dairy and Eggs": "waterbottle.fill"
        case "Fresh Produce and Meat": "leaf.fill"
        case "Snacks and Confectionery": "birthday.cake.fill"
        case "Household Cleaning": "bubbles.and.sparkles.fill"
        case "Personal Care": "sparkles"
        case "Baby Products": "figure.and.child.holdinghands"
        default: "shippingbox.fill"
        }
    }
}

struct ProductArtwork: View {
    let product: StoreProduct

    private var assetName: String { "Product-\(product.sku)" }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ZayFlowTheme.categoryColor(product.category).opacity(0.10))

            if let image = UIImage(named: assetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(5)
            } else {
                Image(systemName: ZayFlowTheme.categorySymbol(product.category))
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(ZayFlowTheme.categoryColor(product.category))
            }
        }
        .accessibilityHidden(true)
    }
}

struct SurfaceCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 14, y: 6)
    }
}
