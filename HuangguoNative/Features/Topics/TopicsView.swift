import SwiftUI
import UIKit

struct TopicsView: View {
	@Binding var path: NavigationPath
	@State private var items: [TopicLite] = []
	@State private var page = 1
	@State private var pages = 1
	@State private var loading = true
	@State private var errorText = ""

	var body: some View {
		ScrollView {
			if loading && items.isEmpty {
				SkeletonRowList(count: 6)
			} else if !errorText.isEmpty && items.isEmpty {
				StateBox(text: errorText) { Task { await load(reset: true) } }
			} else if items.isEmpty {
				StateBox(text: "暂无专题")
			} else {
				LazyVStack(spacing: 0) {
					if let first = items.first {
						Button {
							path.append(AppRoute.topicDetail(first.slug))
						} label: {
							TopicFeatureCard(topic: first)
								.padding(.horizontal, 16)
								.padding(.top, 12)
								.padding(.bottom, 8)
						}
						.buttonStyle(.plain)
						.accessibilityLabel(first.title)
					}

					ForEach(Array(items.dropFirst().enumerated()), id: \.element.id) { index, topic in
						Button {
							path.append(AppRoute.topicDetail(topic.slug))
						} label: {
							TopicListRow(topic: topic)
								.padding(.horizontal, 16)
								.padding(.vertical, 14)
						}
						.buttonStyle(.plain)
						.accessibilityLabel(topic.title)

						if index < items.count - 2 {
							Divider()
								.background(HGTheme.glassStroke)
								.padding(.leading, 16 + 128 + 14)
						}
					}

					InfiniteScrollFooter(hasMore: page <= pages, loading: loading) {
						Task { await load(reset: false) }
					}
				}
				.padding(.bottom, 20)
			}
		}
		.background(HGTheme.bg.ignoresSafeArea())
		.navigationTitle("专题")
		.navigationBarTitleDisplayMode(.inline)
		.toolbarBackground(HGTheme.bg, for: .navigationBar)
		.task { await load(reset: true) }
	}

	private func load(reset: Bool) async {
		if !reset {
			guard !loading, page <= pages else { return }
		}
		if reset { page = 1; items = []; errorText = "" }
		loading = true
		do {
			let result = try await APIService.shared.fetchTopics(page: page)
			if reset { items = result.items } else { items.mergeUnique(result.items) }
			pages = max(result.pages, 1)
			page = result.page + 1
		} catch {
			errorText = error.localizedDescription
		}
		loading = false
	}
}

/// 列表首条大封面专题卡
private struct TopicFeatureCard: View {
	let topic: TopicLite

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			ZStack(alignment: .bottomLeading) {
				HGCoverImage(url: topic.cover, cornerRadius: 0)
					.frame(maxWidth: .infinity)
					.frame(height: 180)
					.clipped()

				LinearGradient(
					colors: [.clear, .black.opacity(0.72)],
					startPoint: .center,
					endPoint: .bottom
				)

				VStack(alignment: .leading, spacing: 6) {
					Text("精选专题")
						.font(.caption.weight(.semibold))
						.foregroundStyle(HGTheme.accent)
					Text(topic.title)
						.font(.title3.weight(.bold))
						.foregroundStyle(.white)
						.lineLimit(2)
					HStack(spacing: 8) {
						Label("\(topic.videoCount) 部", systemImage: "rectangle.stack.fill")
						Spacer(minLength: 0)
						Image(systemName: "chevron.right")
							.font(.caption.weight(.semibold))
					}
					.font(.caption)
					.foregroundStyle(.white.opacity(0.85))
				}
				.padding(14)
			}
			.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

			if !topic.intro.isEmpty {
				Text(topic.intro)
					.font(.subheadline)
					.foregroundStyle(HGTheme.textSecondary)
					.lineLimit(2)
					.padding(.top, 10)
			}
		}
		.contentShape(Rectangle())
	}
}

private struct TopicListRow: View {
	let topic: TopicLite

	var body: some View {
		HStack(alignment: .top, spacing: 14) {
			HGCoverImage(url: topic.cover, cornerRadius: 12)
				.frame(width: 128, height: 86)
				.clipped()

			VStack(alignment: .leading, spacing: 8) {
				Text(topic.title)
					.font(.body.weight(.semibold))
					.foregroundStyle(HGTheme.textPrimary)
					.lineLimit(2)
					.multilineTextAlignment(.leading)
					.frame(
						maxWidth: .infinity,
						minHeight: UIFont.preferredFont(forTextStyle: .body).lineHeight * 2,
						alignment: .topLeading
					)

				if !topic.intro.isEmpty {
					Text(topic.intro)
						.font(.caption)
						.foregroundStyle(HGTheme.textSecondary)
						.lineLimit(2)
				}

				HStack(spacing: 8) {
					Text("\(topic.videoCount) 部作品")
						.font(.caption2.weight(.semibold))
						.foregroundStyle(.black)
						.padding(.horizontal, 8)
						.padding(.vertical, 4)
						.background(HGTheme.accent, in: Capsule())
					Spacer(minLength: 0)
					Image(systemName: "chevron.right")
						.font(.caption.weight(.semibold))
						.foregroundStyle(HGTheme.textMuted)
				}
			}
		}
		.contentShape(Rectangle())
	}
}
