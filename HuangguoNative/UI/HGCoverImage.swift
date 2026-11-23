import SwiftUI
import UIKit

/// CDN 封面：AES-128-CBC 解密后再显示（对齐文档第 4 节）
struct HGCoverImage: View {
	let url: String
	var cornerRadius: CGFloat = 10
	var contentMode: ContentMode = .fill

	@State private var image: UIImage?
	@State private var failed = false

	var body: some View {
		ZStack {
			RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
				.fill(contentMode == .fit ? Color.black : HGTheme.surface)
			if let image {
				Image(uiImage: image)
					.resizable()
					.aspectRatio(contentMode: contentMode)
			} else if failed {
				Image(systemName: "photo")
					.foregroundStyle(HGTheme.textMuted)
			} else {
				ProgressView()
					.tint(HGTheme.accent)
					.scaleEffect(0.8)
			}
		}
		.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
		.task(id: url) { await load() }
	}

	private func load() async {
		image = nil
		failed = false
		if let ui = await ImageCache.shared.loadDecrypted(url: url) {
			image = ui
		} else {
			failed = true
		}
	}
}

/// 图文详情用：按真实宽高比排布。
/// - 横图 / 方图：铺满内容宽，限制最大高度，完整显示不裁切
/// - 竖图：同样完整显示，但限制最大高度，避免一条图占满整屏
struct HGAdaptiveCoverImage: View {
	let url: String
	var cornerRadius: CGFloat = 12
	/// 竖图高度上限（不读 UIScreen.main，避免 iOS 26 弃用警告）
	var portraitMaxHeight: CGFloat = 560
	var landscapeMaxHeight: CGFloat = 280

	@State private var image: UIImage?
	@State private var failed = false

	/// width / height
	private var aspect: CGFloat {
		guard let size = image?.size, size.height > 0 else { return 16.0 / 9.0 }
		return size.width / size.height
	}

	private var isPortrait: Bool { aspect < 0.95 }

	private var heightCap: CGFloat {
		isPortrait ? portraitMaxHeight : landscapeMaxHeight
	}

	var body: some View {
		ZStack {
			RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
				.fill(HGTheme.surface)
			if let image {
				Image(uiImage: image)
					.resizable()
					.aspectRatio(aspect, contentMode: .fit)
			} else if failed {
				Image(systemName: "photo")
					.foregroundStyle(HGTheme.textMuted)
			} else {
				ProgressView()
					.tint(HGTheme.accent)
					.scaleEffect(0.8)
			}
		}
		.aspectRatio(failed && image == nil ? 16.0 / 9.0 : aspect, contentMode: .fit)
		.frame(maxWidth: .infinity)
		.frame(maxHeight: image == nil ? 168 : heightCap)
		.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
		.animation(.easeOut(duration: 0.2), value: aspect)
		.task(id: url) { await load() }
		.accessibilityHidden(image == nil && !failed)
	}

	private func load() async {
		image = nil
		failed = false
		if let ui = await ImageCache.shared.loadDecrypted(url: url) {
			image = ui
		} else {
			failed = true
		}
	}
}

enum ImageDecrypt {
	static func decrypt(_ raw: Data) throws -> Data {
		try DxCrypto.decryptImageData(raw)
	}
}

final class ImageCache {
	static let shared = ImageCache()
	private let cache = NSCache<NSString, UIImage>()

	func image(for key: String) -> UIImage? {
		cache.object(forKey: key as NSString)
	}

	func set(_ image: UIImage, for key: String) {
		cache.setObject(image, forKey: key as NSString)
	}

	func loadDecrypted(url: String) async -> UIImage? {
		guard !url.isEmpty, let u = URL(string: url) else { return nil }
		if let cached = image(for: url) { return cached }
		do {
			var req = URLRequest(url: u, timeoutInterval: 25)
			req.setValue(EndpointRouter.referer, forHTTPHeaderField: "Referer")
			req.setValue("HuangguoNative/1.0", forHTTPHeaderField: "User-Agent")
			let (data, resp) = try await URLSession.shared.data(for: req)
			let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
			guard (200..<300).contains(code) else { return nil }
			let plain = try ImageDecrypt.decrypt(data)
			guard let ui = UIImage(data: plain) else { return nil }
			set(ui, for: url)
			return ui
		} catch {
			return nil
		}
	}
}
