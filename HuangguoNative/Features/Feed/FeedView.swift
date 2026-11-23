import SwiftUI

struct FeedView: View {
	@Binding var path: NavigationPath
	@State private var kind = "recommend"
	@State private var items: [VideoCard] = []
	@State private var page = 1
	@State private var pages = 1
	@State private var loading = true
	@State private var errorText = ""

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 8) {
				chip("推荐", "recommend")
				chip("今日", "today")
				Spacer()
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 8)

			ScrollView {
				if loading && items.isEmpty {
					SkeletonRowList()
				} else if !errorText.isEmpty && items.isEmpty {
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
		}
		.background(HGTheme.bg.ignoresSafeArea())
		.navigationTitle("推荐流")
		.navigationBarTitleDisplayMode(.inline)
		.task { await load(reset: true) }
	}

	private func chip(_ title: String, _ value: String) -> some View {
		Button(title) {
			kind = value
			Task { await load(reset: true) }
		}
		.font(.subheadline.weight(.semibold))
		.foregroundStyle(kind == value ? .black : HGTheme.textPrimary)
		.padding(.horizontal, 14)
		.padding(.vertical, 8)
		.background(Capsule().fill(kind == value ? HGTheme.accent : HGTheme.surface))
		.frame(minHeight: 44)
	}

	private func load(reset: Bool) async {
		if !reset { guard !loading, page <= pages else { return } }
		if reset { page = 1; items = []; errorText = "" }
		loading = true
		do {
			let r = try await APIService.shared.fetchFeed(kind: kind, page: page)
			if reset { items = r.items } else { items.mergeUnique(r.items) }
			pages = max(r.pages, 1)
			page = r.page + 1
		} catch {
			errorText = error.localizedDescription
		}
		loading = false
	}
}

struct MoreView: View {
	@Binding var path: NavigationPath
	@State private var sorts: [SortItem] = []

	var body: some View {
		List {
			Section("内容") {
				Button("原创作品") { path.append(AppRoute.original) }
				Button("图文") { path.append(AppRoute.posts) }
				Button("推荐流") { path.append(AppRoute.feed) }
				Button("专题") { path.append(AppRoute.topics) }
			}
			Section("排序") {
				ForEach(sorts) { s in
					Button(s.name) { path.append(AppRoute.sort(s.route)) }
				}
			}
		}
		.listStyle(.insetGrouped)
		.scrollContentBackground(.hidden)
		.background(HGTheme.bg.ignoresSafeArea())
		.navigationTitle("更多")
		.navigationBarTitleDisplayMode(.inline)
		.task {
			sorts = (try? await APIService.shared.fetchSorts()) ?? []
		}
	}
}

struct OriginalListView: View {
	@Binding var path: NavigationPath
	@State private var items: [VideoCard] = []
	@State private var page = 1
	@State private var pages = 1
	@State private var loading = true
	@State private var errorText = ""

	var body: some View {
		videoList
			.navigationTitle("原创")
			.task { await load(reset: true) }
	}

	private var videoList: some View {
		ScrollView {
			if loading && items.isEmpty {
				SkeletonRowList()
			} else if !errorText.isEmpty && items.isEmpty {
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
		.navigationBarTitleDisplayMode(.inline)
	}

	private func load(reset: Bool) async {
		if !reset { guard !loading, page <= pages else { return } }
		if reset { page = 1; items = []; errorText = "" }
		loading = true
		do {
			let r = try await APIService.shared.fetchOriginal(page: page)
			if reset { items = r.items } else { items.mergeUnique(r.items) }
			pages = max(r.pages, 1)
			page = r.page + 1
		} catch {
			errorText = error.localizedDescription
		}
		loading = false
	}
}

struct SortListView: View {
	@Binding var path: NavigationPath
	let route: String
	@State private var items: [VideoCard] = []
	@State private var page = 1
	@State private var pages = 1
	@State private var loading = true
	@State private var errorText = ""

	var body: some View {
		ScrollView {
			if loading && items.isEmpty {
				SkeletonRowList()
			} else if !errorText.isEmpty && items.isEmpty {
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
		.navigationTitle(route)
		.navigationBarTitleDisplayMode(.inline)
		.task { await load(reset: true) }
	}

	private func load(reset: Bool) async {
		if !reset { guard !loading, page <= pages else { return } }
		if reset { page = 1; items = []; errorText = "" }
		loading = true
		do {
			let r = try await APIService.shared.fetchSortedVideos(route: route, page: page)
			if reset { items = r.items } else { items.mergeUnique(r.items) }
			pages = max(r.pages, 1)
			page = r.page + 1
		} catch {
			errorText = error.localizedDescription
		}
		loading = false
	}
}
