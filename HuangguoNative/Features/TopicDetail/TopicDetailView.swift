import SwiftUI
import UIKit

struct TopicDetailView: View {
	@Binding var path: NavigationPath
	let slug: String

	@State private var detail: TopicDetail?
	@State private var videos: [VideoCard] = []
	@State private var page = 1
	@State private var pages = 1
	@State private var loading = true
	@State private var errorText = ""
	@State private var introExpanded = false
	@State private var lightbox: HGImageLightboxItem?

	var body: some View {
		ScrollView {
			if let detail {
				VStack(alignment: .leading, spacing: 0) {
					hero(detail.topic)
					header(detail.topic)
					Divider().background(HGTheme.glassStroke).padding(.horizontal, 16)

					SectionHeader(title: "收录作品")
					videoList

					if !detail.related.isEmpty {
						SectionHeader(title: "相关专题")
						relatedStrip(detail.related)
							.padding(.bottom, 8)
					}
				}
				.padding(.bottom, 28)
			} else if loading {
				SkeletonDetailInfo()
			} else {
				StateBox(text: errorText.isEmpty ? "加载失败" : errorText) {
					Task { await bootstrap() }
				}
			}
		}
		.background(HGTheme.bg.ignoresSafeArea())
		.navigationTitle(detail?.topic.title.isEmpty == false ? "专题" : "专题")
		.navigationBarTitleDisplayMode(.inline)
		.fullScreenCover(item: $lightbox) { item in
			HGImageLightbox(urls: item.urls, startIndex: item.index)
		}
		.task { await bootstrap() }
	}

	private func hero(_ topic: TopicLite) -> some View {
		Button {
			guard !topic.cover.isEmpty else { return }
			lightbox = HGImageLightboxItem(urls: [topic.cover], index: 0)
		} label: {
			ZStack(alignment: .bottomTrailing) {
				HGCoverImage(url: topic.cover, cornerRadius: 0)
					.frame(maxWidth: .infinity)
					.frame(height: 200)
					.clipped()
				Image(systemName: "arrow.up.left.and.arrow.down.right")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.white)
					.padding(8)
					.background(.black.opacity(0.45), in: Circle())
					.padding(12)
			}
		}
		.buttonStyle(.plain)
		.accessibilityLabel("查看专题封面")
		.disabled(topic.cover.isEmpty)
	}

	private func header(_ topic: TopicLite) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(topic.title)
				.font(.title2.weight(.bold))
				.foregroundStyle(HGTheme.textPrimary)
				.fixedSize(horizontal: false, vertical: true)

			HStack(spacing: 10) {
				Label("\(topic.videoCount) 部作品", systemImage: "rectangle.stack.fill")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.black)
					.padding(.horizontal, 10)
					.padding(.vertical, 6)
					.background(HGTheme.accent, in: Capsule())
				Spacer(minLength: 0)
			}

			if !topic.intro.isEmpty {
				Text(topic.intro)
					.font(.body)
					.foregroundStyle(HGTheme.textSecondary)
					.lineSpacing(4)
					.lineLimit(introExpanded ? nil : 4)
					.fixedSize(horizontal: false, vertical: true)

				Button(introExpanded ? "收起" : "展开全部") {
					withAnimation(.snappy) { introExpanded.toggle() }
				}
				.font(.caption.weight(.semibold))
				.foregroundStyle(HGTheme.accent)
				.frame(minHeight: 44, alignment: .leading)
				.contentShape(Rectangle())
			}
		}
		.padding(16)
	}

	private var videoList: some View {
		LazyVStack(spacing: 0) {
			if videos.isEmpty && loading {
				SkeletonRowList(count: 4)
			} else if videos.isEmpty {
				Text("暂无收录作品")
					.font(.subheadline)
					.foregroundStyle(HGTheme.textMuted)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 24)
			} else {
				ForEach(Array(videos.enumerated()), id: \.element.id) { index, item in
					Button {
						path.append(AppRoute.detail(item.id))
					} label: {
						VideoRowCard(item: item)
							.padding(.horizontal, 16)
							.padding(.vertical, 8)
					}
					.buttonStyle(.plain)

					if index < videos.count - 1 {
						Divider()
							.background(HGTheme.glassStroke)
							.padding(.leading, 16 + 84 + 12)
					}
				}
				InfiniteScrollFooter(hasMore: page <= pages, loading: loading) {
					Task { await loadMore() }
				}
			}
		}
	}

	private func relatedStrip(_ topics: [TopicLite]) -> some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(alignment: .top, spacing: 12) {
				ForEach(topics) { t in
					Button {
						path.append(AppRoute.topicDetail(t.slug))
					} label: {
						VStack(alignment: .leading, spacing: 8) {
							HGCoverImage(url: t.cover, cornerRadius: 12)
								.frame(width: 148, height: 98)
								.clipped()
							Text(t.title)
								.font(.caption.weight(.semibold))
								.foregroundStyle(HGTheme.textPrimary)
								.lineLimit(2)
								.frame(
									width: 148,
									height: UIFont.preferredFont(forTextStyle: .caption1).lineHeight * 2,
									alignment: .topLeading
								)
							Text("\(t.videoCount) 部")
								.font(.caption2)
								.foregroundStyle(HGTheme.textMuted)
						}
					}
					.buttonStyle(.plain)
					.accessibilityLabel(t.title)
				}
			}
			.padding(.horizontal, 16)
		}
	}

	private func bootstrap() async {
		loading = true
		errorText = ""
		do {
			let d = try await APIService.shared.fetchTopicDetail(slug: slug, page: 1)
			detail = d
			videos = d.videos.items.uniquedPreservingOrder()
			page = d.videos.page + 1
			pages = max(d.videos.pages, 1)
		} catch {
			errorText = error.localizedDescription
		}
		loading = false
	}

	private func loadMore() async {
		guard !loading, page <= pages else { return }
		loading = true
		do {
			let d = try await APIService.shared.fetchTopicDetail(slug: slug, page: page)
			videos.mergeUnique(d.videos.items)
			page = d.videos.page + 1
			pages = max(d.videos.pages, 1)
		} catch {
			errorText = error.localizedDescription
		}
		loading = false
	}
}
