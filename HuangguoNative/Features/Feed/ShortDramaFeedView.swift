import SwiftUI
import AVKit
import AVFoundation
import UIKit
import CoreImage
import CoreVideo

/// 竖屏整页滑动刷短剧：推荐流默认第 1 集；点「看全集」后可在本页继续下滑连播后续集
struct ShortDramaFeedView: View {
	@Binding var path: NavigationPath

	@State private var items: [ShortDramaPage] = []
	@State private var currentID: String?
	@State private var page = 1
	@State private var pages = 1
	@State private var loading = true
	@State private var loadingMore = false
	@State private var expandingID: String?
	/// 非空表示正在该剧连播；点「退出连播」可回到推荐流
	@State private var seriesVideoId: String?
	@State private var errorText = ""
	@State private var prefetcher = ShortDramaPrefetcher()
	@State private var showSwipeHint = true
	@State private var swipeHintText = "上滑看下一条"
	/// 长按倍速时锁住分页滑动，避免误切下一条
	@State private var scrollLocked = false

	var body: some View {
		GeometryReader { geo in
			// 仅作「有有效尺寸」门闸；真正的分页高度交给 containerRelativeFrame，贴齐 ScrollView 可视区，避免露下一条
			let ready = geo.size.width > 32 && geo.size.height > 32
			ZStack {
				Color.black
				if loading && items.isEmpty {
					VStack(spacing: 14) {
						ProgressView().tint(HGTheme.accent).scaleEffect(1.1)
						Text("正在加载短剧…")
							.font(.subheadline.weight(.medium))
							.foregroundStyle(.white.opacity(0.7))
					}
				} else if !errorText.isEmpty && items.isEmpty {
					StateBox(text: errorText) {
						Task { await load(reset: true) }
					}
				} else if ready {
					ZStack(alignment: .top) {
						ScrollView(.vertical) {
							LazyVStack(spacing: 0) {
								ForEach(items) { item in
									ShortDramaCell(
										page: item,
										isActive: item.id == currentID,
										prefetcher: prefetcher,
										scrollLocked: $scrollLocked,
										seriesArmed: seriesVideoId == item.videoId,
										expanding: expandingID == item.id,
										onWatchAll: {
											if seriesVideoId == item.videoId {
												exitSeriesBinge(keeping: item.id)
											} else {
												Task { await expandFullSeries(from: item.id) }
											}
										},
										onOpenDetail: { path.append(AppRoute.detail(item.videoId)) },
										onRequestNext: { advanceToNext(from: item.id) }
									)
									// 相对滚动容器满高，Tab 栏高度变化时也不会矮一截露出下一条
									.containerRelativeFrame([.horizontal, .vertical])
									.clipped()
									.contentShape(Rectangle())
									.id(item.id)
								}
							}
							.scrollTargetLayout()
						}
						.scrollTargetBehavior(.paging)
						.scrollPosition(id: $currentID)
						.scrollIndicators(.hidden)
						.scrollDisabled(scrollLocked)
						.clipShape(Rectangle())

						VStack(spacing: 8) {
							if seriesVideoId != nil {
								Text("连播中 · 点右侧「退出连播」可返回")
									.font(.caption.weight(.semibold))
									.foregroundStyle(.white)
									.padding(.horizontal, 12)
									.padding(.vertical, 7)
									.background(.black.opacity(0.45), in: Capsule())
									.allowsHitTesting(false)
							}
							if showSwipeHint {
								Text(swipeHintText)
									.font(.caption.weight(.semibold))
									.foregroundStyle(.white)
									.padding(.horizontal, 12)
									.padding(.vertical, 7)
									.background(.black.opacity(0.45), in: Capsule())
									.transition(.opacity.combined(with: .move(edge: .top)))
									.allowsHitTesting(false)
							}
						}
						.padding(.top, 10)
					}
				}
			}
		}
		.background(Color.black.ignoresSafeArea())
		.toolbar(.hidden, for: .navigationBar)
		.task {
			guard items.isEmpty else { return }
			await load(reset: true)
			Task {
				try? await Task.sleep(nanoseconds: 2_400_000_000)
				withAnimation(.easeOut(duration: 0.35)) { showSwipeHint = false }
			}
		}
		.onChange(of: currentID) { _, newID in
			if showSwipeHint {
				withAnimation(.easeOut(duration: 0.25)) { showSwipeHint = false }
			}
			guard let newID, let idx = items.firstIndex(where: { $0.id == newID }) else { return }
			// 滑出本剧后自动结束连播状态
			if let sid = seriesVideoId, items[idx].videoId != sid {
				seriesVideoId = nil
			}
			prefetcher.maintain(centerIndex: idx, items: items)
			Task { await ensureSeriesTail(around: newID) }
			if idx >= items.count - 3 {
				Task { await load(reset: false) }
			}
		}
		.onDisappear {
			prefetcher.evictAll(except: [])
		}
	}

	@discardableResult
	private func advanceToNext(from pageID: String) -> Bool {
		guard let idx = items.firstIndex(where: { $0.id == pageID }),
		      items.indices.contains(idx + 1)
		else { return false }
		withAnimation(.easeInOut(duration: 0.25)) {
			currentID = items[idx + 1].id
		}
		return true
	}

	/// 退出连播：只保留当前这一集，去掉同剧其它集，下一条回到推荐
	private func exitSeriesBinge(keeping pageID: String) {
		guard let idx = items.firstIndex(where: { $0.id == pageID }) else { return }
		let cur = items[idx]
		let trimmed = items.filter { $0.videoId != cur.videoId || $0.id == cur.id }
		items = trimmed
		currentID = cur.id
		seriesVideoId = nil
		prefetcher.evictAll(except: [cur.id])
		if let i = items.firstIndex(where: { $0.id == cur.id }) {
			prefetcher.maintain(centerIndex: i, items: items)
		}
		swipeHintText = "上滑看下一条"
		withAnimation(.snappy) { showSwipeHint = true }
		Task {
			try? await Task.sleep(nanoseconds: 1_800_000_000)
			withAnimation(.easeOut(duration: 0.3)) { showSwipeHint = false }
		}
		UIImpactFeedbackGenerator(style: .light).impactOccurred()
	}

	private func expandFullSeries(from pageID: String) async {
		guard let idx = items.firstIndex(where: { $0.id == pageID }) else { return }
		let base = items[idx]
		if base.episodeCount <= 1 {
			path.append(AppRoute.detail(base.videoId))
			return
		}
		expandingID = pageID
		defer { expandingID = nil }
		do {
			let detail = try await APIService.shared.fetchVideoDetail(id: base.videoId)
			var epNums = detail.episodes.filter { !$0.locked }.map(\.epNum).sorted()
			if epNums.isEmpty, !detail.episodes.isEmpty {
				// status 解析异常导致全 locked 时仍允许连播
				epNums = detail.episodes.map(\.epNum).sorted()
			}
			if epNums.isEmpty {
				let n = max(detail.episodeCount, base.episodeCount, 1)
				epNums = Array(1...n)
			}
			let forward = epNums.filter { $0 > base.ep }
			guard !forward.isEmpty else {
				path.append(AppRoute.detail(base.videoId))
				return
			}
			var next = items
			let insertAt = idx + 1
			while insertAt < next.count, next[insertAt].videoId == base.videoId {
				next.remove(at: insertAt)
			}
			let total = max(base.episodeCount, detail.episodeCount, epNums.count)
			// 先只插后面一小段，避免一次插入几十集把 LazyVStack / scrollPosition 搞崩
			let chunk = Array(forward.prefix(8))
			let inserted = chunk.map { ep in
				ShortDramaPage.fromSeries(
					base: base,
					detail: detail,
					ep: ep,
					total: total,
					locked: false
				)
			}
			next.insert(contentsOf: inserted, at: insertAt)
			let keepID = base.id
			items = next
			currentID = keepID
			seriesVideoId = base.videoId
			prefetcher.evictAll(except: [keepID])
			prefetcher.maintain(centerIndex: idx, items: items)
			swipeHintText = "上滑看下一集"
			withAnimation(.snappy) { showSwipeHint = true }
			Task {
				try? await Task.sleep(nanoseconds: 2_200_000_000)
				withAnimation(.easeOut(duration: 0.3)) { showSwipeHint = false }
			}
		} catch {
			path.append(AppRoute.detail(base.videoId))
		}
	}

	/// 滑到本剧已插入集数末尾时，继续补后续集
	private func ensureSeriesTail(around pageID: String) async {
		guard let idx = items.firstIndex(where: { $0.id == pageID }) else { return }
		let cur = items[idx]
		guard seriesVideoId == cur.videoId else { return }
		guard cur.episodeCount > cur.ep else { return }
		// 已在同剧段末尾附近才补
		let nextIdx = idx + 1
		if nextIdx < items.count, items[nextIdx].videoId == cur.videoId { return }
		let have = Set(items.filter { $0.videoId == cur.videoId }.map(\.ep))
		let want = Array((cur.ep + 1)...cur.episodeCount).filter { !have.contains($0) }
		guard !want.isEmpty else { return }
		let chunk = Array(want.prefix(8))
		let inserted = chunk.map { ep in
			ShortDramaPage(
				videoId: cur.videoId,
				ep: ep,
				title: cur.title,
				cover: cur.cover,
				score: cur.score,
				hot: cur.hot,
				episodeCount: cur.episodeCount,
				isFinished: cur.isFinished,
				tags: cur.tags,
				desc: cur.desc,
				badge: cur.badge,
				durationSec: 0,
				locked: false
			)
		}
		var next = items
		next.insert(contentsOf: inserted, at: idx + 1)
		items = next
		prefetcher.maintain(centerIndex: idx, items: items)
	}

	private func load(reset: Bool) async {
		if reset {
			loading = true
			errorText = ""
			page = 1
			prefetcher.evictAll(except: [])
		} else {
			guard !loadingMore, page <= pages else { return }
			loadingMore = true
		}
		do {
			let r = try await APIService.shared.fetchFeed(kind: "recommend", page: page)
			let mapped = r.items.uniquedPreservingOrder().map(ShortDramaPage.fromRecommend)
			if reset {
				items = mapped
				currentID = items.first?.id
				if let idx = items.firstIndex(where: { $0.id == currentID }) {
					prefetcher.maintain(centerIndex: idx, items: items)
				}
			} else {
				items.mergeUnique(mapped)
				if let id = currentID, let idx = items.firstIndex(where: { $0.id == id }) {
					prefetcher.maintain(centerIndex: idx, items: items)
				}
			}
			pages = max(r.pages, 1)
			page = r.page + 1
		} catch {
			if items.isEmpty {
				errorText = error.localizedDescription
			}
		}
		loading = false
		loadingMore = false
	}
}

/// 刷剧分页条目：同一剧不同集用 videoId#ep 区分
struct ShortDramaPage: Identifiable, Hashable, Sendable {
	var id: String { "\(videoId)#\(ep)" }
	let videoId: String
	var ep: Int
	var title: String
	var cover: String
	var score: Double
	var hot: Int
	var episodeCount: Int
	var isFinished: Bool
	var tags: [String]
	var desc: String
	var badge: String
	var durationSec: Int
	var locked: Bool

	static func fromRecommend(_ card: VideoCard) -> ShortDramaPage {
		ShortDramaPage(
			videoId: card.id,
			ep: 1,
			title: card.title,
			cover: card.cover,
			score: card.score,
			hot: card.hot,
			episodeCount: card.episodeCount,
			isFinished: card.isFinished,
			tags: card.tags,
			desc: card.desc,
			badge: card.badge,
			durationSec: card.durationSec,
			locked: false
		)
	}

	static func fromSeries(
		base: ShortDramaPage,
		detail: VideoDetail,
		ep: Int,
		total: Int,
		locked: Bool
	) -> ShortDramaPage {
		ShortDramaPage(
			videoId: base.videoId,
			ep: ep,
			title: base.title,
			cover: detail.cover.isEmpty ? base.cover : detail.cover,
			score: detail.score > 0 ? detail.score : base.score,
			hot: detail.hot > 0 ? detail.hot : base.hot,
			episodeCount: total,
			isFinished: detail.isFinished || base.isFinished,
			tags: detail.tags.isEmpty ? base.tags : detail.tags,
			desc: detail.description.isEmpty ? base.desc : detail.description,
			badge: base.badge,
			durationSec: detail.episodes.first(where: { $0.epNum == ep })?.durationSec ?? 0,
			locked: locked
		)
	}
}

// MARK: - Prefetch

@MainActor
final class ShortDramaPrefetcher {
	private var players: [String: AVPlayer] = [:]
	private var tasks: [String: Task<Void, Never>] = [:]

	func maintain(centerIndex: Int, items: [ShortDramaPage]) {
		var keep: [String] = []
		for offset in [0, 1] {
			let j = centerIndex + offset
			guard items.indices.contains(j) else { continue }
			keep.append(items[j].id)
		}
		let keepSet = Set(keep)
		evictAll(except: keepSet)

		// 只预加载下一条，避免和当前集抢 playback 通道（连播时尤其容易卡加载）
		for offset in [1] {
			let j = centerIndex + offset
			guard items.indices.contains(j) else { continue }
			let page = items[j]
			if page.locked { continue }
			if players[page.id] != nil { continue }
			if tasks[page.id] != nil { continue }
			tasks[page.id] = Task { [weak self] in
				await self?.prepare(page: page)
			}
		}
	}

	func consume(pageId: String) -> AVPlayer? {
		tasks[pageId]?.cancel()
		tasks.removeValue(forKey: pageId)
		return players.removeValue(forKey: pageId)
	}

	func park(pageId: String, player: AVPlayer?) {
		guard let player else { return }
		player.pause()
		if let old = players[pageId], old !== player {
			old.pause()
			old.replaceCurrentItem(with: nil)
		}
		players[pageId] = player
	}

	func evictAll(except keep: Set<String>) {
		for id in Array(tasks.keys) where !keep.contains(id) {
			tasks[id]?.cancel()
			tasks.removeValue(forKey: id)
		}
		for id in Array(players.keys) where !keep.contains(id) {
			players[id]?.pause()
			players[id]?.replaceCurrentItem(with: nil)
			players.removeValue(forKey: id)
		}
	}

	private func prepare(page: ShortDramaPage) async {
		let pageId = page.id
		defer { tasks.removeValue(forKey: pageId) }
		if Task.isCancelled { return }
		if players[pageId] != nil { return }
		do {
			await AudioSession.activatePlaybackAsync()
			if Task.isCancelled { return }
			let info = try await APIService.shared.fetchPlayback(videoId: page.videoId, ep: page.ep)
			if Task.isCancelled { return }
			guard let url = URL(string: info.url), !info.url.isEmpty else { return }
			let p = ShortDramaPlayerFactory.make(url: url)
			p.isMuted = true
			let ready = await ShortDramaPlayerFactory.waitReady(p.currentItem, timeout: 16)
			if Task.isCancelled {
				p.replaceCurrentItem(with: nil)
				return
			}
			if ready {
				p.play()
				try? await Task.sleep(nanoseconds: 350_000_000)
				p.pause()
				await p.seek(to: .zero)
				p.isMuted = false
				if Task.isCancelled {
					p.replaceCurrentItem(with: nil)
					return
				}
				players[pageId] = p
			} else {
				p.replaceCurrentItem(with: nil)
			}
		} catch {}
	}
}

enum ShortDramaPlayerFactory {
	static func make(url: URL) -> AVPlayer {
		let headers: [String: String] = [
			"Referer": EndpointRouter.referer,
			"User-Agent": "HuangguoNative/1.0",
		]
		let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
		let item = AVPlayerItem(asset: asset)
		item.preferredForwardBufferDuration = 6
		let p = AVPlayer(playerItem: item)
		p.automaticallyWaitsToMinimizeStalling = true
		p.isMuted = false
		p.volume = 1
		return p
	}

	static func waitReady(_ item: AVPlayerItem?, timeout: TimeInterval) async -> Bool {
		guard let item else { return false }
		if item.status == .readyToPlay { return true }
		if item.status == .failed { return false }
		return await withCheckedContinuation { continuation in
			final class Box: @unchecked Sendable {
				var obs: NSKeyValueObservation?
				var done = false
				let lock = NSLock()
				func finish(_ ok: Bool, _ cont: CheckedContinuation<Bool, Never>) {
					lock.lock()
					defer { lock.unlock() }
					guard !done else { return }
					done = true
					obs?.invalidate()
					obs = nil
					cont.resume(returning: ok)
				}
			}
			let box = Box()
			box.obs = item.observe(\.status, options: [.initial, .new]) { item, _ in
				switch item.status {
				case .readyToPlay: box.finish(true, continuation)
				case .failed: box.finish(false, continuation)
				default: break
				}
			}
			Task {
				try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
				box.finish(item.status == .readyToPlay, continuation)
			}
		}
	}
}

// MARK: - Cell

private struct ShortDramaCell: View {
	let page: ShortDramaPage
	let isActive: Bool
	var prefetcher: ShortDramaPrefetcher
	@Binding var scrollLocked: Bool
	var seriesArmed: Bool
	var expanding: Bool
	var onWatchAll: () -> Void
	var onOpenDetail: () -> Void
	var onRequestNext: () -> Bool

	@State private var player: AVPlayer?
	@State private var paused = false
	@State private var tip = ""
	@State private var loadingPlay = false
	@State private var generation = 0
	@State private var progress: Double = 0
	@State private var endObserver: NSObjectProtocol?
	@State private var timeObserver: Any?
	@State private var boosting = false
	@State private var holdSpeed: Float = 2.0
	@State private var previousRate: Float = 1
	@State private var scrubbing = false
	@State private var scrubProgress: Double = 0
	/// 供 AVPlayer 时间回调读取（避免 struct 值捕获过期）
	@State private var scrubGate = ScrubGate()
	@State private var duration: Double = 0
	@State private var previewImage: UIImage?
	@State private var previewTask: Task<Void, Never>?
	@State private var videoOutput: AVPlayerItemVideoOutput?
	/// 长按倍速：按下后延迟到齐最小时长再加速，避免与单击暂停/播放打架
	@State private var boostArmTask: Task<Void, Never>?
	@State private var suppressTapAfterBoost = false
	@State private var showComments = false
	@State private var comments: [CommentItem] = []
	@State private var commentText = ""
	@State private var commentsLoading = false
	@State private var commentsLoadingMore = false
	@State private var commentsPage = 1
	@State private var commentsPages = 1
	@State private var commentsTotal = 0
	@State private var commentToast = ""
	/// 折叠短时 isActive 抖动，避免 park 后 loading 清不掉 / 反复取消拉流
	@State private var activeSwitchTask: Task<Void, Never>?

	var body: some View {
		ZStack {
			Color.black

			// 画面
			Group {
				if let player {
					HGPlayerLayerView(player: player)
				} else {
					HGCoverImage(url: page.cover, cornerRadius: 0, contentMode: .fill)
				}
			}
			.allowsHitTesting(false)

			// 上下遮罩：保可读性，不挡中间点击
			VStack(spacing: 0) {
				LinearGradient(
					colors: [.black.opacity(0.35), .clear],
					startPoint: .top,
					endPoint: .bottom
				)
				.frame(height: 100)
				Spacer(minLength: 0)
				LinearGradient(
					colors: [.clear, .black.opacity(0.55), .black.opacity(0.82)],
					startPoint: .top,
					endPoint: .bottom
				)
				.frame(height: 280)
			}
			.allowsHitTesting(false)

			// 仅中间画面响应点击暂停 / 长按倍速（避开底部进度条与右侧按钮）
			// 注意：不能在 pressing=true 时立刻 beginBoost，否则短按会走「加速→恢复→再 toggle」又停掉
			Color.clear
				.contentShape(Rectangle())
				.padding(.trailing, 78)
				.padding(.bottom, 58)
				.onTapGesture { handleVideoTap() }
				.onLongPressGesture(minimumDuration: 0.35, maximumDistance: 64, pressing: { pressing in
					if pressing {
						armBoost()
					} else {
						cancelBoostArm()
						let engaged = boosting
						endBoost()
						if engaged {
							// 松手结束倍速时系统偶发再派发 tap，吞掉以免又暂停
							suppressTapAfterBoost = true
						}
					}
				}, perform: {})

			// 加载 / 失败
			if loadingPlay {
				ProgressView()
					.tint(HGTheme.accent)
					.scaleEffect(1.15)
					.padding(18)
					.background(.black.opacity(0.4), in: Circle())
					.allowsHitTesting(false)
			} else if player == nil, !tip.isEmpty {
				VStack(spacing: 10) {
					Image(systemName: "exclamationmark.triangle.fill")
						.font(.title2)
						.foregroundStyle(HGTheme.accent)
					Text(tip)
						.font(.subheadline.weight(.medium))
						.foregroundStyle(.white.opacity(0.9))
						.multilineTextAlignment(.center)
				}
				.padding(20)
				.background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
				.padding(.horizontal, 32)
				.allowsHitTesting(false)
			}

			// 暂停（倍速中不显示）
			if paused, player != nil, !boosting {
				Image(systemName: "play.fill")
					.font(.system(size: 40, weight: .bold))
					.foregroundStyle(.white)
					.padding(26)
					.background(.ultraThinMaterial.opacity(0.55), in: Circle())
					.shadow(color: .black.opacity(0.35), radius: 12, y: 4)
					.transition(.scale(scale: 0.85).combined(with: .opacity))
					.allowsHitTesting(false)
			}

			// 长按倍速提示
			if boosting {
				VStack {
					Text("\(String(format: "%.1f", holdSpeed))x 倍速中 · 松手恢复")
						.font(.subheadline.weight(.bold))
						.foregroundStyle(.black)
						.padding(.horizontal, 14)
						.padding(.vertical, 8)
						.background(HGTheme.accent, in: Capsule())
						.shadow(color: .black.opacity(0.35), radius: 10, y: 4)
						.padding(.top, 56)
					Spacer(minLength: 0)
				}
				.transition(.opacity.combined(with: .scale(scale: 0.92)))
				.allowsHitTesting(false)
			}

			// 右侧操作栏 + 底部信息（文案不抢手势，按钮可点）
			HStack(alignment: .bottom, spacing: 12) {
				VStack(alignment: .leading, spacing: 10) {
					if !page.badge.isEmpty || page.isFinished {
						HStack(spacing: 6) {
							if !page.badge.isEmpty {
								Text(page.badge)
									.font(.caption2.weight(.bold))
									.foregroundStyle(.black)
									.padding(.horizontal, 8)
									.padding(.vertical, 4)
									.background(HGTheme.accent, in: Capsule())
							}
							if page.isFinished {
								Text("全集")
									.font(.caption2.weight(.bold))
									.foregroundStyle(.white)
									.padding(.horizontal, 8)
									.padding(.vertical, 4)
									.background(.white.opacity(0.18), in: Capsule())
							}
						}
					}

					Text(page.title)
						.font(.title3.weight(.bold))
						.foregroundStyle(.white)
						.lineLimit(2)
						.shadow(color: .black.opacity(0.5), radius: 6, y: 2)

					metaRow

					if !page.desc.isEmpty {
						Text(page.desc)
							.font(.footnote)
							.foregroundStyle(.white.opacity(0.78))
							.lineLimit(2)
					}

					if !page.tags.isEmpty {
						HStack(spacing: 6) {
							ForEach(Array(page.tags.prefix(3)), id: \.self) { tag in
								Text("#\(tag)")
									.font(.caption2.weight(.semibold))
									.foregroundStyle(.white.opacity(0.85))
									.padding(.horizontal, 8)
									.padding(.vertical, 4)
									.background(.white.opacity(0.12), in: Capsule())
									.lineLimit(1)
							}
						}
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.allowsHitTesting(false)

				VStack(spacing: 18) {
					sideAction(
						system: seriesArmed
							? "rectangle.stack.badge.minus"
							: "rectangle.stack.badge.play.fill",
						title: watchAllTitle,
						action: onWatchAll
					)
					sideAction(
						system: "bubble.left.and.bubble.right.fill",
						title: "评论",
						action: { showComments = true }
					)
					sideAction(
						system: "gauge.with.dots.needle.67percent",
						title: "\(String(format: "%.1f", holdSpeed))x",
						action: cycleHoldSpeed
					)
				}
				.padding(.bottom, 4)
			}
			.padding(.horizontal, 16)
			.padding(.bottom, scrubbing ? 96 : 52)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

			// 可拖动进度条 + 时间 / 预览（最上层）
			VStack {
				Spacer(minLength: 0)
				progressScrubber
					.padding(.horizontal, 16)
					.padding(.bottom, 4)
			}
		}
		.animation(.snappy(duration: 0.22), value: paused)
		.animation(.snappy(duration: 0.2), value: boosting)
		.onChange(of: isActive) { _, active in
			scheduleActive(active)
		}
		.onAppear {
			if isActive { scheduleActive(true) }
		}
		.onDisappear {
			activeSwitchTask?.cancel()
			parkOrTearDown()
		}
		.sheet(isPresented: $showComments) {
			ShortDramaCommentsSheet(
				comments: $comments,
				commentText: $commentText,
				loading: $commentsLoading,
				loadingMore: $commentsLoadingMore,
				toast: $commentToast,
				total: commentsTotal,
				hasMore: commentsPage < commentsPages,
				onAppearLoad: {
					Task { await loadComments(reset: true) }
				},
				onLoadMore: {
					Task { await loadMoreComments() }
				},
				onSend: { Task { await sendComment() } }
			)
			.presentationDetents([.medium, .large])
			.presentationDragIndicator(.visible)
		}
		.accessibilityElement(children: .contain)
		.accessibilityLabel("\(page.title) 第\(page.ep)集")
		.accessibilityHint("长按画面可倍速播放")
	}

	private var watchAllTitle: String {
		if expanding { return "展开中" }
		if seriesArmed { return "退出连播" }
		if page.episodeCount <= 1 { return "详情" }
		return "看全集"
	}

	private var metaRow: some View {
		HStack(spacing: 10) {
			if page.score > 0 {
				Label(String(format: "%.1f", page.score), systemImage: "star.fill")
			}
			if page.episodeCount > 0 {
				Label("第 \(page.ep)/\(page.episodeCount) 集", systemImage: "rectangle.stack.fill")
			} else {
				Label("第 \(page.ep) 集", systemImage: "rectangle.stack.fill")
			}
			if page.hot > 0 {
				Label(formatHot(page.hot), systemImage: "flame.fill")
			}
		}
		.font(.caption.weight(.semibold))
		.foregroundStyle(.white.opacity(0.88))
		.symbolRenderingMode(.hierarchical)
		.lineLimit(1)
	}

	private var displayedProgress: Double {
		scrubbing ? scrubProgress : progress
	}

	private var currentSeconds: Double {
		max(0, displayedProgress * max(duration, 0))
	}

	private var progressScrubber: some View {
		VStack(spacing: 6) {
			GeometryReader { g in
				let w = max(g.size.width, 1)
				let fill = max(4, w * displayedProgress)
				let thumb: CGFloat = scrubbing ? 14 : 10
				ZStack(alignment: .bottomLeading) {
					// 拖动预览
					if scrubbing {
						previewBubble(trackWidth: w, fill: fill)
							.offset(y: -10)
							.transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
					}

					ZStack(alignment: .leading) {
						Capsule()
							.fill(.white.opacity(0.2))
							.frame(height: scrubbing ? 5 : 3)
						Capsule()
							.fill(HGTheme.accent)
							.frame(width: fill, height: scrubbing ? 5 : 3)
						Circle()
							.fill(.white)
							.frame(width: thumb, height: thumb)
							.shadow(color: .black.opacity(0.35), radius: 3, y: 1)
							.offset(x: max(0, fill - thumb / 2))
							.opacity(player == nil ? 0.35 : 1)
					}
					.frame(maxHeight: .infinity, alignment: .bottom)
					.padding(.bottom, 14)
				}
				.contentShape(Rectangle())
				.highPriorityGesture(
					DragGesture(minimumDistance: 0)
						.onChanged { value in
							guard let player, !boosting else { return }
							if !scrubbing {
								scrubbing = true
								scrubGate.active = true
								scrollLocked = true
								scrubProgress = progress
								player.pause()
								UIImpactFeedbackGenerator(style: .light).impactOccurred()
							}
							let ratio = min(1, max(0, value.location.x / w))
							scrubProgress = ratio
							seekToProgress(ratio, exact: false)
							schedulePreview(at: ratio)
						}
						.onEnded { value in
							guard player != nil else {
								finishScrub()
								return
							}
							let ratio = min(1, max(0, value.location.x / w))
							scrubProgress = ratio
							progress = ratio
							seekToProgress(ratio, exact: true)
							finishScrub()
						}
				)
				.accessibilityLabel("播放进度")
				.accessibilityValue("\(formatClock(currentSeconds)) / \(formatClock(duration))")
				.accessibilityAdjustableAction { direction in
					guard player != nil else { return }
					let step = 0.05
					let next: Double
					switch direction {
					case .increment: next = min(1, progress + step)
					case .decrement: next = max(0, progress - step)
					@unknown default: return
					}
					progress = next
					seekToProgress(next, exact: true)
				}
			}
			.frame(height: scrubbing ? 118 : 44)

			HStack {
				Text(formatClock(currentSeconds))
					.foregroundStyle(.white.opacity(0.92))
				Spacer(minLength: 0)
				Text(formatClock(duration))
					.foregroundStyle(.white.opacity(0.65))
			}
			.font(.caption2.monospacedDigit().weight(.semibold))
			.padding(.horizontal, 2)
		}
		.animation(.snappy(duration: 0.15), value: scrubbing)
	}

	@ViewBuilder
	private func previewBubble(trackWidth: CGFloat, fill: CGFloat) -> some View {
		let bubbleW: CGFloat = 132
		let bubbleH: CGFloat = 74
		let centerX = min(max(fill, bubbleW / 2), trackWidth - bubbleW / 2)
		VStack(spacing: 6) {
			ZStack {
				// HLS 用 ImageGenerator 常失败；先封面托底，帧出来再盖上
				HGCoverImage(url: page.cover, cornerRadius: 10, contentMode: .fill)
				if let previewImage {
					Image(uiImage: previewImage)
						.resizable()
						.scaledToFill()
				}
			}
			.frame(width: bubbleW, height: bubbleH)
			.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: 10, style: .continuous)
					.strokeBorder(.white.opacity(0.25), lineWidth: 0.8)
			)
			.shadow(color: .black.opacity(0.45), radius: 10, y: 4)

			Text(formatClock(currentSeconds))
				.font(.caption.monospacedDigit().weight(.bold))
				.foregroundStyle(.white)
				.padding(.horizontal, 10)
				.padding(.vertical, 4)
				.background(.black.opacity(0.55), in: Capsule())
		}
		.frame(width: bubbleW)
		.offset(x: centerX - bubbleW / 2)
	}

	private func finishScrub() {
		let wasScrubbing = scrubbing
		scrubbing = false
		scrubGate.active = false
		previewTask?.cancel()
		previewTask = nil
		previewImage = nil
		if wasScrubbing, !paused, !boosting {
			player?.play()
		}
		if !boosting { scrollLocked = false }
	}

	private func formatClock(_ seconds: Double) -> String {
		guard seconds.isFinite, seconds >= 0 else { return "0:00" }
		let total = Int(seconds.rounded(.down))
		let h = total / 3600
		let m = (total % 3600) / 60
		let s = total % 60
		if h > 0 {
			return String(format: "%d:%02d:%02d", h, m, s)
		}
		return String(format: "%d:%02d", m, s)
	}

	private func seekToProgress(_ ratio: Double, exact: Bool) {
		guard let player, let item = player.currentItem else { return }
		var dur = item.duration
		if !dur.isNumeric || !dur.seconds.isFinite || dur.seconds <= 0 {
			if duration > 0 {
				dur = CMTime(seconds: duration, preferredTimescale: 600)
			} else {
				return
			}
		} else {
			duration = dur.seconds
		}
		let t = CMTime(seconds: dur.seconds * ratio, preferredTimescale: 600)
		if exact {
			player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
		} else {
			player.seek(
				to: t,
				toleranceBefore: CMTime(seconds: 0.35, preferredTimescale: 600),
				toleranceAfter: CMTime(seconds: 0.35, preferredTimescale: 600)
			)
		}
	}

	private func schedulePreview(at ratio: Double) {
		previewTask?.cancel()
		previewTask = Task { @MainActor in
			guard scrubbing, let player else { return }
			// 等 seek 解码出新帧（HLS 不能靠 AVAssetImageGenerator）
			for _ in 0..<12 {
				if Task.isCancelled || !scrubbing { return }
				try? await Task.sleep(nanoseconds: 45_000_000)
				if let img = capturePlayerFrame(from: player) {
					previewImage = img
					return
				}
			}
		}
		_ = ratio
	}

	private func ensureVideoOutput(on item: AVPlayerItem) {
		if videoOutput != nil { return }
		for existing in item.outputs {
			if let v = existing as? AVPlayerItemVideoOutput {
				videoOutput = v
				return
			}
		}
		let attrs: [String: Any] = [
			kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
		]
		let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
		item.add(output)
		videoOutput = output
	}

	private func capturePlayerFrame(from player: AVPlayer) -> UIImage? {
		guard let output = videoOutput else { return nil }
		let times: [CMTime] = [
			player.currentTime(),
			CMTimeSubtract(player.currentTime(), CMTime(seconds: 0.05, preferredTimescale: 600)),
			CMTimeSubtract(player.currentTime(), CMTime(seconds: 0.15, preferredTimescale: 600)),
		]
		for t in times where t.isNumeric {
			if output.hasNewPixelBuffer(forItemTime: t),
			   let buf = output.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil) {
				return UIImage.fromPixelBuffer(buf)
			}
		}
		// 有些机型 hasNewPixelBuffer 偏严，直接 copy 试一次
		let t = player.currentTime()
		if t.isNumeric, let buf = output.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil) {
			return UIImage.fromPixelBuffer(buf)
		}
		return nil
	}

	private func clearVideoOutput(from player: AVPlayer?) {
		if let output = videoOutput, let item = player?.currentItem {
			item.remove(output)
		}
		videoOutput = nil
	}

	private func sideAction(system: String, title: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			VStack(spacing: 6) {
				Image(systemName: system)
					.font(.title2.weight(.semibold))
					.foregroundStyle(.white)
					.frame(width: 48, height: 48)
					.background(.ultraThinMaterial.opacity(0.55), in: Circle())
					.overlay(Circle().strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
				Text(title)
					.font(.caption2.weight(.bold))
					.foregroundStyle(.white.opacity(0.92))
			}
			.frame(width: 64)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(title)
	}

	private func formatHot(_ n: Int) -> String {
		if n >= 100_000_000 { return String(format: "%.1f亿", Double(n) / 100_000_000) }
		if n >= 10_000 { return String(format: "%.1f万", Double(n) / 10_000) }
		return "\(n)"
	}

	private func handleVideoTap() {
		if suppressTapAfterBoost {
			suppressTapAfterBoost = false
			return
		}
		togglePause()
	}

	private func togglePause() {
		guard let player, !boosting else { return }
		if player.rate > 0.05 {
			player.pause()
			paused = true
		} else {
			player.play()
			paused = false
		}
	}

	private func armBoost() {
		cancelBoostArm()
		suppressTapAfterBoost = false
		boostArmTask = Task { @MainActor in
			try? await Task.sleep(nanoseconds: 350_000_000)
			guard !Task.isCancelled else { return }
			beginBoost()
		}
	}

	private func cancelBoostArm() {
		boostArmTask?.cancel()
		boostArmTask = nil
	}

	private func loadComments(reset: Bool) async {
		if reset {
			commentsLoading = true
			commentsPage = 1
		}
		defer { commentsLoading = false }
		do {
			let r = try await APIService.shared.fetchComments(videoId: page.videoId, page: 1)
			comments = r.items.uniquedPreservingOrder()
			commentsPage = max(r.page, 1)
			commentsPages = max(r.pages, 1)
			commentsTotal = r.total > 0 ? r.total : comments.count
			// 若服务端 pages 不准但本页已满，再探一页
			if commentsPages <= 1, r.items.count >= 20 {
				commentsPages = 2
			}
		} catch {
			flashCommentToast(error.localizedDescription)
		}
	}

	private func loadMoreComments() async {
		guard !commentsLoading, !commentsLoadingMore, commentsPage < commentsPages else { return }
		commentsLoadingMore = true
		defer { commentsLoadingMore = false }
		let next = commentsPage + 1
		do {
			let r = try await APIService.shared.fetchComments(videoId: page.videoId, page: next)
			if r.items.isEmpty {
				commentsPages = commentsPage
			} else {
				comments.mergeUnique(r.items)
				commentsPage = max(r.page, next)
				commentsPages = max(r.pages, commentsPages)
				if r.total > 0 { commentsTotal = r.total }
				else { commentsTotal = max(commentsTotal, comments.count) }
				if r.items.count >= 20, commentsPage >= commentsPages {
					commentsPages = commentsPage + 1
				}
			}
		} catch {
			flashCommentToast(error.localizedDescription)
		}
	}

	private func sendComment() async {
		guard SessionStore.shared.isLoggedIn else {
			flashCommentToast("请先登录后再评论")
			return
		}
		let t = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !t.isEmpty else { return }
		do {
			try await APIService.shared.postComment(videoId: page.videoId, text: t, ep: page.ep)
			commentText = ""
			await loadComments(reset: true)
			flashCommentToast("评论已发送")
		} catch {
			flashCommentToast(error.localizedDescription)
		}
	}

	private func flashCommentToast(_ text: String) {
		commentToast = text
		Task { @MainActor in
			try? await Task.sleep(nanoseconds: 1_800_000_000)
			if commentToast == text { commentToast = "" }
		}
	}

	private func cycleHoldSpeed() {
		let options: [Float] = [1.5, 2.0, 2.5, 3.0]
		if let i = options.firstIndex(where: { abs($0 - holdSpeed) < 0.01 }) {
			holdSpeed = options[(i + 1) % options.count]
		} else {
			holdSpeed = 2.0
		}
		if boosting {
			player?.rate = holdSpeed
		}
		UIImpactFeedbackGenerator(style: .light).impactOccurred()
	}

	private func beginBoost() {
		guard let player, isActive else { return }
		guard !boosting, !scrubbing, !scrubGate.active else { return }
		// 暂停时长按：记 0，松手后回到暂停；播放中则恢复原倍速
		previousRate = player.rate > 0.05 ? player.rate : (paused ? 0 : 1)
		paused = false
		boosting = true
		scrollLocked = true
		player.rate = holdSpeed
		UIImpactFeedbackGenerator(style: .medium).impactOccurred()
	}

	private func endBoost() {
		cancelBoostArm()
		guard boosting else {
			if !scrubbing { scrollLocked = false }
			return
		}
		boosting = false
		if !scrubbing { scrollLocked = false }
		guard let player else { return }
		if previousRate > 0.05 {
			player.rate = previousRate
			paused = false
		} else {
			player.pause()
			paused = true
		}
	}

	private func scheduleActive(_ active: Bool) {
		activeSwitchTask?.cancel()
		if active {
			// 立刻拉流，避免首帧空等
			activeSwitchTask = Task { await handleActive(true) }
		} else {
			// 短暂失活（插入集数 / 分页抖动）先别拆播放器，防止 loading 残灯
			activeSwitchTask = Task {
				try? await Task.sleep(nanoseconds: 180_000_000)
				guard !Task.isCancelled else { return }
				await handleActive(false)
			}
		}
	}

	private func handleActive(_ active: Bool) async {
		if active {
			paused = false
			tip = ""
			if player == nil {
				await startPlayback()
			} else {
				player?.isMuted = false
				loadingPlay = false
				if !boosting {
					player?.play()
				}
			}
		} else {
			endBoost()
			// 作废进行中的拉流，并清掉转圈；已有播放器则暂停回收
			generation += 1
			loadingPlay = false
			player?.pause()
			if let p = player {
				removeObservers(keepingPlayer: true)
				videoOutput = nil
				player = nil
				prefetcher.park(pageId: page.id, player: p)
			}
		}
	}

	private func startPlayback() async {
		generation += 1
		let gen = generation
		tip = ""
		if page.locked {
			loadingPlay = false
			tip = "该集暂不可播"
			return
		}
		loadingPlay = true
		defer {
			// 被更新的一代接管后，不要清掉新一代的 loading 状态
			if gen == generation {
				loadingPlay = false
			}
		}

		if let warmed = prefetcher.consume(pageId: page.id) {
			guard gen == generation else { return }
			attach(player: warmed, generation: gen)
			warmed.isMuted = false
			warmed.play()
			paused = false
			Task { await APIService.shared.syncHistory(videoId: page.videoId, ep: page.ep) }
			return
		}

		do {
			await AudioSession.activatePlaybackAsync()
			guard gen == generation else { return }
			let info = try await APIService.shared.fetchPlayback(videoId: page.videoId, ep: page.ep)
			guard gen == generation else { return }
			if let warmed = prefetcher.consume(pageId: page.id) {
				attach(player: warmed, generation: gen)
				warmed.isMuted = false
				warmed.play()
				paused = false
				Task { await APIService.shared.syncHistory(videoId: page.videoId, ep: page.ep) }
				return
			}
			guard let url = URL(string: info.url), !info.url.isEmpty else {
				tip = "播放地址无效"
				return
			}
			let p = ShortDramaPlayerFactory.make(url: url)
			attach(player: p, generation: gen)
			let ready = await ShortDramaPlayerFactory.waitReady(p.currentItem, timeout: 12)
			guard gen == generation else { return }
			if ready {
				p.isMuted = false
				p.play()
				paused = false
				Task { await APIService.shared.syncHistory(videoId: page.videoId, ep: page.ep) }
			} else {
				tearDownPlayer()
				tip = "加载失败，上滑换下一条"
			}
		} catch {
			guard gen == generation else { return }
			tip = "播放失败，上滑换下一条"
		}
	}

	private func attach(player p: AVPlayer, generation gen: Int) {
		guard gen == generation else { return }
		removeObservers(keepingPlayer: false)
		endObserver = NotificationCenter.default.addObserver(
			forName: .AVPlayerItemDidPlayToEndTime,
			object: p.currentItem,
			queue: .main
		) { [weak p] _ in
			Task { @MainActor in
				// 有下一页（含同剧下一集）则自动下滑，否则循环本集
				if onRequestNext() { return }
				await p?.seek(to: .zero)
				p?.play()
			}
		}
		let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
		let gate = scrubGate
		timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak p] time in
			guard let p, let item = p.currentItem else { return }
			let dur = item.duration.seconds
			guard dur.isFinite, dur > 0 else { return }
			if duration <= 0 || abs(duration - dur) > 0.5 {
				duration = dur
			}
			// 拖动时不要被播放进度顶回去
			if gate.active { return }
			progress = min(1, max(0, time.seconds / dur))
		}
		player = p
		progress = 0
		if let item = p.currentItem {
			ensureVideoOutput(on: item)
			let d = item.duration.seconds
			if d.isFinite, d > 0 {
				duration = d
			} else if self.page.durationSec > 0 {
				duration = Double(self.page.durationSec)
			}
		}
		// HLS 时长可能稍后才就绪
		Task { @MainActor in
			for _ in 0..<20 {
				try? await Task.sleep(nanoseconds: 200_000_000)
				guard let item = p.currentItem else { return }
				let d = item.duration.seconds
				if d.isFinite, d > 0 {
					duration = d
					return
				}
			}
		}
	}

	private func removeObservers(keepingPlayer: Bool) {
		if let obs = endObserver {
			NotificationCenter.default.removeObserver(obs)
			endObserver = nil
		}
		if let token = timeObserver, let p = player {
			p.removeTimeObserver(token)
			timeObserver = nil
		} else {
			timeObserver = nil
		}
		_ = keepingPlayer
	}

	private func parkOrTearDown() {
		generation += 1
		loadingPlay = false
		endBoost()
		finishScrub()
		removeObservers(keepingPlayer: true)
		if let p = player {
			// 输出留在 item 上，下次 consume 再挂回引用
			videoOutput = nil
			player = nil
			prefetcher.park(pageId: page.id, player: p)
		}
		paused = false
		progress = 0
		duration = 0
		if !boosting { scrollLocked = false }
	}

	private func tearDownPlayer() {
		generation += 1
		loadingPlay = false
		endBoost()
		finishScrub()
		removeObservers(keepingPlayer: true)
		clearVideoOutput(from: player)
		player?.pause()
		player?.replaceCurrentItem(with: nil)
		player = nil
		paused = false
		progress = 0
		duration = 0
		if !boosting { scrollLocked = false }
	}
}

// MARK: - Comments sheet

private struct ShortDramaCommentsSheet: View {
	@Binding var comments: [CommentItem]
	@Binding var commentText: String
	@Binding var loading: Bool
	@Binding var loadingMore: Bool
	@Binding var toast: String
	var total: Int
	var hasMore: Bool
	var onAppearLoad: () -> Void
	var onLoadMore: () -> Void
	var onSend: () -> Void

	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				if !toast.isEmpty {
					Text(toast)
						.font(.caption.weight(.semibold))
						.foregroundStyle(.white)
						.padding(.horizontal, 12)
						.padding(.vertical, 8)
						.frame(maxWidth: .infinity)
						.background(HGTheme.accent.opacity(0.9))
						.transition(.move(edge: .top).combined(with: .opacity))
				}

				HStack(spacing: 10) {
					TextField("说点什么…", text: $commentText)
						.padding(12)
						.background(HGTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
						.foregroundStyle(HGTheme.textPrimary)
					Button(action: onSend) {
						Text("发送")
							.font(.subheadline.weight(.semibold))
							.frame(minWidth: 56, minHeight: 44)
					}
					.hgProminentButton()
					.tint(HGTheme.accent)
					.disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 12)

				Divider().background(HGTheme.glassStroke)

				Group {
					if loading && comments.isEmpty {
						ProgressView()
							.tint(HGTheme.accent)
							.frame(maxWidth: .infinity, maxHeight: .infinity)
					} else if comments.isEmpty {
						Text("还没有评论，来抢沙发吧")
							.font(.subheadline)
							.foregroundStyle(HGTheme.textMuted)
							.frame(maxWidth: .infinity, maxHeight: .infinity)
					} else {
						ScrollView {
							LazyVStack(alignment: .leading, spacing: 0) {
								ForEach(Array(comments.enumerated()), id: \.element.id) { index, c in
									VStack(alignment: .leading, spacing: 6) {
										HStack {
											Text(c.userName.isEmpty ? "用户" : c.userName)
												.font(.caption.weight(.semibold))
												.foregroundStyle(HGTheme.accent)
											if c.ep > 0 {
												Text("第\(c.ep)集")
													.font(.caption2.weight(.semibold))
													.foregroundStyle(HGTheme.textMuted)
											}
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
									.onAppear {
										if index >= comments.count - 3 {
											onLoadMore()
										}
									}

									if index < comments.count - 1 {
										Divider().background(HGTheme.glassStroke).padding(.leading, 16)
									}
								}

								if loadingMore {
									ProgressView()
										.tint(HGTheme.accent)
										.frame(maxWidth: .infinity)
										.padding(.vertical, 16)
								} else if hasMore {
									Button("加载更多") { onLoadMore() }
										.font(.subheadline.weight(.semibold))
										.foregroundStyle(HGTheme.accent)
										.frame(maxWidth: .infinity)
										.padding(.vertical, 16)
								} else if comments.count > 0 {
									Text(total > comments.count
										 ? "已加载 \(comments.count)/\(total)"
										 : "已加载全部 \(comments.count) 条")
										.font(.caption)
										.foregroundStyle(HGTheme.textMuted)
										.frame(maxWidth: .infinity)
										.padding(.vertical, 16)
								}
							}
							.padding(.bottom, 24)
						}
					}
				}
			}
			.background(HGTheme.bg)
			.navigationTitle(total > 0 ? "评论 (\(total))" : "评论")
			.navigationBarTitleDisplayMode(.inline)
			.onAppear(perform: onAppearLoad)
		}
	}
}

private extension UIImage {
	static func fromPixelBuffer(_ buffer: CVPixelBuffer) -> UIImage? {
		let w = CVPixelBufferGetWidth(buffer)
		let h = CVPixelBufferGetHeight(buffer)
		guard w > 1, h > 1 else { return nil }
		let ci = CIImage(cvPixelBuffer: buffer)
		guard ci.extent.width > 1, ci.extent.height > 1 else { return nil }
		let context = CIContext(options: nil)
		guard let cg = context.createCGImage(ci, from: ci.extent) else { return nil }
		return UIImage(cgImage: cg)
	}
}

private final class ScrubGate {
	var active = false
}

// MARK: - Player layer

private struct HGPlayerLayerView: UIViewRepresentable {
	let player: AVPlayer

	func makeUIView(context: Context) -> PlayerLayerView {
		let v = PlayerLayerView()
		v.playerLayer.videoGravity = .resizeAspectFill
		v.attach(player)
		return v
	}

	func updateUIView(_ uiView: PlayerLayerView, context: Context) {
		uiView.attach(player)
	}

	final class PlayerLayerView: UIView {
		override class var layerClass: AnyClass { AVPlayerLayer.self }
		var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
		private weak var pendingPlayer: AVPlayer?

		override init(frame: CGRect) {
			super.init(frame: frame)
			clipsToBounds = true
			isOpaque = true
			backgroundColor = .black
		}

		required init?(coder: NSCoder) {
			super.init(coder: coder)
			clipsToBounds = true
			isOpaque = true
			backgroundColor = .black
		}

		func attach(_ player: AVPlayer) {
			pendingPlayer = player
			// bounds 为 0 时先不挂 player，避免系统创建 宽×0 image slot
			if bounds.width > 1, bounds.height > 1 {
				if playerLayer.player !== player {
					playerLayer.player = player
				}
			} else if playerLayer.player !== nil {
				playerLayer.player = nil
			}
		}

		override func layoutSubviews() {
			super.layoutSubviews()
			if bounds.width > 1, bounds.height > 1, let pendingPlayer {
				if playerLayer.player !== pendingPlayer {
					playerLayer.player = pendingPlayer
				}
			}
		}
	}
}
