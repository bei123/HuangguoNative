import SwiftUI

/// 自定义控件上的官方 Liquid Glass（`glassEffect` / `GlassEffectContainer`）。
/// Tab 导航本身交给系统 `TabView`，见 `RootTabView`。
/// 文档：https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
enum HGGlass {
	/// 首页快捷入口等：同容器内可互融
	@ViewBuilder
	static func toolbarCluster<Content: View>(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) -> some View {
		GlassEffectContainer(spacing: spacing) {
			content()
		}
	}
}

extension View {
	/// 规则玻璃 + 可交互（按钮/快捷项）
	func hgGlassInteractive(tint: Color? = HGTheme.accent) -> some View {
		Group {
			if let tint {
				self.glassEffect(.regular.tint(tint).interactive())
			} else {
				self.glassEffect(.regular.interactive())
			}
		}
	}

	/// 圆角矩形玻璃（搜索条、卡片条）
	func hgGlassRect(cornerRadius: CGFloat = 16) -> some View {
		self.glassEffect(in: .rect(cornerRadius: cornerRadius))
	}

	/// 默认胶囊玻璃
	func hgGlassCapsule() -> some View {
		self.glassEffect()
	}
}
