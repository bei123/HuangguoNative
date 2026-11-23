import SwiftUI

struct CategoryView: View {
	@Binding var path: NavigationPath
	@State private var categories: [CategoryItem] = []
	@State private var selected: CategoryItem?
	@State private var items: [VideoCard] = []
	@State private var page = 1
	@State private var pages = 1
	@State private var hasMore = true
	@State private var loading = true
	@State private var errorText = ""
	@State private var loadToken = 0
	private let pageSize = 20

	var body: some View {
		ScrollView {
			LazyVStack(spacing: 0) {
				categoryBar

				if !errorText.isEmpty && items.isEmpty {
					StateBox(text: errorText) { Task { await bootstrap(force: true) } }
				} else if loading && items.isEmpty {
					SkeletonPosterGrid()
				} else if items.isEmpty {
					Text("该分类暂无内容")
						.font(.subheadline)
						.foregroundStyle(HGTheme.textMuted)
						.frame(maxWidth: .infinity, minHeight: 160)
				} else {
					LazyVGrid(
						columns: [
							GridItem(.flexible(), spacing: 10, alignment: .top),
							GridItem(.flexible(), spacing: 10, alignment: .top),
							GridItem(.flexible(), spacing: 10, alignment: .top)
						],
						spacing: 14
					) {
						ForEach(items) { item in
							Button { path.append(AppRoute.detail(item.id)) } label: {
								VideoPosterCard(item: item, width: nil)
									.frame(maxWidth: .infinity, alignment: .top)
							}
							.buttonStyle(.plain)
						}
					}
					.padding(.horizontal, 16)

					InfiniteScrollFooter(hasMore: hasMore, loading: loading) {
						Task { await loadVideos(reset: false) }
					}
				}
			}
			.padding(.bottom, 24)
		}
		.background(HGTheme.bg)
		.navigationTitle("发现")
		.navigationBarTitleDisplayMode(.large)
		.toolbarBackground(.automatic, for: .navigationBar)
		.refreshable { await bootstrap(force: true) }
		.task { await bootstrap(force: false) }
		.onAppear {
			if items.isEmpty, !loading {
				Task { await bootstrap(force: false) }
			}
		}
	}

	@ViewBuilder
	private var categoryBar: some View {
		if !categories.isEmpty {
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 8) {
					ForEach(categories) { c in
						Button {
							guard selected?.route != c.route else { return }
							selected = c
							Task { await loadVideos(reset: true, category: c) }
						} label: {
							Text(c.name)
								.font(.subheadline.weight(.semibold))
								.foregroundStyle(selected?.route == c.route ? .black : HGTheme.textPrimary)
								.padding(.horizontal, 14)
								.padding(.vertical, 8)
								.background(
									Capsule().fill(selected?.route == c.route ? HGTheme.accent : HGTheme.surface)
								)
						}
						.buttonStyle(.plain)
						.frame(minHeight: 44)
					}
				}
				.padding(.horizontal, 16)
			}
			.padding(.top, 4)
			.padding(.bottom, 10)
		}
	}

	private func bootstrap(force: Bool) async {
		if !force, !items.isEmpty, !categories.isEmpty { return }
		loading = true
		if force { errorText = "" }
		do {
			let list = try await APIService.shared.fetchCategories(forceRefresh: force)
				.filter { !APIService.isRetiredCategory($0) }
			guard !Task.isCancelled else { return }
			categories = list
			if list.isEmpty {
				errorText = "暂无可用分类"
				loading = false
				hasMore = false
				return
			}
			let next: CategoryItem
			if let selected, list.contains(where: { $0.route == selected.route }) {
				next = selected
			} else {
				next = list[0]
				selected = next
			}
			await loadVideos(reset: true, category: next)
		} catch is CancellationError {
			// 切 Tab 取消时保持现状
		} catch {
			if items.isEmpty {
				errorText = error.localizedDescription
			}
			loading = false
		}
	}

	private func loadVideos(reset: Bool, category: CategoryItem? = nil) async {
		guard let cat = category ?? selected else {
			loading = false
			return
		}
		if !reset {
			guard !loading, hasMore else { return }
		}

		loadToken += 1
		let token = loadToken
		let route = cat.route

		if reset {
			page = 1
			pages = 1
			hasMore = true
			items = []
			errorText = ""
		}
		loading = true
		defer {
			if token == loadToken {
				loading = false
			}
		}

		do {
			let result = try await APIService.shared.fetchCategoryVideos(
				route: route,
				page: page,
				size: pageSize
			)
			guard token == loadToken, !Task.isCancelled else { return }

			let before = items.count
			if reset {
				items = result.items
			} else {
				items.mergeUnique(result.items)
			}
			let added = items.count - before
			let current = max(result.page, 1)
			pages = max(result.pages, 1)
			page = current + 1
			if result.items.isEmpty || (!reset && added == 0) {
				hasMore = false
			} else if pages > 1 {
				hasMore = current < pages
			} else {
				hasMore = result.items.count >= pageSize
			}
			errorText = ""
		} catch is CancellationError {
			return
		} catch {
			guard token == loadToken else { return }
			if items.isEmpty {
				errorText = error.localizedDescription
			}
			if !reset { hasMore = true }
		}
	}
}
