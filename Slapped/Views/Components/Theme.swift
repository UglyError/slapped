import SwiftUI
import UIKit

extension Color {
    static let brand = Color(red: 1.0, green: 0.757, blue: 0.0)          // #FFC100
    static let onBrand = Color(red: 0.08, green: 0.08, blue: 0.08)
    static let bg = Color(uiColor: .dynamic(light: 0xF4F3EF, dark: 0x0F0F10))
    static let card = Color(uiColor: .dynamic(light: 0xFFFFFF, dark: 0x1B1B1D))
    static let cardRaised = Color(uiColor: .dynamic(light: 0xEEEDE8, dark: 0x262629))
    static let hairline = Color(uiColor: .dynamic(light: 0xE3E1DA, dark: 0x2E2E31))
}

extension UIColor {
    static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }

    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

struct BrandButtonStyle: ButtonStyle {
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(filled ? Color.onBrand : Color.primary)
            .background(filled ? Color.brand : Color.cardRaised, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.hairline, lineWidth: 0.5))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }

    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .sticker(let sticker): StickerDetailView(sticker: sticker)
            case .profile(let id): ProfileView(userID: id)
            case .stickerID(let id): StickerLoaderView(id: id)
            case .trades: TradesView()
            case .activity: ActivityView()
            case .settings: SettingsView()
            case .blockedUsers: BlockedUsersView()
            case .badges(let id): BadgesView(userID: id)
            case .series(let name): SeriesView(series: name)
            }
        }
    }
}

extension Date {
    var timeAgo: String {
        let seconds = -timeIntervalSinceNow
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        case ..<604_800: return "\(Int(seconds / 86_400))d"
        default: return formatted(.dateTime.month(.abbreviated).day())
        }
    }
}
