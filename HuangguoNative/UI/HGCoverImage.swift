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
		guard !url.isEmpty, let u = URL(string: url) else {
			failed = true
			return
		}
		if let cached = ImageCache.shared.image(for: url) {
			image = cached
			return
		}
		do {
			var req = URLRequest(url: u, timeoutInterval: 25)
			req.setValue("https://huangguoai.com/", forHTTPHeaderField: "Referer")
			req.setValue("HuangguoNative/1.0", forHTTPHeaderField: "User-Agent")
			let (data, resp) = try await URLSession.shared.data(for: req)
			let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
			guard (200..<300).contains(code) else {
				failed = true
				return
			}
			let plain = try ImageDecrypt.decrypt(data)
			guard let ui = UIImage(data: plain) else {
				failed = true
				return
			}
			ImageCache.shared.set(ui, for: url)
			image = ui
		} catch {
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
}
