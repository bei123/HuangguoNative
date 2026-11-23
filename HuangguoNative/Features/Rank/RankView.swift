import SwiftUI

struct RankView: View {
	@Binding var path: NavigationPath
	@State private var type = "hot"
	@State private var items: [RankItem] = []
	@State private var loading = true
	@State private var errorText = ""

	private let types = [("hot", "热播"), ("recommend", "推荐"), ("potential", "潜力")]

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 8) {
				ForEach(types, id: \.0) { t in
					Button(t.1) {
						type = t.0
						Task { await load() }
					}
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(type == t.0 ? .black : HGTheme.textPrimary)
					.padding(.horizontal, 14)
					.padding(.vertical, 8)
					.background(Capsule().fill(type == t.0 ? HGTheme.accent : HGTheme.surface))
					.frame(minHeight: 44)
				}
				Spacer()
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 10)

			ScrollView {
				if loading && items.isEmpty {
					SkeletonRowList()
				} else if !errorText.isEmpty {
					StateBox(text: errorText) { Task { await load() } }
				} else {
					LazyVStack(spacing: 10) {
						ForEach(items) { item in
							Button { path.append(AppRoute.detail(item.videoId)) } label: {
								HStack(spacing: 12) {
									Text("#\(item.rank)")
										.font(.headline.weight(.bold))
										.foregroundStyle(item.rank <= 3 ? HGTheme.accent : HGTheme.textSecondary)
										.frame(width: 36)
									HGCoverImage(url: item.cover, cornerRadius: 8)
										.frame(width: 64, height: 86)
									VStack(alignment: .leading, spacing: 4) {
										Text(item.title)
											.font(.body.weight(.semibold))
											.foregroundStyle(HGTheme.textPrimary)
											.lineLimit(2)
										Text("\(item.cateName) · \(item.episodeCount)集 · \(String(format: "%.1f", item.score))")
											.font(.caption)
											.foregroundStyle(HGTheme.textSecondary)
										Text("\(item.metricLabel) \(item.metricValue)")
											.font(.caption2)
											.foregroundStyle(HGTheme.accent)
									}
									Spacer(minLength: 0)
								}
								.padding(.horizontal, 16)
							}
							.buttonStyle(.plain)
						}
					}
					.padding(.bottom, 40)
				}
			}
		}
		.background(HGTheme.bg.ignoresSafeArea())
		.navigationTitle("榜单")
		.navigationBarTitleDisplayMode(.inline)
		.toolbarBackground(HGTheme.bg, for: .navigationBar)
		.toolbarColorScheme(.dark, for: .navigationBar)
		.task { await load() }
	}

	private func load() async {
		loading = true
		errorText = ""
		do {
			items = try await APIService.shared.fetchRanks(type: type)
		} catch {
			errorText = error.localizedDescription
		}
		loading = false
	}
}

struct LatestListView: View {
	@Binding var path: NavigationPath
	@State private var items: [VideoCard] = []
	@State private var page = 1
	@State private var pages = 1
	@State private var loading = true
	@State private var errorText = ""

	var body: some View {
		ScrollView {
			if loading && items.isEmpty {
				SkeletonRowList()
			} else if !errorText.isEmpty {
				StateBox(text: errorText) { Task { await load(reset: true) } }
			} else {
				LazyVStack(spacing: 4) {
					ForEach(items) { item in
						Button { path.append(AppRoute.detail(item.id)) } label: {
							VideoRowCard(item: item).padding(.horizontal, 16)
						}
						.buttonStyle(.plain)
					}
					InfiniteScrollFooter(hasMore: page <= pages, loading: loading) {
						Task { await load(reset: false) }
					}
				}
			}
		}
		.background(HGTheme.bg.ignoresSafeArea())
		.navigationTitle("最近更新")
		.navigationBarTitleDisplayMode(.inline)
		.toolbarBackground(HGTheme.bg, for: .navigationBar)
		.toolbarColorScheme(.dark, for: .navigationBar)
		.task { await load(reset: true) }
	}

	private func load(reset: Bool) async {
		if !reset {
			guard !loading, page <= pages else { return }
		}
		if reset { page = 1; items = []; errorText = "" }
		loading = true
		do {
			let result = try await APIService.shared.fetchLatest(page: page)
			if reset { items = result.items } else { items.mergeUnique(result.items) }
			pages = max(result.pages, 1)
			page = result.page + 1
		} catch {
			errorText = error.localizedDescription
		}
		loading = false
	}
}
