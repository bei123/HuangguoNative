import Foundation

enum EdgeScope: String {
	case publicScope = "public"
	case dynamic = "dynamic"
	case playback = "playback"
	case user = "user"
}

actor APIService {
	static let shared = APIService()

	private let base = "https://huangguoai.com"
	private let picCDN = "https://pic.qnlycc.cn"
	/// 分类探测较慢，缓存后避免每次进发现页都全量探测
	private var cachedVideoCategories: [CategoryItem]?

	func fetchHome() async throws -> HomeData {
		let raw = try await edge(.dynamic, "GET", "/api/home")
		guard let data = raw["data"] as? [String: Any] else { throw APIError.empty("home") }
		return parseHome(data)
	}

	func fetchLatest(page: Int) async throws -> PageResult<VideoCard> {
		let raw = try await edge(.publicScope, "GET", "/api/home/latest?page=\(page)")
		guard let data = raw["data"] as? [String: Any] else { throw APIError.empty("latest") }
		return parseCardPage(data)
	}

	/// 已知已下线路由（目录接口仍会返回）
	private static let offlineCategoryRoutes: Set<String> = [
		"ai-mogai",
		"ai-huanlian",
	]

	func fetchCategories(forceRefresh: Bool = false) async throws -> [CategoryItem] {
		if !forceRefresh, let cachedVideoCategories, !cachedVideoCategories.isEmpty {
			return cachedVideoCategories.filter { !Self.isRetiredCategory($0) }
		}
		let raw = try await edge(.publicScope, "GET", "/api/site/categories/video")
		guard let data = raw["data"] as? [String: Any] else { return [] }
		let listed = APIJSON.arr(data["items"]).compactMap { item -> CategoryItem? in
			guard let d = item as? [String: Any] else { return nil }
			let route = APIJSON.string(d, "route")
			guard !route.isEmpty else { return nil }
			let id = APIJSON.string(d, "id")
			return CategoryItem(
				// 部分条目 id 为空，切换标签时必须能区分
				id: id.isEmpty ? route : id,
				name: APIJSON.string(d, "name"),
				route: route
			)
		}
		.filter { !Self.isRetiredCategory($0) }

		// 再探测列表接口，剔除探测确认下线的
		let filtered = await filterOnlineCategories(listed)
		// 只回退到「已去掉硬编码下线项」的目录，绝不把 AI魔改/换脸加回来
		let result = filtered.isEmpty ? listed : filtered
		if !result.isEmpty {
			cachedVideoCategories = result
		}
		return result
	}

	func fetchCategoryVideos(route: String, page: Int, size: Int = 20) async throws -> PageResult<VideoCard> {
		if Self.isRetiredRoute(route) {
			throw APIError.biz("分类已下线")
		}
		let enc = route.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? route
		let raw = try await edge(.publicScope, "GET", "/api/videos/category/\(enc)?page=\(page)&size=\(size)")
		try rejectOfflineCategory(raw, route: route)
		guard let data = raw["data"] as? [String: Any] else { throw APIError.empty("category") }
		return parseCardPage(data)
	}

	static func isRetiredCategory(_ item: CategoryItem) -> Bool {
		isRetiredRoute(item.route) || isRetiredName(item.name)
	}

	static func isRetiredRoute(_ route: String) -> Bool {
		let r = route.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		if offlineCategoryRoutes.contains(r) { return true }
		return r.contains("mogai") || r.contains("huanlian")
	}

	static func isRetiredName(_ name: String) -> Bool {
		name.contains("AI魔改") || name.contains("AI换脸") || name.contains("魔改") && name.contains("AI") || name.contains("换脸") && name.contains("AI")
	}

	/// 并行探测；明确下线剔除，网络抖动保留（硬编码下线项已在上游去掉）。
	private func filterOnlineCategories(_ items: [CategoryItem]) async -> [CategoryItem] {
		await withTaskGroup(of: (Int, CategoryItem?).self) { group in
			for (idx, item) in items.enumerated() {
				group.addTask {
					let state = await self.categoryOnlineState(route: item.route)
					switch state {
					case .online, .unknown:
						return (idx, item)
					case .offline:
						return (idx, nil)
					}
				}
			}
			var kept: [(Int, CategoryItem)] = []
			for await (idx, item) in group {
				if let item { kept.append((idx, item)) }
			}
			return kept.sorted { $0.0 < $1.0 }.map(\.1)
		}
	}

	private enum CategoryOnlineState {
		case online, offline, unknown
	}

	private func categoryOnlineState(route: String) async -> CategoryOnlineState {
		if Task.isCancelled { return .unknown }
		let enc = route.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? route
		do {
			let raw = try await edge(.publicScope, "GET", "/api/videos/category/\(enc)?page=1&size=1")
			try rejectOfflineCategory(raw, route: route)
			return raw["data"] is [String: Any] ? .online : .unknown
		} catch is CancellationError {
			return .unknown
		} catch let err as APIError {
			if case .biz = err { return .offline }
			return .unknown
		} catch {
			return .unknown
		}
	}

	private func rejectOfflineCategory(_ raw: [String: Any], route: String) throws {
		let msg = APIJSON.string(raw, "msg", "message", "error")
		if msg.contains("下线") || msg.contains("不存在") || msg.lowercased().contains("not found") {
			throw APIError.biz(msg.isEmpty ? "分类已下线" : msg)
		}
		if raw["status"] != nil {
			let status = APIJSON.int(raw, "status")
			if status == 0 || status == 404 {
				throw APIError.biz(msg.isEmpty ? "分类已下线（\(route)）" : msg)
			}
		}
	}

	func fetchRanks(type: String) async throws -> [RankItem] {
		let enc = type.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? type
		let raw = try await edge(.publicScope, "GET", "/api/ranks/\(enc)")
		guard let data = raw["data"] as? [String: Any] else { return [] }
		return APIJSON.arr(data["items"]).compactMap { item -> RankItem? in
			guard let d = item as? [String: Any] else { return nil }
			return RankItem(
				rank: APIJSON.int(d, "rank"),
				videoId: APIJSON.string(d, "video_id", "id"),
				title: APIJSON.string(d, "title"),
				cover: absoluteImage(APIJSON.string(d, "cover")),
				cateName: APIJSON.string(d, "cate_name"),
				episodeCount: APIJSON.int(d, "episode_count"),
				isFinished: APIJSON.bool(d, "is_finished"),
				score: APIJSON.double(d, "score"),
				tags: stringArray(d["tags"]),
				metricLabel: APIJSON.string(d, "metric_label"),
				metricValue: APIJSON.int(d, "metric_value")
			)
		}
	}

	func fetchHotWords() async throws -> [String] {
		let raw = try await edge(.publicScope, "GET", "/api/search/hot")
		guard let data = raw["data"] as? [String: Any] else { return [] }
		return APIJSON.arr(data["items"]).compactMap { item in
			guard let d = item as? [String: Any] else { return nil }
			let w = APIJSON.string(d, "word")
			return w.isEmpty ? nil : w
		}
	}

	func fetchSearch(q: String, page: Int) async throws -> PageResult<VideoCard> {
		let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
		let raw = try await edge(.dynamic, "GET", "/api/search?q=\(enc)&page=\(page)")
		guard let data = raw["data"] as? [String: Any] else { throw APIError.empty("search") }
		return parseSearchPage(data)
	}

	func fetchVideoDetail(id: String) async throws -> VideoDetail {
		let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
		let raw = try await edge(.dynamic, "GET", "/api/videos/\(enc)")
		guard let data = raw["data"] as? [String: Any] else { throw APIError.empty("detail") }
		return parseDetail(data)
	}

	func fetchPlayback(videoId: String, ep: Int) async throws -> PlaybackInfo {
		let enc = videoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? videoId
		let path = "/api/videos/\(enc)/episodes/\(ep)/playback"
		let raw = try await edge(.playback, "POST", path, body: "{}")
		guard let data = raw["data"] as? [String: Any] else { throw APIError.empty("playback") }
		let info = parsePlayback(data)
		if info.url.isEmpty { throw APIError.empty("playback url") }
		return info
	}

	func fetchTopics(page: Int) async throws -> PageResult<TopicLite> {
		let raw = try await edge(.publicScope, "GET", "/api/topics?page=\(page)")
		guard let data = raw["data"] as? [String: Any] else { throw APIError.empty("topics") }
		let items = APIJSON.arr(data["items"]).compactMap { parseTopicLite($0) }
		let pag = data["pagination"] as? [String: Any]
		return PageResult(
			items: items,
			page: APIJSON.int(pag, "page"),
			pages: APIJSON.int(pag, "pages"),
			total: APIJSON.int(pag, "total")
		)
	}

	// MARK: - edge

	private func edge(_ scope: EdgeScope, _ method: String, _ path: String, body: String = "", auth: String = "") async throws -> [String: Any] {
		let json = try await EdgeClient.shared.edgeRequest(
			scope: scope.rawValue,
			method: method,
			path: path,
			bodyJson: body,
			authToken: auth
		)
		guard let data = json.data(using: .utf8),
			  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw APIError.decode
		}
		return obj
	}

	// MARK: - parse

	private func parseHome(_ data: [String: Any]) -> HomeData {
		HomeData(
			banners: APIJSON.arr(data["banners"]).compactMap { item in
				guard let d = item as? [String: Any] else { return nil }
				return HomeBanner(
					id: APIJSON.string(d, "id"),
					videoId: APIJSON.string(d, "video_id"),
					title: APIJSON.string(d, "title"),
					image: absoluteImage(APIJSON.string(d, "image", "cover")),
					score: APIJSON.double(d, "score"),
					desc: APIJSON.string(d, "desc")
				)
			},
			featured: APIJSON.arr(data["featured"]).compactMap { parseCard($0) }.uniquedPreservingOrder(),
			latest: APIJSON.arr(data["latest"]).compactMap { parseCard($0) }.uniquedPreservingOrder(),
			cateRec: APIJSON.arr(data["cate_rec"]).compactMap { item in
				guard let d = item as? [String: Any] else { return nil }
				return CateRec(
					cateId: APIJSON.string(d, "cate_id"),
					cateName: APIJSON.string(d, "cate_name"),
					videos: APIJSON.arr(d["videos"]).compactMap { parseCard($0) }.uniquedPreservingOrder()
				)
			},
			topicRec: APIJSON.arr(data["topic_rec"]).compactMap { parseTopicLite($0) }.uniquedPreservingOrder()
		)
	}

	private func parseCardPage(_ data: [String: Any]) -> PageResult<VideoCard> {
		let items = APIJSON.arr(data["items"]).compactMap { parseCard($0) }.uniquedPreservingOrder()
		let pag = data["pagination"] as? [String: Any]
		return PageResult(
			items: items,
			page: APIJSON.int(pag ?? data, "page"),
			pages: max(APIJSON.int(pag ?? data, "pages"), 1),
			total: APIJSON.int(pag ?? data, "total")
		)
	}

	private func parseSearchPage(_ data: [String: Any]) -> PageResult<VideoCard> {
		let items = APIJSON.arr(data["items"]).compactMap { parseCard($0) }.uniquedPreservingOrder()
		let pag = data["pagination"] as? [String: Any]
		return PageResult(
			items: items,
			page: APIJSON.int(pag, "page"),
			pages: max(APIJSON.int(pag, "pages"), 1),
			total: APIJSON.int(pag, "total")
		)
	}

	private func parseCard(_ any: Any?) -> VideoCard? {
		guard let d = any as? [String: Any] else { return nil }
		let id = APIJSON.string(d, "id", "video_id")
		if id.isEmpty { return nil }
		return VideoCard(
			id: id,
			title: APIJSON.string(d, "title"),
			cover: absoluteImage(APIJSON.string(d, "cover")),
			score: APIJSON.double(d, "score"),
			hot: APIJSON.int(d, "hot"),
			episodeCount: APIJSON.int(d, "episode_count"),
			isFinished: APIJSON.bool(d, "is_finished"),
			tags: stringArray(d["tags"]),
			desc: APIJSON.string(d, "desc", "description"),
			badge: APIJSON.string(d, "badge"),
			durationSec: APIJSON.int(d, "duration"),
			cateId: APIJSON.string(d, "cate_id")
		)
	}

	private func parseTopicLite(_ any: Any?) -> TopicLite? {
		guard let d = any as? [String: Any] else { return nil }
		let id = APIJSON.string(d, "id")
		if id.isEmpty { return nil }
		return TopicLite(
			id: id,
			title: APIJSON.string(d, "title"),
			slug: APIJSON.string(d, "slug"),
			cover: absoluteImage(APIJSON.string(d, "cover")),
			intro: APIJSON.string(d, "intro"),
			videoCount: APIJSON.int(d, "video_count")
		)
	}

	private func parseDetail(_ d: [String: Any]) -> VideoDetail {
		let counts = d["counts"] as? [String: Any]
		let author = d["author"] as? [String: Any]
		let interaction = d["interaction"] as? [String: Any]
		let episodes = APIJSON.arr(d["episodes"]).compactMap { item -> EpisodeItem? in
			guard let e = item as? [String: Any] else { return nil }
			return EpisodeItem(
				epNum: APIJSON.int(e, "ep_num"),
				title: APIJSON.string(e, "title"),
				durationSec: APIJSON.int(e, "duration"),
				locked: APIJSON.int(e, "status") != 1
			)
		}
		return VideoDetail(
			id: APIJSON.string(d, "id"),
			title: APIJSON.string(d, "title"),
			description: APIJSON.string(d, "description", "desc"),
			cover: absoluteImage(APIJSON.string(d, "cover")),
			score: APIJSON.double(d, "score"),
			episodeCount: APIJSON.int(d, "episode_count", "total_episodes"),
			isFinished: APIJSON.bool(d, "is_finished"),
			tags: stringArray(d["tags"]),
			hot: APIJSON.int(counts, "hot"),
			like: APIJSON.int(counts, "like"),
			collect: APIJSON.int(counts, "collect"),
			authorId: APIJSON.int(author, "id"),
			authorName: APIJSON.string(author, "name"),
			episodes: episodes,
			liked: APIJSON.bool(interaction, "liked"),
			collected: APIJSON.bool(interaction, "collected")
		)
	}

	private func parsePlayback(_ d: [String: Any]) -> PlaybackInfo {
		let streams = d["streams"] as? [String: Any]
		let main = APIJSON.string(streams, "main", "preview")
		let hevc = APIJSON.string(streams, "hevc")
		let url = main.isEmpty ? hevc : main
		return PlaybackInfo(url: url, hevcURL: hevc, expiresAt: APIJSON.int(d, "timestamp"))
	}

	private func absoluteImage(_ raw: String) -> String {
		if raw.isEmpty { return "" }
		if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return raw }
		if raw.hasPrefix("/") { return picCDN + raw }
		return picCDN + "/" + raw
	}

	private func stringArray(_ any: Any?) -> [String] {
		APIJSON.arr(any).compactMap { $0 as? String }
	}
}

enum APIError: LocalizedError {
	case empty(String)
	case decode
	case unauthorized
	case biz(String)

	var errorDescription: String? {
		switch self {
		case .empty(let s): return "空数据: \(s)"
		case .decode: return "JSON 解析失败"
		case .unauthorized: return "未登录"
		case .biz(let s): return s
		}
	}
}
