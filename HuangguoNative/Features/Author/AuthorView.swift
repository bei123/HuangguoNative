import SwiftUI

struct AuthorView: View {
	@Binding var path: NavigationPath
	let userId: Int

	@State private var profile: AuthorProfile?
	@State private var videos: [VideoCard] = []
	@State private var page = 1
	@State private var pages = 1
	@State private var loading = true
	@State private var errorText = ""
	@State private var following = false

	var body: some View {
		ScrollView {
			if let profile {
				VStack(alignment: .leading, spacing: 12) {
					HStack(spacing: 14) {
						HGCoverImage(url: profile.avatar, cornerRadius: 32)
							.frame(width: 64, height: 64)
						VStack(alignment: .leading, spacing: 4) {
							Text(profile.nickname)
								.font(.title3.weight(.bold))
								.foregroundStyle(HGTheme.textPrimary)
							Text(profile.sign.isEmpty ? profile.desc : profile.sign)
								.font(.caption)
								.foregroundStyle(HGTheme.textSecondary)
								.lineLimit(2)
						}
						Spacer()
						if SessionStore.shared.isLoggedIn {
							Button(following ? "已关注" : "关注") {
								Task { await toggleFollow() }
							}
							.font(.subheadline.weight(.semibold))
							.hgProminentButton()
							.tint(HGTheme.accent)
							.frame(minHeight: 44)
						}
					}
					.padding(.horizontal, 16)

					Text("作品 \(profile.videoCount) · 粉丝 \(profile.followers) · 获赞 \(profile.likeCount)")
						.font(.caption)
						.foregroundStyle(HGTheme.textMuted)
						.padding(.horizontal, 16)

					LazyVStack(spacing: 4) {
						ForEach(videos) { item in
							Button { path.append(AppRoute.detail(item.id)) } label: {
								VideoRowCard(item: item).padding(.horizontal, 16)
							}
							.buttonStyle(.plain)
						}
						InfiniteScrollFooter(hasMore: page <= pages, loading: loading) {
							Task { await loadVideos(reset: false) }
						}
					}
				}
			} else if loading {
				SkeletonRowList()
			} else {
				StateBox(text: errorText) { Task { await bootstrap() } }
			}
		}
		.background(HGTheme.bg.ignoresSafeArea())
		.navigationTitle("作者")
		.navigationBarTitleDisplayMode(.inline)
		.task { await bootstrap() }
	}

	private func bootstrap() async {
		loading = true
		errorText = ""
		do {
			profile = try await APIService.shared.fetchAuthor(id: userId)
			following = SessionStore.shared.user.followUserIds.contains(userId)
			await loadVideos(reset: true)
		} catch {
			errorText = error.localizedDescription
			loading = false
		}
	}

	private func loadVideos(reset: Bool) async {
		if !reset { guard !loading, page <= pages else { return } }
		if reset { page = 1; videos = [] }
		loading = true
		do {
			let r = try await APIService.shared.fetchAuthorVideos(userId: userId, page: page)
			if reset { videos = r.items } else { videos.mergeUnique(r.items) }
			pages = max(r.pages, 1)
			page = r.page + 1
		} catch {
			errorText = error.localizedDescription
		}
		loading = false
	}

	private func toggleFollow() async {
		do {
			following = try await APIService.shared.followUser(uid: userId, on: !following)
		} catch {
			errorText = error.localizedDescription
		}
	}
}
