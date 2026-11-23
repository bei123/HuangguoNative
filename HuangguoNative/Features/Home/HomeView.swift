import SwiftUI

struct HomeView: View {
	@Binding var path: NavigationPath
	@State private var data: HomeData?
	@State private var loading = true
	@State private var errorText = ""

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 0) {
				if let data {
					homeContent(data)
				} else if !errorText.isEmpty {
					StateBox(text: errorText) { Task { await reload(showSkeleton: true) } }
				} else if loading {
					SkeletonHomeBlocks()
				}
			}
			.padding(.bottom, 24)
		}
		.background(HGTheme.bg.ignoresSafeArea())
		.navigationTitle("黄果")
		.navigationBarTitleDisplayMode(.large)
		.task {
			// 从详情返回会再次触发 .task，已有数据则不重拉
			guard data == nil else { return }
			await reload(showSkeleton: true)
		}
		.refreshable { await reload(showSkeleton: false) }
	}

	@ViewBuilder
	private func homeContent(_ data: HomeData) -> some View {
		// 少量自定义玻璃控件：放进 GlassEffectContainer，便于互融（Landmarks / Applying Liquid Glass）
		HGGlass.toolbarCluster(spacing: 14) {
			HStack(spacing: 12) {
				quick("flame.fill", "热播榜") { path.append(AppRoute.rank) }
				quick("rectangle.stack.fill", "专题") { path.append(AppRoute.topics) }
				quick("clock.fill", "更新") { path.append(AppRoute.latest) }
			}
			.padding(.horizontal, 16)
		}

		if !data.banners.isEmpty {
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 12) {
					ForEach(data.banners) { b in
						Button { path.append(AppRoute.detail(b.videoId)) } label: {
							ZStack(alignment: .bottomLeading) {
								HGCoverImage(url: b.image, cornerRadius: 14)
									.frame(width: 280, height: 150)
								LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
									.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
								VStack(alignment: .leading, spacing: 2) {
									Text(b.title.isEmpty ? "精选推荐" : b.title)
										.font(.subheadline.weight(.semibold))
										.foregroundStyle(.white)
										.lineLimit(1)
									if b.score > 0 {
										Text(String(format: "%.1f 分", b.score))
											.font(.caption)
											.foregroundStyle(HGTheme.accent)
									}
								}
								.padding(12)
							}
						}
						.buttonStyle(.plain)
					}
				}
				.padding(.horizontal, 16)
			}
			.padding(.top, 16)
		}

		if !data.featured.isEmpty {
			SectionHeader(title: "精选")
			horizontalCards(data.featured)
		}
		if !data.latest.isEmpty {
			SectionHeader(title: "最近更新", actionTitle: "更多") { path.append(AppRoute.latest) }
			horizontalCards(data.latest)
		}
		ForEach(data.cateRec) { cate in
			SectionHeader(title: cate.cateName)
			horizontalCards(cate.videos)
		}
		if !data.topicRec.isEmpty {
			SectionHeader(title: "精选专题", actionTitle: "更多") { path.append(AppRoute.topics) }
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 12) {
					ForEach(data.topicRec) { t in
						Button { path.append(AppRoute.topicDetail(t.slug)) } label: {
							VStack(alignment: .leading, spacing: 6) {
								HGCoverImage(url: t.cover, cornerRadius: 12)
									.frame(width: 160, height: 100)
								Text(t.title)
									.font(.caption.weight(.semibold))
									.foregroundStyle(HGTheme.textPrimary)
									.lineLimit(2)
									.frame(width: 160, alignment: .leading)
							}
						}
						.buttonStyle(.plain)
					}
				}
				.padding(.horizontal, 16)
			}
		}
	}

	private func horizontalCards(_ items: [VideoCard]) -> some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(alignment: .top, spacing: 12) {
				ForEach(items) { item in
					Button { path.append(AppRoute.detail(item.id)) } label: {
						VideoPosterCard(item: item)
					}
					.buttonStyle(.plain)
				}
			}
			.padding(.horizontal, 16)
		}
	}

	private func quick(_ system: String, _ label: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			HStack(spacing: 8) {
				Image(systemName: system)
					.font(.subheadline.weight(.semibold))
				Text(label)
					.font(.subheadline.weight(.semibold))
			}
			.foregroundStyle(HGTheme.textPrimary)
			.frame(maxWidth: .infinity, minHeight: 44)
			.padding(.vertical, 10)
		}
		.buttonStyle(.plain)
		.hgGlassInteractive(tint: HGTheme.accent.opacity(0.55))
	}

	private func reload(showSkeleton: Bool) async {
		if showSkeleton { loading = true }
		errorText = ""
		do {
			data = try await APIService.shared.fetchHome()
		} catch {
			// 已有内容时保留旧数据，只在首屏失败时展示错误
			if data == nil {
				errorText = error.localizedDescription
			}
		}
		loading = false
	}
}
