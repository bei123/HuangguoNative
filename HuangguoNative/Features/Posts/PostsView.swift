import SwiftUI
import UIKit

struct PostsView: View {
	@Binding var path: NavigationPath
	@State private var categories: [CategoryItem] = []
	@State private var selected: CategoryItem?
	@State private var items: [PostCard] = []
	@State private var page = 1
	@State private var pages = 1
	@State private var loading = true
	@State private var errorText = ""

	var body: some View {
		VStack(spacing: 0) {
			categoryBar
			ScrollView {
				if loading && items.isEmpty {
					SkeletonRowList(count: 8)
				} else if !errorText.isEmpty && items.isEmpty {
					StateBox(text: errorText) { Task { await bootstrap() } }
				} else if items.isEmpty {
					StateBox(text: "暂无图文")
				} else {
					LazyVStack(spacing: 0) {
						ForEach(Array(items.enumerated()), id: \.element.id) { index, post in
							Button {
								path.append(AppRoute.postDetail(post.id))
							} label: {
								PostListRow(post: post)
									.padding(.horizontal, 16)
									.padding(.vertical, 14)
							}
							.buttonStyle(.plain)
							.accessibilityLabel(post.title)

							if index < items.count - 1 {
								Divider()
									.background(HGTheme.glassStroke)
									.padding(.leading, 16 + 112 + 14)
							}
						}
						InfiniteScrollFooter(hasMore: page <= pages, loading: loading) {
							Task { await load(reset: false) }
						}
					}
				}
			}
		}
		.background(HGTheme.bg.ignoresSafeArea())
		.navigationTitle("图文")
		.navigationBarTitleDisplayMode(.inline)
		.task { await bootstrap() }
	}

	@ViewBuilder
	private var categoryBar: some View {
		if !categories.isEmpty {
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 8) {
					ForEach(categories) { c in
						Button {
							guard selected?.id != c.id else { return }
							selected = c
							Task { await load(reset: true) }
						} label: {
							Text(c.name)
								.font(.subheadline.weight(.semibold))
								.foregroundStyle(selected?.id == c.id ? .black : HGTheme.textPrimary)
								.padding(.horizontal, 14)
								.padding(.vertical, 8)
								.background(Capsule().fill(selected?.id == c.id ? HGTheme.accent : HGTheme.surface))
						}
						.buttonStyle(.plain)
						.frame(minHeight: 44)
					}
				}
				.padding(.horizontal, 16)
			}
			.padding(.top, 4)
			.padding(.bottom, 8)
		}
	}

	private func bootstrap() async {
		do {
			categories = try await APIService.shared.fetchPostCategories()
			selected = categories.first
			await load(reset: true)
		} catch {
			errorText = error.localizedDescription
			loading = false
		}
	}

	private func load(reset: Bool) async {
		guard let selected else { return }
		if !reset { guard !loading, page <= pages else { return } }
		if reset { page = 1; items = []; errorText = "" }
		loading = true
		do {
			let r = try await APIService.shared.fetchPosts(route: selected.route, page: page)
			if reset { items = r.items } else { items.mergeUnique(r.items) }
			pages = max(r.pages, 1)
			page = r.page + 1
		} catch {
			errorText = error.localizedDescription
		}
		loading = false
	}
}

private struct PostListRow: View {
	let post: PostCard

	var body: some View {
		HStack(alignment: .top, spacing: 14) {
			HGCoverImage(url: post.cover, cornerRadius: 10)
				.frame(width: 112, height: 84)
				.clipped()

			VStack(alignment: .leading, spacing: 8) {
				Text(post.title)
					.font(.body.weight(.semibold))
					.foregroundStyle(HGTheme.textPrimary)
					.lineLimit(2)
					.multilineTextAlignment(.leading)
					.frame(maxWidth: .infinity, minHeight: UIFont.preferredFont(forTextStyle: .body).lineHeight * 2, alignment: .topLeading)

				if !post.desc.isEmpty {
					Text(post.desc)
						.font(.caption)
						.foregroundStyle(HGTheme.textSecondary)
						.lineLimit(2)
				}

				if !post.tags.isEmpty {
					HStack(spacing: 6) {
						ForEach(Array(post.tags.prefix(3)), id: \.self) { tag in
							Text(tag)
								.font(.caption2.weight(.medium))
								.foregroundStyle(HGTheme.accent)
								.padding(.horizontal, 8)
								.padding(.vertical, 4)
								.background(HGTheme.accent.opacity(0.14), in: Capsule())
								.lineLimit(1)
						}
						Spacer(minLength: 0)
					}
				}

				HStack(spacing: 10) {
					Label(formatHot(post.hot), systemImage: "flame.fill")
					if !post.createdAt.isEmpty {
						Text(shortDate(post.createdAt))
					}
					Spacer(minLength: 0)
					Image(systemName: "chevron.right")
						.font(.caption.weight(.semibold))
						.foregroundStyle(HGTheme.textMuted)
				}
				.font(.caption2)
				.foregroundStyle(HGTheme.textMuted)
				.symbolRenderingMode(.hierarchical)
			}
		}
		.contentShape(Rectangle())
	}

	private func formatHot(_ n: Int) -> String {
		if n >= 100_000_000 { return String(format: "%.1f亿", Double(n) / 100_000_000) }
		if n >= 10_000 { return String(format: "%.1f万", Double(n) / 10_000) }
		return "\(n)"
	}

	private func shortDate(_ raw: String) -> String {
		let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		guard s.count >= 10 else { return s }
		return String(s.prefix(10))
	}
}
