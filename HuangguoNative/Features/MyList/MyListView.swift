import SwiftUI

struct MyListView: View {
	@Binding var path: NavigationPath
	let kind: MyListKind

	@State private var history: [HistoryItem] = []
	@State private var collects: [CollectItem] = []
	@State private var follows: [FollowUser] = []
	@State private var page = 1
	@State private var pages = 1
	@State private var loading = true
	@State private var errorText = ""

	var body: some View {
		ScrollView {
			if loading && isEmpty {
				SkeletonRowList()
			} else if !errorText.isEmpty && isEmpty {
				StateBox(text: errorText) { Task { await load(reset: true) } }
			} else if isEmpty {
				StateBox(text: "暂无内容")
			} else {
				LazyVStack(spacing: 8) {
					switch kind {
					case .history:
						ForEach(history) { item in
							Button { path.append(AppRoute.detail(item.videoId)) } label: {
								row(cover: item.cover, title: item.title, sub: "看到第\(item.lastEp)集 · \(item.categoryName)")
							}.buttonStyle(.plain)
						}
					case .collects, .likes:
						ForEach(collects) { item in
							Button { path.append(AppRoute.detail(item.videoId)) } label: {
								row(cover: item.cover, title: item.title, sub: item.categoryName)
							}.buttonStyle(.plain)
						}
					case .follows:
						ForEach(follows) { u in
							Button { path.append(AppRoute.author(u.id)) } label: {
								HStack(spacing: 12) {
									HGCoverImage(url: u.avatar, cornerRadius: 24)
										.frame(width: 48, height: 48)
									VStack(alignment: .leading, spacing: 4) {
										Text(u.nickname).foregroundStyle(HGTheme.textPrimary).font(.body.weight(.semibold))
										Text(u.sign).font(.caption).foregroundStyle(HGTheme.textSecondary).lineLimit(1)
									}
									Spacer()
								}
								.padding(.horizontal, 16)
							}.buttonStyle(.plain)
						}
					}
					InfiniteScrollFooter(hasMore: page <= pages, loading: loading) {
						Task { await load(reset: false) }
					}
				}
			}
		}
		.background(HGTheme.bg.ignoresSafeArea())
		.navigationTitle(kind.title)
		.navigationBarTitleDisplayMode(.inline)
		.task { await load(reset: true) }
	}

	private var isEmpty: Bool {
		switch kind {
		case .history: return history.isEmpty
		case .collects, .likes: return collects.isEmpty
		case .follows: return follows.isEmpty
		}
	}

	private func row(cover: String, title: String, sub: String) -> some View {
		HStack(spacing: 12) {
			HGCoverImage(url: cover, cornerRadius: 8).frame(width: 64, height: 86)
			VStack(alignment: .leading, spacing: 6) {
				Text(title).font(.body.weight(.semibold)).foregroundStyle(HGTheme.textPrimary).lineLimit(2)
				Text(sub).font(.caption).foregroundStyle(HGTheme.textSecondary)
			}
			Spacer(minLength: 0)
		}
		.padding(.horizontal, 16)
	}

	private func load(reset: Bool) async {
		if !reset { guard !loading, page <= pages else { return } }
		if reset { page = 1; history = []; collects = []; follows = []; errorText = "" }
		loading = true
		do {
			switch kind {
			case .history:
				let r = try await APIService.shared.fetchMyHistory(page: page)
				if reset { history = r.items } else { history.mergeUnique(r.items) }
				pages = max(r.pages, 1); page = r.page + 1
			case .collects:
				let r = try await APIService.shared.fetchMyCollects(page: page)
				if reset { collects = r.items } else { collects.mergeUnique(r.items) }
				pages = max(r.pages, 1); page = r.page + 1
			case .likes:
				let r = try await APIService.shared.fetchMyLikes(page: page)
				if reset { collects = r.items } else { collects.mergeUnique(r.items) }
				pages = max(r.pages, 1); page = r.page + 1
			case .follows:
				let r = try await APIService.shared.fetchMyFollows(page: page)
				if reset { follows = r.items } else { follows.mergeUnique(r.items) }
				pages = max(r.pages, 1); page = r.page + 1
			}
		} catch {
			errorText = error.localizedDescription
		}
		loading = false
	}
}
