import SwiftUI

typealias ViewState<Value> = State<Value>

enum NEK {
  static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(
      UIColor { traits in
        let v = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(
          red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
          blue: CGFloat(v & 255) / 255, alpha: 1)
      })
  }
  static let background = adaptive(0xFAF7F1, 0x211D19), surface = adaptive(0xFFFDF9, 0x2D2722),
    ink = adaptive(0x302A24, 0xF5EDE1), muted = adaptive(0x756B5E, 0xC3B5A4),
    brand = adaptive(0x74563D, 0xD7B995), soft = adaptive(0xEEE7DC, 0x3A3028),
    line = adaptive(0xE5DDD1, 0x4B4035), onBrand = adaptive(0xFFFDF9, 0x241C16),
    deep = adaptive(0x392C22, 0xE6D1B5), onDeep = adaptive(0xFFF5E7, 0x302319),
    good = adaptive(0x416347, 0xB9D4AC)
}
struct NEKCard<Content: View>: View {
  let content: Content
  init(@ViewBuilder content: () -> Content) { self.content = content() }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) { content }.frame(
      maxWidth: .infinity, alignment: .leading
    ).padding(18).background(NEK.surface).cornerRadius(20).overlay(
      RoundedRectangle(cornerRadius: 20).stroke(NEK.line, lineWidth: 0.7))
  }
}
struct NEKButton: View {
  let title: String
  var symbol: String? = nil
  var secondary = false
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 9) {
        if let symbol = symbol { Image(systemName: symbol) }
        Text(title).font(.system(size: 15, weight: .medium))
      }.frame(maxWidth: .infinity).frame(minHeight: 48).padding(.horizontal, 12).background(
        secondary ? NEK.surface : NEK.brand
      ).foregroundColor(secondary ? NEK.brand : NEK.onBrand).cornerRadius(13).overlay(
        RoundedRectangle(cornerRadius: 13).stroke(secondary ? NEK.line : Color.clear, lineWidth: 1)
      )
    }.buttonStyle(.plain)
  }
}
