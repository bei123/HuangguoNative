import SwiftUI

/// 自定义控件上的官方 Liquid Glass（`glassEffect` / `GlassEffectContainer`）。
/// CI（Xcode 16）通过 `-D HG_NO_LIQUID_GLASS` 走回退样式，本地新 Xcode 仍用 Liquid Glass。
/// 文档：https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
enum HGGlass {
	/// 首页快捷入口等：同容器内可互融
	@ViewBuilder
	static func toolbarCluster<Content: View>(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) -> some View {
		#if HG_NO_LIQUID_GLASS
		HStack(spacing: spacing) { content() }
		#else
		GlassEffectContainer(spacing: spacing) {
			content()
		}
		#endif
	}
}

extension View {
	/// 规则玻璃 + 可交互（按钮/快捷项）
	@ViewBuilder
	func hgGlassInteractive(tint: Color? = HGTheme.accent) -> some View {
		#if HG_NO_LIQUID_GLASS
		self
			.background((tint ?? HGTheme.accent).opacity(0.18), in: Capsule())
		#else
		if let tint {
			self.glassEffect(.regular.tint(tint).interactive())
		} else {
			self.glassEffect(.regular.interactive())
		}
		#endif
	}

	/// 圆角矩形玻璃（搜索条、卡片条）
	@ViewBuilder
	func hgGlassRect(cornerRadius: CGFloat = 16) -> some View {
		#if HG_NO_LIQUID_GLASS
		self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
		#else
		self.glassEffect(in: .rect(cornerRadius: cornerRadius))
		#endif
	}

	/// 默认胶囊玻璃
	@ViewBuilder
	func hgGlassCapsule() -> some View {
		#if HG_NO_LIQUID_GLASS
		self.background(.ultraThinMaterial, in: Capsule())
		#else
		self.glassEffect()
		#endif
	}

	/// Prominent 按钮：有 Liquid Glass 用 glassProminent，否则 borderedProminent
	@ViewBuilder
	func hgProminentButton() -> some View {
		#if HG_NO_LIQUID_GLASS
		self.buttonStyle(.borderedProminent)
		#else
		self.buttonStyle(.glassProminent)
		#endif
	}
}
