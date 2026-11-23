import SwiftUI
import UIKit

enum HGTheme {
	/// 主背景：深色保留品牌夜色，浅色用系统分层背景
	static let bg = Color(uiColor: UIColor { tc in
		if tc.userInterfaceStyle == .dark {
			return UIColor(red: 0.071, green: 0.078, blue: 0.102, alpha: 1) // #12141a
		}
		return .systemGroupedBackground
	})

	static let surface = Color(uiColor: UIColor { tc in
		if tc.userInterfaceStyle == .dark {
			return UIColor(red: 0.102, green: 0.114, blue: 0.141, alpha: 1) // #1a1d24
		}
		return .secondarySystemGroupedBackground
	})

	/// 单一强调色（香槟金），深浅都可用
	static let accent = Color(red: 0.910, green: 0.761, blue: 0.478)

	static let textPrimary = Color.primary
	static let textSecondary = Color.secondary
	static let textMuted = Color(uiColor: .tertiaryLabel)

	static let glassFill = Color(uiColor: UIColor { tc in
		tc.userInterfaceStyle == .dark
			? UIColor.white.withAlphaComponent(0.08)
			: UIColor.black.withAlphaComponent(0.04)
	})

	static let glassStroke = Color(uiColor: UIColor { tc in
		tc.userInterfaceStyle == .dark
			? UIColor.white.withAlphaComponent(0.14)
			: UIColor.black.withAlphaComponent(0.08)
	})

	static let danger = Color.red
}
