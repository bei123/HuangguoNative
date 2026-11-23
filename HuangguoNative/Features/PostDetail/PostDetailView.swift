import SwiftUI

struct PostDetailView: View {
	@Binding var path: NavigationPath
	let postId: String

	@State private var detail: PostDetail?
	@State private var blocks: [PostContentBlock] = []
	@State private var loading = true
	@State private var errorText = ""
	@State private var lightbox: HGImageLightboxItem?

	var body: some View {
		ScrollView {
			if let detail {
				VStack(alignment: .leading, spacing: 0) {
					hero(detail)
					articleHeader(detail)
					Divider().background(HGTheme.glassStroke).padding(.horizontal, 16)
					articleBody
						.padding(.top, 18)
						.padding(.horizontal, 16)
						.padding(.bottom, 40)
				}
			} else if loading {
				SkeletonDetailInfo()
			} else {
				StateBox(text: errorText.isEmpty ? "加载失败" : errorText) {
					Task { await load() }
				}
			}
		}
		.background(HGTheme.bg.ignoresSafeArea())
		.navigationTitle(detail?.title.isEmpty == false ? "图文" : "图文详情")
		.navigationBarTitleDisplayMode(.inline)
		.fullScreenCover(item: $lightbox) { item in
			HGImageLightbox(urls: item.urls, startIndex: item.index)
		}
		.task { await load() }
	}

	private var galleryURLs: [String] {
		var urls: [String] = []
		if let cover = detail?.cover, !cover.isEmpty { urls.append(cover) }
		for block in blocks {
			if case .image(let url) = block.kind, !url.isEmpty, !urls.contains(url) {
				urls.append(url)
			}
		}
		return urls
	}

	private func openLightbox(url: String) {
		let urls = galleryURLs
		guard !urls.isEmpty else { return }
		let idx = urls.firstIndex(of: url) ?? 0
		lightbox = HGImageLightboxItem(urls: urls, index: idx)
	}

	private func hero(_ detail: PostDetail) -> some View {
		Group {
			if !detail.cover.isEmpty {
				Button {
					openLightbox(url: detail.cover)
				} label: {
					HGAdaptiveCoverImage(url: detail.cover, cornerRadius: 0, landscapeMaxHeight: 300)
						.overlay(alignment: .bottomTrailing) {
							Image(systemName: "arrow.up.left.and.arrow.down.right")
								.font(.caption.weight(.semibold))
								.foregroundStyle(.white)
								.padding(8)
								.background(.black.opacity(0.45), in: Circle())
								.padding(10)
						}
				}
				.buttonStyle(.plain)
				.accessibilityLabel("查看封面大图")
			}
		}
	}

	private func articleHeader(_ detail: PostDetail) -> some View {
		VStack(alignment: .leading, spacing: 14) {
			Text(detail.title)
				.font(.title2.weight(.bold))
				.foregroundStyle(HGTheme.textPrimary)
				.fixedSize(horizontal: false, vertical: true)

			if !detail.desc.isEmpty {
				Text(detail.desc)
					.font(.subheadline)
					.foregroundStyle(HGTheme.textSecondary)
					.fixedSize(horizontal: false, vertical: true)
			}

			HStack(spacing: 16) {
				meta(icon: "flame.fill", text: formatHot(detail.hot))
				meta(icon: "heart.fill", text: "\(detail.like)")
				meta(icon: "star.fill", text: "\(detail.collect)")
				Spacer(minLength: 0)
			}

			if detail.authorId > 0 || !detail.authorName.isEmpty {
				Button {
					if detail.authorId > 0 {
						path.append(AppRoute.author(detail.authorId))
					}
				} label: {
					HStack(spacing: 10) {
						ZStack {
							Circle().fill(HGTheme.surface)
							Image(systemName: "person.fill")
								.font(.caption.weight(.semibold))
								.foregroundStyle(HGTheme.accent)
						}
						.frame(width: 36, height: 36)
						VStack(alignment: .leading, spacing: 2) {
							Text(detail.authorName.isEmpty ? "作者" : detail.authorName)
								.font(.subheadline.weight(.semibold))
								.foregroundStyle(HGTheme.textPrimary)
							Text("查看作者主页")
								.font(.caption2)
								.foregroundStyle(HGTheme.textMuted)
						}
						Spacer(minLength: 0)
						Image(systemName: "chevron.right")
							.font(.caption.weight(.semibold))
							.foregroundStyle(HGTheme.textMuted)
					}
					.padding(12)
					.background(HGTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.disabled(detail.authorId <= 0)
				.frame(minHeight: 44)
			}

			if !detail.tags.isEmpty {
				FlowTagRow(tags: Array(detail.tags.prefix(8)))
			}
		}
		.padding(16)
	}

	private var articleBody: some View {
		LazyVStack(alignment: .leading, spacing: 16) {
			if blocks.isEmpty {
				Text("暂无正文")
					.font(.body)
					.foregroundStyle(HGTheme.textMuted)
			} else {
				ForEach(blocks) { block in
					switch block.kind {
					case .text(let text):
						Text(text)
							.font(.body)
							.foregroundStyle(HGTheme.textPrimary.opacity(0.9))
							.lineSpacing(6)
							.fixedSize(horizontal: false, vertical: true)
					case .image(let url):
						Button {
							openLightbox(url: url)
						} label: {
							HGAdaptiveCoverImage(url: url, cornerRadius: 12)
								.overlay(alignment: .bottomTrailing) {
									Image(systemName: "arrow.up.left.and.arrow.down.right")
										.font(.caption2.weight(.semibold))
										.foregroundStyle(.white)
										.padding(6)
										.background(.black.opacity(0.45), in: Circle())
										.padding(8)
								}
						}
						.buttonStyle(.plain)
						.accessibilityLabel("查看配图大图")
					}
				}
			}
		}
	}

	private func meta(icon: String, text: String) -> some View {
		Label(text, systemImage: icon)
			.font(.caption.weight(.medium))
			.foregroundStyle(HGTheme.textSecondary)
			.symbolRenderingMode(.hierarchical)
	}

	private func formatHot(_ n: Int) -> String {
		if n >= 100_000_000 { return String(format: "%.1f亿", Double(n) / 100_000_000) }
		if n >= 10_000 { return String(format: "%.1f万", Double(n) / 10_000) }
		return "\(n)"
	}

	private func load() async {
		loading = true
		errorText = ""
		do {
			let d = try await APIService.shared.fetchPostDetail(id: postId)
			detail = d
			blocks = PostHTML.parse(d.contentHTML)
		} catch {
			errorText = error.localizedDescription
		}
		loading = false
	}
}

// MARK: - Tags

private struct FlowTagRow: View {
	let tags: [String]

	var body: some View {
		FlexibleWrap(spacing: 8) {
			ForEach(tags, id: \.self) { tag in
				Text(tag)
					.font(.caption.weight(.medium))
					.foregroundStyle(HGTheme.accent)
					.padding(.horizontal, 10)
					.padding(.vertical, 6)
					.background(HGTheme.accent.opacity(0.14), in: Capsule())
			}
		}
	}
}

/// 简单换行流式布局（标签）
private struct FlexibleWrap<Content: View>: View {
	var spacing: CGFloat = 8
	@ViewBuilder var content: () -> Content

	var body: some View {
		_FlexibleWrapLayout(spacing: spacing) {
			content()
		}
	}
}

private struct _FlexibleWrapLayout: Layout {
	var spacing: CGFloat

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let maxWidth = proposal.width ?? .infinity
		var x: CGFloat = 0
		var y: CGFloat = 0
		var rowHeight: CGFloat = 0
		var height: CGFloat = 0
		for sub in subviews {
			let size = sub.sizeThatFits(.unspecified)
			if x + size.width > maxWidth, x > 0 {
				x = 0
				y += rowHeight + spacing
				rowHeight = 0
			}
			rowHeight = max(rowHeight, size.height)
			x += size.width + spacing
			height = y + rowHeight
		}
		return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: height)
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		var x = bounds.minX
		var y = bounds.minY
		var rowHeight: CGFloat = 0
		for sub in subviews {
			let size = sub.sizeThatFits(.unspecified)
			if x + size.width > bounds.maxX, x > bounds.minX {
				x = bounds.minX
				y += rowHeight + spacing
				rowHeight = 0
			}
			sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
			x += size.width + spacing
			rowHeight = max(rowHeight, size.height)
		}
	}
}

// MARK: - HTML → blocks

struct PostContentBlock: Identifiable {
	enum Kind {
		case text(String)
		case image(String)
	}
	let id: String
	let kind: Kind
}

enum PostHTML {
	static func parse(_ html: String) -> [PostContentBlock] {
		guard !html.isEmpty else { return [] }
		var blocks: [PostContentBlock] = []
		var remaining = html

		// 统一换行标签
		remaining = remaining
			.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
			.replacingOccurrences(of: "</p>", with: "</p>\n", options: .caseInsensitive)

		let tokenPattern = #"(?is)(<img\b[^>]*>)|(<p\b[^>]*>.*?</p>)|([^<]+)|(<[^>]+>)"#
		guard let regex = try? NSRegularExpression(pattern: tokenPattern) else {
			let plain = decodeEntities(stripTags(html)).trimmingCharacters(in: .whitespacesAndNewlines)
			return plain.isEmpty ? [] : [PostContentBlock(id: "t0", kind: .text(plain))]
		}

		let ns = remaining as NSString
		let matches = regex.matches(in: remaining, range: NSRange(location: 0, length: ns.length))
		var textBuf = ""
		var index = 0

		func flushText() {
			let t = decodeEntities(textBuf)
				.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
				.trimmingCharacters(in: .whitespacesAndNewlines)
			if !t.isEmpty {
				blocks.append(PostContentBlock(id: "t\(index)", kind: .text(t)))
				index += 1
			}
			textBuf = ""
		}

		for m in matches {
			let token = ns.substring(with: m.range)
			if token.lowercased().hasPrefix("<img") {
				flushText()
				if let url = imageURL(from: token) {
					blocks.append(PostContentBlock(id: "i\(index)", kind: .image(url)))
					index += 1
				}
			} else if token.lowercased().hasPrefix("<p") {
				flushText()
				let inner = stripTags(token)
				let plain = decodeEntities(inner).trimmingCharacters(in: .whitespacesAndNewlines)
				if !plain.isEmpty {
					blocks.append(PostContentBlock(id: "t\(index)", kind: .text(plain)))
					index += 1
				}
			} else if token.hasPrefix("<") {
				continue
			} else {
				textBuf += token
			}
		}
		flushText()
		return blocks
	}

	private static func imageURL(from tag: String) -> String? {
		// 优先 data-src（真实 CDN），其次 src（常为占位图）
		let patterns = [
			#"data-src\s*=\s*"([^"]+)""#,
			#"data-src\s*=\s*'([^']+)'"#,
			#"src\s*=\s*"([^"]+)""#,
			#"src\s*=\s*'([^']+)'"#
		]
		for p in patterns {
			if let r = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
			   let m = r.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
			   m.numberOfRanges > 1,
			   let range = Range(m.range(at: 1), in: tag) {
				var url = String(tag[range]).trimmingCharacters(in: .whitespacesAndNewlines)
				if url.contains("cover-placeholder") { continue }
				if url.hasPrefix("//") { url = "https:" + url }
				if url.hasPrefix("http") { return url }
			}
		}
		return nil
	}

	private static func stripTags(_ s: String) -> String {
		var out = s
		while let r = out.range(of: #"<[^>]+>"#, options: .regularExpression) {
			out.removeSubrange(r)
		}
		return out
	}

	private static func decodeEntities(_ s: String) -> String {
		s.replacingOccurrences(of: "&nbsp;", with: " ")
			.replacingOccurrences(of: "&amp;", with: "&")
			.replacingOccurrences(of: "&lt;", with: "<")
			.replacingOccurrences(of: "&gt;", with: ">")
			.replacingOccurrences(of: "&quot;", with: "\"")
			.replacingOccurrences(of: "&#39;", with: "'")
	}
}
