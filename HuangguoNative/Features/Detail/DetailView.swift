import SwiftUI
import AVKit
import UIKit

struct DetailView: View {
	let videoId: String

	@State private var detail: VideoDetail?
	@State private var loading = true
	@State private var errorText = ""
	@State private var currentEp = 1
	@State private var playURL: URL?
	@State private var hevcURL: URL?
	@State private var useHEVC = false
	@State private var expiresAt = 0
	@State private var playTip = "准备播放…"
	@State private var playLoading = false
	@State private var player: AVPlayer?
	@State private var descExpanded = false
	@State private var liked = false
	@State private var collected = false
	@State private var myScore = 0
	@State private var showRate = false
	@State private var comments: [CommentItem] = []
	@State private var commentText = ""
	@State private var showComments = false
	@State private var related: [VideoCard] = []
	@State private var toast = ""
	@State private var acting = false
	@State private var needLogin = false
	@State private var toastTask: Task<Void, Never>?
	@State private var speedBoosting = false
	@State private var holdSpeed: Float = 2.0
	/// 用引用类型同步标记全屏，避免 @State 更新晚于 onDisappear 误杀播放器
	@State private var fullscreenGate = FullscreenGate()
	@State private var loadedVideoId: String?

	var body: some View {
		VStack(spacing: 0) {
			playerChrome
			ScrollView {
				if let detail {
					VStack(alignment: .leading, spacing: 0) {
						infoBlock(detail)
						Divider().background(HGTheme.glassStroke).padding(.horizontal, 16)
						actionRow
							.padding(.vertical, 12)
						if showRate {
							rateRow
								.padding(.bottom, 8)
						}
						episodeBlock(detail)
						if showComments {
							commentsBlock
						}
						if !related.isEmpty {
							SectionHeader(title: "相关推荐")
							relatedStrip
								.padding(.bottom, 8)
						}
					}
					.padding(.bottom, 36)
				} else if loading {
					SkeletonDetailInfo()
				} else if !errorText.isEmpty {
					StateBox(text: errorText) { Task { await load(force: true) } }
				}
			}
		}
		.background(HGTheme.bg.ignoresSafeArea())
		.overlay(alignment: .bottom) {
			if !toast.isEmpty {
				Text(toast)
					.font(.subheadline.weight(.medium))
					.foregroundStyle(HGTheme.textPrimary)
					.padding(.horizontal, 16)
					.padding(.vertical, 12)
					.background(HGTheme.surface.opacity(0.96), in: Capsule())
					.padding(.bottom, 28)
					.transition(.move(edge: .bottom).combined(with: .opacity))
					.accessibilityLabel(toast)
			}
		}
		.animation(.snappy, value: toast)
		.navigationTitle(detail?.title.isEmpty == false ? (detail?.title ?? "播放") : "播放")
		.navigationBarTitleDisplayMode(.inline)
		.toolbarBackground(.ultraThinMaterial, for: .navigationBar)
		.alert("需要登录", isPresented: $needLogin) {
			Button("知道了", role: .cancel) {}
		} message: {
			Text("点赞、收藏和评分需要先登录。请到「我的」页登录后再试。")
		}
		.task(id: videoId) { await load(force: false) }
		.onDisappear {
			// 系统全屏会拆掉内联播放器并触发 onDisappear：只暂停，绝不销毁，否则退出全屏进度归零
			guard !fullscreenGate.isFullscreen else { return }
			player?.pause()
			toastTask?.cancel()
			speedBoosting = false
		}
	}

	// MARK: - Player（全屏交给系统控件；自定义只做集数提示与长按倍速）

	private var playerChrome: some View {
		ZStack {
			Color.black
			if let player {
				HGPlayerContainer(
					player: player,
					holdSpeed: holdSpeed,
					onHoldSpeedChanged: { boosting in
						speedBoosting = boosting
					},
					onFullscreenChanged: { fullscreen in
						fullscreenGate.isFullscreen = fullscreen
					}
				)
			} else if let detail {
				HGCoverImage(url: detail.cover, cornerRadius: 0, contentMode: .fill)
					.overlay {
						LinearGradient(
							colors: [.clear, .black.opacity(0.55)],
							startPoint: .center,
							endPoint: .bottom
						)
					}
					.overlay {
						VStack(spacing: 10) {
							if playLoading {
								ProgressView().tint(HGTheme.accent)
							} else {
								Image(systemName: "play.circle.fill")
									.font(.largeTitle)
									.imageScale(.large)
									.symbolRenderingMode(.hierarchical)
									.foregroundStyle(.white)
							}
							Text(playTip)
								.font(.caption.weight(.medium))
								.foregroundStyle(.white.opacity(0.9))
								.padding(.horizontal, 12)
								.padding(.vertical, 6)
								.background(.black.opacity(0.4), in: Capsule())
						}
					}
			} else {
				ProgressView().tint(HGTheme.accent)
			}

			VStack {
				HStack(spacing: 8) {
					Spacer(minLength: 0)
					Text("第 \(currentEp) 集")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.white)
						.padding(.horizontal, 10)
						.padding(.vertical, 6)
						.background(.black.opacity(0.45), in: Capsule())

					if player != nil {
						Menu {
							ForEach([1.5, 2.0, 2.5, 3.0], id: \.self) { speed in
								Button {
									holdSpeed = Float(speed)
									flashToast("长按倍速：\(String(format: "%.1f", speed))x")
								} label: {
									HStack {
										Text("\(String(format: "%.1f", speed))x")
										if abs(Double(holdSpeed) - speed) < 0.01 {
											Image(systemName: "checkmark")
										}
									}
								}
							}
						} label: {
							Image(systemName: "gauge.with.dots.needle.67percent")
								.font(.body.weight(.semibold))
								.foregroundStyle(.white)
								.frame(width: 44, height: 44)
								.background(.black.opacity(0.45), in: Circle())
						}
						.accessibilityLabel("设置长按倍速")
					}
				}
				.padding(.horizontal, 12)
				.padding(.top, 8)

				Spacer(minLength: 0)
					.allowsHitTesting(false)

				if speedBoosting {
					Text("\(String(format: "%.1f", holdSpeed))x 倍速播放中 · 松手恢复")
						.font(.subheadline.weight(.bold))
						.foregroundStyle(.black)
						.padding(.horizontal, 14)
						.padding(.vertical, 8)
						.background(HGTheme.accent, in: Capsule())
						.padding(.bottom, 12)
						.transition(.scale.combined(with: .opacity))
						.allowsHitTesting(false)
				}
			}
			.animation(.snappy, value: speedBoosting)
		}
		.frame(maxWidth: .infinity)
		.aspectRatio(16 / 9, contentMode: .fit)
		.background(Color.black)
	}

	// MARK: - Info

	private func infoBlock(_ d: VideoDetail) -> some View {
		VStack(alignment: .leading, spacing: 14) {
			Text(d.title)
				.font(.title2.weight(.bold))
				.foregroundStyle(HGTheme.textPrimary)
				.fixedSize(horizontal: false, vertical: true)

			HStack(spacing: 8) {
				metaChip(String(format: "%.1f 分", d.score), icon: "star.fill", emphasize: d.score > 0)
				metaChip(d.isFinished ? "已完结" : "连载中", icon: d.isFinished ? "checkmark.circle.fill" : "clock.fill", emphasize: false)
				metaChip("\(d.episodeCount) 集", icon: "rectangle.stack.fill", emphasize: false)
				metaChip(formatCount(d.hot), icon: "flame.fill", emphasize: false)
				Spacer(minLength: 0)
			}

			if d.authorId > 0 || !d.authorName.isEmpty {
				NavigationLink(value: AppRoute.author(d.authorId)) {
					HStack(spacing: 10) {
						ZStack {
							Circle().fill(HGTheme.surface)
							Image(systemName: "person.fill")
								.font(.caption.weight(.semibold))
								.foregroundStyle(HGTheme.accent)
						}
						.frame(width: 36, height: 36)
						VStack(alignment: .leading, spacing: 2) {
							Text(d.authorName.isEmpty ? "作者" : d.authorName)
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
				.disabled(d.authorId <= 0)
				.frame(minHeight: 44)
			}

			if !d.tags.isEmpty {
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 8) {
						ForEach(Array(d.tags.prefix(8)), id: \.self) { tag in
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

			if hevcURL != nil {
				Toggle("优先 HEVC 线路", isOn: $useHEVC)
					.tint(HGTheme.accent)
					.font(.subheadline)
					.foregroundStyle(HGTheme.textSecondary)
					.onChange(of: useHEVC) { _, _ in
						Task { await replayCurrent() }
					}
			}

			if !d.description.isEmpty {
				VStack(alignment: .leading, spacing: 8) {
					Text(d.description)
						.font(.body)
						.foregroundStyle(HGTheme.textSecondary)
						.lineSpacing(4)
						.lineLimit(descExpanded ? nil : 3)
						.fixedSize(horizontal: false, vertical: true)
					Button(descExpanded ? "收起简介" : "展开简介") {
						withAnimation(.snappy) { descExpanded.toggle() }
					}
					.font(.caption.weight(.semibold))
					.foregroundStyle(HGTheme.accent)
					.frame(minHeight: 44, alignment: .leading)
					.contentShape(Rectangle())
				}
			}
		}
		.padding(16)
	}

	private func metaChip(_ text: String, icon: String, emphasize: Bool) -> some View {
		Label(text, systemImage: icon)
			.font(.caption2.weight(.semibold))
			.foregroundStyle(emphasize ? .black : HGTheme.textSecondary)
			.padding(.horizontal, 8)
			.padding(.vertical, 5)
			.background(
				Capsule().fill(emphasize ? HGTheme.accent : HGTheme.surface)
			)
			.symbolRenderingMode(.hierarchical)
			.lineLimit(1)
	}

	// MARK: - Actions

	private var actionRow: some View {
		HStack(spacing: 0) {
			actionItem(
				title: liked ? "已赞" : "点赞",
				system: liked ? "heart.fill" : "heart",
				on: liked
			) { Task { await toggleLike() } }
			actionItem(
				title: collected ? "已藏" : "收藏",
				system: collected ? "star.fill" : "star",
				on: collected
			) { Task { await toggleCollect() } }
			actionItem(
				title: myScore > 0 ? "\(myScore)星" : "评分",
				system: myScore > 0 ? "hand.thumbsup.fill" : "hand.thumbsup",
				on: showRate || myScore > 0
			) {
				if requireLogin() { withAnimation(.snappy) { showRate.toggle() } }
			}
			actionItem(
				title: "评论",
				system: showComments ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right",
				on: showComments
			) {
				withAnimation(.snappy) { showComments.toggle() }
				if showComments && comments.isEmpty {
					Task { await loadComments() }
				}
			}
		}
		.padding(.horizontal, 8)
		.disabled(acting)
		.opacity(acting ? 0.7 : 1)
	}

	private func actionItem(title: String, system: String, on: Bool, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			VStack(spacing: 6) {
				Image(systemName: system)
					.font(.title3.weight(.semibold))
					.foregroundStyle(on ? HGTheme.accent : HGTheme.textPrimary)
					.symbolRenderingMode(.hierarchical)
					.frame(height: 28)
				Text(title)
					.font(.caption2.weight(.semibold))
					.foregroundStyle(on ? HGTheme.accent : HGTheme.textSecondary)
			}
			.frame(maxWidth: .infinity, minHeight: 56)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(title)
	}

	private var rateRow: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("给这部剧打分")
				.font(.caption.weight(.semibold))
				.foregroundStyle(HGTheme.textMuted)
				.padding(.horizontal, 16)
			HStack(spacing: 8) {
				ForEach(1...5, id: \.self) { s in
					Button {
						Task { await rate(s) }
					} label: {
						Text("\(s)")
							.font(.subheadline.weight(.bold))
							.foregroundStyle(myScore == s ? .black : HGTheme.textPrimary)
							.frame(maxWidth: .infinity, minHeight: 44)
							.background(
								RoundedRectangle(cornerRadius: 10, style: .continuous)
									.fill(myScore == s ? HGTheme.accent : HGTheme.surface)
							)
							.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					.disabled(acting)
					.accessibilityLabel("评分 \(s) 星")
				}
			}
			.padding(.horizontal, 16)
		}
	}

	// MARK: - Episodes

	private func episodeBlock(_ d: VideoDetail) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Text("选集")
					.font(.headline)
					.foregroundStyle(HGTheme.textPrimary)
				Spacer()
				Text("正在播放第 \(currentEp) 集")
					.font(.caption)
					.foregroundStyle(HGTheme.textMuted)
			}
			.padding(.horizontal, 16)

			LazyVGrid(
				columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
				spacing: 8
			) {
				ForEach(d.episodes) { ep in
					let selected = currentEp == ep.epNum
					Button {
						Task { await play(ep: ep.epNum, locked: ep.locked) }
					} label: {
						VStack(spacing: 2) {
							Text("\(ep.epNum)")
								.font(.subheadline.weight(.bold))
							if selected {
								Text("播放中")
									.font(.caption2.weight(.semibold))
							}
						}
						.foregroundStyle(ep.locked ? HGTheme.textMuted : (selected ? .black : HGTheme.textPrimary))
						.frame(maxWidth: .infinity, minHeight: 48)
						.background(
							RoundedRectangle(cornerRadius: 10, style: .continuous)
								.fill(
									ep.locked
										? HGTheme.surface.opacity(0.5)
										: (selected ? HGTheme.accent : HGTheme.surface)
								)
						)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					.disabled(ep.locked)
					.accessibilityLabel(ep.locked ? "第\(ep.epNum)集已锁定" : "第\(ep.epNum)集")
				}
			}
			.padding(.horizontal, 16)
			.padding(.bottom, 8)
		}
		.padding(.top, 8)
	}

	// MARK: - Comments / Related

	private var commentsBlock: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionHeader(title: "评论")
			HStack(spacing: 10) {
				TextField("说点什么…", text: $commentText)
					.padding(12)
					.background(HGTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
					.foregroundStyle(HGTheme.textPrimary)
				Button {
					Task { await sendComment() }
				} label: {
					Text("发送")
						.font(.subheadline.weight(.semibold))
						.frame(minWidth: 56, minHeight: 44)
				}
				.buttonStyle(.glassProminent)
				.tint(HGTheme.accent)
			}
			.padding(.horizontal, 16)

			if comments.isEmpty {
				Text("还没有评论，来抢沙发吧")
					.font(.subheadline)
					.foregroundStyle(HGTheme.textMuted)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 16)
			} else {
				LazyVStack(alignment: .leading, spacing: 0) {
					ForEach(Array(comments.enumerated()), id: \.element.id) { index, c in
						VStack(alignment: .leading, spacing: 6) {
							HStack {
								Text(c.userName.isEmpty ? "用户" : c.userName)
									.font(.caption.weight(.semibold))
									.foregroundStyle(HGTheme.accent)
								Spacer()
								Text(c.createdAt)
									.font(.caption2)
									.foregroundStyle(HGTheme.textMuted)
							}
							Text(c.text)
								.font(.subheadline)
								.foregroundStyle(HGTheme.textPrimary)
								.fixedSize(horizontal: false, vertical: true)
						}
						.padding(.horizontal, 16)
						.padding(.vertical, 12)

						if index < comments.count - 1 {
							Divider().background(HGTheme.glassStroke).padding(.leading, 16)
						}
					}
				}
			}
		}
		.padding(.bottom, 8)
	}

	private var relatedStrip: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(alignment: .top, spacing: 12) {
				ForEach(related) { item in
					NavigationLink(value: AppRoute.detail(item.id)) {
						VideoPosterCard(item: item, width: 110)
					}
					.buttonStyle(.plain)
				}
			}
			.padding(.horizontal, 16)
		}
	}

	// MARK: - Helpers / Data

	private func formatCount(_ n: Int) -> String {
		if n >= 100_000_000 { return String(format: "%.1f亿", Double(n) / 100_000_000) }
		if n >= 10_000 { return String(format: "%.1f万", Double(n) / 10_000) }
		return "\(n)"
	}

	private func load(force: Bool) async {
		// 全屏进出会让 .task 重入；已有详情/播放器则跳过，禁止重新拉流（会从头播）
		if !force, loadedVideoId == videoId, detail != nil {
			return
		}
		loading = true
		errorText = ""
		do {
			let d = try await APIService.shared.fetchVideoDetail(id: videoId)
			detail = d
			loadedVideoId = videoId
			let vid = Int(d.id) ?? -1
			liked = d.liked || SessionStore.shared.user.likeVideoIds.contains(vid)
			collected = d.collected || SessionStore.shared.user.favoriteVideoIds.contains(vid)
			if SessionStore.shared.isLoggedIn {
				if let my = try? await APIService.shared.fetchMyRating(videoId: videoId, ep: 1), my > 0 {
					myScore = my
				}
			}
			await APIService.shared.visitVideo(id: videoId)
			related = ((try? await APIService.shared.fetchRelated(videoId: videoId)) ?? []).uniquedPreservingOrder()
			if player == nil, let first = d.episodes.first(where: { !$0.locked }) {
				await play(ep: first.epNum, locked: false)
			}
		} catch {
			errorText = error.localizedDescription
		}
		loading = false
	}

	private func play(ep: Int, locked: Bool) async {
		if locked {
			playTip = "该集暂不可播"
			return
		}
		playLoading = true
		currentEp = ep
		playTip = "获取播放地址…"
		do {
			let info = try await APIService.shared.fetchPlayback(videoId: videoId, ep: ep)
			guard let url = URL(string: info.url) else {
				playTip = "播放地址无效"
				playLoading = false
				return
			}
			playURL = url
			expiresAt = info.expiresAt
			hevcURL = URL(string: info.hevcURL)
			await AudioSession.activatePlaybackAsync()
			let chosen = (useHEVC ? hevcURL : nil) ?? url
			let p = AVPlayer(url: chosen)
			p.isMuted = false
			p.volume = 1
			player?.pause()
			player = p
			p.play()
			playTip = ""
			await APIService.shared.syncHistory(videoId: videoId, ep: ep)
		} catch {
			playTip = "播放失败"
			playURL = nil
		}
		playLoading = false
	}

	private func replayCurrent() async {
		await play(ep: currentEp, locked: false)
	}

	@MainActor
	private func requireLogin() -> Bool {
		if SessionStore.shared.isLoggedIn { return true }
		needLogin = true
		flashToast("请先登录后再操作")
		return false
	}

	@MainActor
	private func flashToast(_ text: String) {
		toastTask?.cancel()
		toast = text
		toastTask = Task {
			try? await Task.sleep(nanoseconds: 2_200_000_000)
			guard !Task.isCancelled else { return }
			toast = ""
		}
	}

	@MainActor
	private func toggleLike() async {
		guard requireLogin() else { return }
		guard !acting else { return }
		let next = !liked
		liked = next
		acting = true
		defer { acting = false }
		do {
			liked = try await APIService.shared.likeVideo(id: videoId, ep: currentEp, on: next)
			flashToast(liked ? "已点赞" : "已取消点赞")
			UIImpactFeedbackGenerator(style: .light).impactOccurred()
		} catch {
			liked = !next
			flashToast(error.localizedDescription)
		}
	}

	@MainActor
	private func toggleCollect() async {
		guard requireLogin() else { return }
		guard !acting else { return }
		let next = !collected
		collected = next
		acting = true
		defer { acting = false }
		do {
			collected = try await APIService.shared.collectVideo(id: videoId, ep: currentEp, on: next)
			flashToast(collected ? "已收藏" : "已取消收藏")
			UIImpactFeedbackGenerator(style: .light).impactOccurred()
		} catch {
			collected = !next
			flashToast(error.localizedDescription)
		}
	}

	@MainActor
	private func rate(_ s: Int) async {
		guard requireLogin() else { return }
		guard !acting else { return }
		let previous = myScore
		myScore = s
		acting = true
		defer { acting = false }
		do {
			myScore = try await APIService.shared.rateVideo(id: videoId, score: s)
			showRate = false
			flashToast("已评分 \(myScore) 星")
			UIImpactFeedbackGenerator(style: .light).impactOccurred()
		} catch {
			myScore = previous
			flashToast(error.localizedDescription)
		}
	}

	@MainActor
	private func loadComments() async {
		do {
			let r = try await APIService.shared.fetchComments(videoId: videoId, page: 1)
			comments = r.items
		} catch {
			flashToast(error.localizedDescription)
		}
	}

	@MainActor
	private func sendComment() async {
		guard requireLogin() else { return }
		let t = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !t.isEmpty else { return }
		do {
			try await APIService.shared.postComment(videoId: videoId, text: t, ep: currentEp)
			commentText = ""
			await loadComments()
			flashToast("评论已发送")
		} catch {
			flashToast(error.localizedDescription)
		}
	}
}

/// 全屏状态需要同步可读，不能只靠 @State 发布时机
private final class FullscreenGate {
	var isFullscreen = false
}
