import Foundation

extension APIService {
	private var token: String { SessionStore.shared.token }

	private func requireOK(_ raw: [String: Any], _ label: String) throws {
		// 仅当明确带了 status 且为 0/失败码时判失败；缺省 status 但有 data 时放行
		guard raw["status"] != nil else { return }
		let status = APIJSON.int(raw, "status")
		if status == 0 || status == 401 || status == 429 {
			let msg = APIJSON.string(raw, "msg")
			if msg.contains("unauthorized") || msg.lowercased().contains("token") || status == 401 {
				throw APIError.unauthorized
			}
			throw APIError.business(msg.isEmpty ? "\(label) 失败" : msg)
		}
	}

	private func userEdge(_ method: String, _ path: String, body: String = "") async throws -> [String: Any] {
		let t = token
		if t.isEmpty { throw APIError.unauthorized }
		let raw = try await edgePublic(method, path, body: body, scope: .user, auth: t)
		try requireOK(raw, path)
		return raw
	}

	/// 暴露给 extension：复用主文件 edge（同 module actor）
	func edgePublic(_ method: String, _ path: String, body: String = "", scope: EdgeScope, auth: String = "") async throws -> [String: Any] {
		try await edgeCall(scope, method, path, body: body, auth: auth)
	}

	// MARK: Account

	func login(username: String, password: String) async throws -> HgUser {
		let body = #"{"username":"\#(jsonEsc(username))","password":"\#(jsonEsc(password))"}"#
		let raw = try await edgeCall(.user, "POST", "/api/account/loginByPassword", body: body, auth: "")
		return try await applyAuthResponse(raw, label: "login")
	}

	func register(username: String, password: String, confirm: String) async throws -> HgUser {
		let body = #"{"username":"\#(jsonEsc(username))","password":"\#(jsonEsc(password))","confirm_password":"\#(jsonEsc(confirm))"}"#
		let raw = try await edgeCall(.user, "POST", "/api/account/registerByPassword", body: body, auth: "")
		return try await applyAuthResponse(raw, label: "register")
	}

	private func applyAuthResponse(_ raw: [String: Any], label: String) async throws -> HgUser {
		try requireOK(raw, label)
		guard let data = raw["data"] as? [String: Any] else {
			let msg = APIJSON.string(raw, "msg")
			throw APIError.business(msg.isEmpty ? "\(label) 无返回数据" : msg)
		}
		let tok = APIJSON.string(data, "token")
		guard !tok.isEmpty, let userObj = data["user"] as? [String: Any] else {
			let msg = APIJSON.string(raw, "msg")
			throw APIError.business(msg.isEmpty ? "\(label) 未返回 token" : msg)
		}
		let user = parseUser(userObj)
		await MainActor.run {
			SessionStore.shared.applyLogin(token: tok, user: user)
		}
		return user
	}

	func fetchMe() async throws -> HgUser {
		let raw = try await userEdge("GET", "/api/account/me")
		guard let data = raw["data"] as? [String: Any] else { throw APIError.empty("me") }
		let user = parseUser(data)
		await MainActor.run { SessionStore.shared.updateUser(user) }
		return user
	}

	func logoutRemote() async {
		guard !token.isEmpty else { return }
		_ = try? await userEdge("POST", "/api/account/logout", body: "{}")
	}

	func updateProfile(nickname: String?, sign: String?, desc: String?, avatarColor: String?) async throws -> HgUser {
		var obj: [String: String] = [:]
		if let nickname { obj["nickname"] = nickname }
		if let sign { obj["sign"] = sign }
		if let desc { obj["desc"] = desc }
		if let avatarColor { obj["avatar_color"] = avatarColor }
		let data = try JSONSerialization.data(withJSONObject: obj)
		let body = String(data: data, encoding: .utf8) ?? "{}"
		let raw = try await userEdge("PATCH", "/api/account/profile", body: body)
		guard let d = raw["data"] as? [String: Any] else { throw APIError.empty("profile") }
		let user = parseUser(d)
		await MainActor.run { SessionStore.shared.updateUser(user) }
		return user
	}

	func changePassword(old: String, new: String, confirm: String) async throws {
		let body = #"{"old_password":"\#(jsonEsc(old))","new_password":"\#(jsonEsc(new))","confirm_password":"\#(jsonEsc(confirm))"}"#
		let raw = try await userEdge("POST", "/api/account/password", body: body)
		if let data = raw["data"] as? [String: Any] {
			let tok = APIJSON.string(data, "token")
			if !tok.isEmpty {
				await MainActor.run { SessionStore.shared.token = tok }
			}
		}
	}

	// MARK: Interact

	func collectVideo(id: String, ep: Int, on: Bool) async throws -> Bool {
		let path = "/api/videos/\(enc(id))/collect?ep=\(max(ep, 1))"
		let raw = try await userEdge(on ? "POST" : "DELETE", path, body: "{}")
		if let data = raw["data"] as? [String: Any], data["collected"] != nil {
			return APIJSON.bool(data, "collected")
		}
		return on
	}

	func likeVideo(id: String, ep: Int, on: Bool) async throws -> Bool {
		let path = "/api/videos/\(enc(id))/like?ep=\(max(ep, 1))"
		let raw = try await userEdge(on ? "POST" : "DELETE", path, body: "{}")
		if let data = raw["data"] as? [String: Any], data["liked"] != nil {
			return APIJSON.bool(data, "liked")
		}
		return on
	}

	func followUser(uid: Int, on: Bool) async throws -> Bool {
		let path = "/api/users/\(uid)/follow"
		let raw = try await userEdge(on ? "POST" : "DELETE", path, body: on ? "{}" : "")
		let data = raw["data"] as? [String: Any]
		return APIJSON.bool(data, "following") || on
	}

	func rateVideo(id: String, score: Int) async throws -> Int {
		let body = #"{"score":\#(score)}"#
		let raw = try await userEdge("POST", "/api/videos/\(enc(id))/rating", body: body)
		let data = raw["data"] as? [String: Any]
		let my = APIJSON.int(data, "my")
		return my > 0 ? my : score
	}

	func fetchMyRating(videoId: String, ep: Int = 1) async throws -> Int {
		let raw = try await userEdge("GET", "/api/videos/\(enc(videoId))/interaction-state?ep=\(max(ep, 1))")
		guard let data = raw["data"] as? [String: Any] else { return 0 }
		let rating = data["rating"] as? [String: Any]
		return APIJSON.int(rating, "my")
	}

	func syncHistory(videoId: String, ep: Int) async {
		guard !token.isEmpty else { return }
		let vid = Int(videoId) ?? 0
		guard vid > 0, ep > 0 else { return }
		let single = #"{"video_id":\#(vid),"ep":\#(ep)}"#
		let sync = #"{"items":[\#(single)]}"#
		do {
			_ = try await userEdge("POST", "/api/users/me/history", body: single)
		} catch {
			_ = try? await userEdge("POST", "/api/users/me/history/sync", body: sync)
		}
	}

	func visitVideo(id: String) async {
		_ = try? await edgeCall(.dynamic, "POST", "/api/videos/\(enc(id))/visit", body: "{}", auth: "")
	}

	func fetchComments(videoId: String, page: Int) async throws -> PageResult<CommentItem> {
		let raw = try await edgeCall(.dynamic, "GET", "/api/videos/\(enc(videoId))/comments?page=\(page)&size=50", body: "", auth: "")
		guard let data = raw["data"] as? [String: Any] else { return PageResult(items: [], page: 1, pages: 1, total: 0) }
		let rawItems: [Any] = {
			let a = APIJSON.arr(data["items"])
			if !a.isEmpty { return a }
			let b = APIJSON.arr(data["list"])
			if !b.isEmpty { return b }
			return APIJSON.arr(data["comments"])
		}()
		let items = rawItems.enumerated().compactMap { idx, any in parseComment(any, fallbackIndex: idx) }
		let pag = data["pagination"] as? [String: Any]
		var pages = APIJSON.int(pag, "pages")
		let total = APIJSON.int(pag, "total")
		let cur = max(APIJSON.int(pag, "page"), page)
		if pages <= 0, total > 0, !items.isEmpty {
			pages = max(1, Int(ceil(Double(total) / Double(max(items.count, 1)))))
		}
		return PageResult(items: items, page: cur, pages: max(pages, 1), total: total)
	}

	func postComment(videoId: String, text: String, ep: Int) async throws {
		let body = #"{"text":"\#(jsonEsc(text))","ep":\#(ep)}"#
		_ = try await userEdge("POST", "/api/videos/\(enc(videoId))/comments", body: body)
	}

	func fetchRelated(videoId: String) async throws -> [VideoCard] {
		let raw = try await edgeCall(.dynamic, "GET", "/api/videos/\(enc(videoId))/related?page=1", body: "", auth: "")
		if let data = raw["data"] as? [String: Any] {
			return APIJSON.arr(data["items"]).compactMap { parseCardPublic($0) }.uniquedPreservingOrder()
		}
		return []
	}

	// MARK: Me lists

	func fetchMyHistory(page: Int) async throws -> PageResult<HistoryItem> {
		let raw = try await userEdge("GET", "/api/users/me/history?page=\(page)&size=20")
		return parseHistoryPage(raw["data"] as? [String: Any], page: page)
	}

	func fetchMyCollects(page: Int) async throws -> PageResult<CollectItem> {
		let raw = try await userEdge("GET", "/api/users/me/collects?page=\(page)&size=20")
		guard let data = raw["data"] as? [String: Any] else { return emptyPage() }
		let items = APIJSON.arr(data["items"]).compactMap { any -> CollectItem? in
			guard let d = any as? [String: Any] else { return nil }
			return CollectItem(
				id: APIJSON.int(d, "id"),
				videoId: APIJSON.string(d, "video_id", "id"),
				title: APIJSON.string(d, "title"),
				cover: absImg(APIJSON.string(d, "cover")),
				lastEp: APIJSON.int(d, "last_ep"),
				categoryName: APIJSON.string(d, "category_name")
			)
		}
		let pag = data["pagination"] as? [String: Any]
		return PageResult(items: items, page: APIJSON.int(pag, "page"), pages: max(APIJSON.int(pag, "pages"), 1), total: APIJSON.int(pag, "total"))
	}

	func fetchMyLikes(page: Int) async throws -> PageResult<CollectItem> {
		let raw = try await userEdge("GET", "/api/users/me/likes?page=\(page)&size=20")
		guard let data = raw["data"] as? [String: Any] else { return emptyPage() }
		let items = APIJSON.arr(data["items"]).compactMap { any -> CollectItem? in
			guard let d = any as? [String: Any] else { return nil }
			return CollectItem(
				id: APIJSON.int(d, "id"),
				videoId: APIJSON.string(d, "video_id", "id"),
				title: APIJSON.string(d, "title"),
				cover: absImg(APIJSON.string(d, "cover")),
				lastEp: APIJSON.int(d, "last_ep", "ep"),
				categoryName: APIJSON.string(d, "category_name")
			)
		}
		let pag = data["pagination"] as? [String: Any]
		return PageResult(items: items, page: APIJSON.int(pag, "page"), pages: max(APIJSON.int(pag, "pages"), 1), total: APIJSON.int(pag, "total"))
	}

	func fetchMyFollows(page: Int) async throws -> PageResult<FollowUser> {
		let raw = try await userEdge("GET", "/api/users/me/follows?page=\(page)&size=20")
		guard let data = raw["data"] as? [String: Any] else { return PageResult(items: [], page: 1, pages: 1, total: 0) }
		let items = APIJSON.arr(data["items"]).compactMap { any -> FollowUser? in
			guard let d = any as? [String: Any] else { return nil }
			return FollowUser(
				id: APIJSON.int(d, "id", "user_id"),
				nickname: APIJSON.string(d, "nickname", "name"),
				avatar: absImg(APIJSON.string(d, "avatar")),
				sign: APIJSON.string(d, "sign")
			)
		}
		let pag = data["pagination"] as? [String: Any]
		return PageResult(items: items, page: APIJSON.int(pag, "page"), pages: max(APIJSON.int(pag, "pages"), 1), total: APIJSON.int(pag, "total"))
	}

	func deleteHistory(ids: [Int]) async throws {
		let arr = ids.map(String.init).joined(separator: ",")
		let body = #"{"ids":[\#(arr)]}"#
		_ = try await userEdge("POST", "/api/users/me/history/delete", body: body)
	}

	func fetchMessages(page: Int) async throws -> PageResult<MessageItem> {
		let raw = try await userEdge("GET", "/api/users/me/messages?page=\(page)&size=20")
		guard let data = raw["data"] as? [String: Any] else { return PageResult(items: [], page: 1, pages: 1, total: 0) }
		let items = APIJSON.arr(data["items"]).compactMap { any -> MessageItem? in
			guard let d = any as? [String: Any] else { return nil }
			return MessageItem(
				id: APIJSON.int(d, "id"),
				title: APIJSON.string(d, "title"),
				content: APIJSON.string(d, "content", "body", "text"),
				createdAt: APIJSON.string(d, "created_at"),
				read: APIJSON.bool(d, "read", "is_read")
			)
		}
		let pag = data["pagination"] as? [String: Any]
		return PageResult(items: items, page: APIJSON.int(pag, "page"), pages: max(APIJSON.int(pag, "pages"), 1), total: APIJSON.int(pag, "total"))
	}

	func fetchUnreadCount() async throws -> Int {
		let raw = try await userEdge("GET", "/api/users/me/messages/unread-count")
		if let data = raw["data"] as? [String: Any] {
			return APIJSON.int(data, "unread")
		}
		return APIJSON.int(raw, "unread")
	}

	func readAllMessages() async throws {
		_ = try await userEdge("POST", "/api/users/me/messages/read-all", body: "{}")
	}

	// MARK: Author / Topic detail / Posts / Feed / Sort

	func fetchAuthor(id: Int) async throws -> AuthorProfile {
		async let uRaw = edgeCall(.dynamic, "GET", "/api/users/\(id)", body: "", auth: "")
		async let sRaw = edgeCall(.publicScope, "GET", "/api/users/\(id)/stats", body: "", auth: "")
		let user = try await uRaw
		let stats = try await sRaw
		guard let data = user["data"] as? [String: Any] else { throw APIError.empty("author") }
		let st = stats["data"] as? [String: Any]
		let counts = data["counts"] as? [String: Any]
		return AuthorProfile(
			id: APIJSON.int(data, "id"),
			nickname: APIJSON.string(data, "nickname", "name"),
			avatar: absImg(APIJSON.string(data, "avatar")),
			avatarColor: APIJSON.string(data, "avatar_color"),
			sign: APIJSON.string(data, "sign"),
			desc: APIJSON.string(data, "desc"),
			likeCount: APIJSON.int(st, "like_count") > 0 ? APIJSON.int(st, "like_count") : APIJSON.int(counts, "like"),
			followers: APIJSON.int(st, "followers") > 0 ? APIJSON.int(st, "followers") : APIJSON.int(counts, "follower"),
			following: APIJSON.int(st, "following") > 0 ? APIJSON.int(st, "following") : APIJSON.int(counts, "following"),
			videoCount: APIJSON.int(st, "video_count") > 0 ? APIJSON.int(st, "video_count") : APIJSON.int(counts, "video"),
			postCount: APIJSON.int(st, "post_count") > 0 ? APIJSON.int(st, "post_count") : APIJSON.int(counts, "post")
		)
	}

	func fetchAuthorVideos(userId: Int, page: Int) async throws -> PageResult<VideoCard> {
		let raw = try await edgeCall(.publicScope, "GET", "/api/videos?author_id=\(userId)&page=\(page)&size=20", body: "", auth: "")
		guard let data = raw["data"] as? [String: Any] else { throw APIError.empty("author videos") }
		return parseCardPagePublic(data)
	}

	func fetchTopicDetail(slug: String, page: Int) async throws -> TopicDetail {
		let encSlug = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
		let raw = try await edgeCall(.publicScope, "GET", "/api/topics/\(encSlug)?page=\(page)", body: "", auth: "")
		guard let data = raw["data"] as? [String: Any] else { throw APIError.empty("topic") }
		let topicObj = data["topic"] as? [String: Any] ?? [:]
		let topic = TopicLite(
			id: APIJSON.string(topicObj, "id"),
			title: APIJSON.string(topicObj, "title"),
			slug: APIJSON.string(topicObj, "slug"),
			cover: absImg(APIJSON.string(topicObj, "cover")),
			intro: APIJSON.string(topicObj, "intro"),
			videoCount: APIJSON.int(topicObj, "video_count")
		)
		let videosObj = data["videos"] as? [String: Any] ?? [:]
		let videos = parseCardPagePublic(videosObj)
		let related = APIJSON.arr(data["related"]).compactMap { parseTopicPublic($0) }
		let faq = APIJSON.arr(topicObj["faq"]).compactMap { any -> (String, String)? in
			guard let d = any as? [String: Any] else { return nil }
			return (APIJSON.string(d, "q"), APIJSON.string(d, "a"))
		}
		return TopicDetail(topic: topic, videos: videos, related: related, faq: faq.map { (q: $0.0, a: $0.1) })
	}

	func fetchPostCategories() async throws -> [CategoryItem] {
		let raw = try await edgeCall(.publicScope, "GET", "/api/site/categories/post", body: "", auth: "")
		guard let data = raw["data"] as? [String: Any] else { return [] }
		return APIJSON.arr(data["items"]).compactMap { any in
			guard let d = any as? [String: Any] else { return nil }
			return CategoryItem(id: APIJSON.string(d, "id"), name: APIJSON.string(d, "name"), route: APIJSON.string(d, "route"))
		}
	}

	func fetchPosts(route: String, page: Int) async throws -> PageResult<PostCard> {
		let encR = route.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? route
		let raw = try await edgeCall(.publicScope, "GET", "/api/posts/category/\(encR)?page=\(page)&size=20", body: "", auth: "")
		guard let data = raw["data"] as? [String: Any] else { throw APIError.empty("posts") }
		let items = APIJSON.arr(data["items"]).compactMap { parsePostCard($0) }
		let pag = data["pagination"] as? [String: Any]
		return PageResult(items: items, page: APIJSON.int(pag, "page"), pages: max(APIJSON.int(pag, "pages"), 1), total: APIJSON.int(pag, "total"))
	}

	func fetchPostDetail(id: String) async throws -> PostDetail {
		let raw = try await edgeCall(.dynamic, "GET", "/api/posts/\(enc(id))", body: "", auth: "")
		guard let d = raw["data"] as? [String: Any] else { throw APIError.empty("post") }
		let author = d["author"] as? [String: Any]
		let counts = d["counts"] as? [String: Any]
		return PostDetail(
			id: APIJSON.string(d, "id"),
			title: APIJSON.string(d, "title"),
			cover: absImg(APIJSON.string(d, "cover")),
			desc: APIJSON.string(d, "desc"),
			contentHTML: APIJSON.string(d, "content"),
			tags: APIJSON.arr(d["tags"]).compactMap { $0 as? String },
			authorId: APIJSON.int(author, "id"),
			authorName: APIJSON.string(author, "name", "nickname"),
			hot: APIJSON.int(counts, "hot"),
			like: APIJSON.int(counts, "like"),
			collect: APIJSON.int(counts, "collect")
		)
	}

	func fetchFeed(kind: String, page: Int) async throws -> PageResult<VideoCard> {
		let path = kind == "today" ? "/api/feed/today?page=\(page)" : "/api/feed/recommend?page=\(page)"
		let raw = try await edgeCall(.publicScope, "GET", path, body: "", auth: "")
		guard let data = raw["data"] as? [String: Any] else { throw APIError.empty("feed") }
		return parseCardPagePublic(data)
	}

	func fetchOriginal(page: Int) async throws -> PageResult<VideoCard> {
		let raw = try await edgeCall(.publicScope, "GET", "/api/videos?is_original=1&page=\(page)&size=20", body: "", auth: "")
		guard let data = raw["data"] as? [String: Any] else { throw APIError.empty("original") }
		return parseCardPagePublic(data)
	}

	func fetchSorts() async throws -> [SortItem] {
		let raw = try await edgeCall(.publicScope, "GET", "/api/site/sorts/video", body: "", auth: "")
		guard let data = raw["data"] as? [String: Any] else { return [] }
		return APIJSON.arr(data["items"]).compactMap { any in
			guard let d = any as? [String: Any] else { return nil }
			return SortItem(id: APIJSON.string(d, "id", "route"), name: APIJSON.string(d, "name"), route: APIJSON.string(d, "route"))
		}
	}

	func fetchSortedVideos(route: String, page: Int) async throws -> PageResult<VideoCard> {
		let encR = route.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? route
		let raw = try await edgeCall(.publicScope, "GET", "/api/videos/sort/\(encR)?page=\(page)&size=20", body: "", auth: "")
		guard let data = raw["data"] as? [String: Any] else { throw APIError.empty("sort") }
		return parseCardPagePublic(data)
	}

	func fetchSuggest(q: String) async throws -> [String] {
		let encQ = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
		let raw = try await edgeCall(.publicScope, "GET", "/api/search/suggest?q=\(encQ)", body: "", auth: "")
		guard let data = raw["data"] as? [String: Any] else { return [] }
		var out: [String] = []
		for key in ["phrases", "items", "tags"] {
			for any in APIJSON.arr(data[key]) {
				if let s = any as? String, !s.isEmpty {
					out.append(s)
				} else if let d = any as? [String: Any] {
					let w = APIJSON.string(d, "word", "text", "name", "phrase")
					if !w.isEmpty { out.append(w) }
				}
			}
		}
		return Array(Set(out)).sorted()
	}

	// MARK: helpers used by Extra

	func edgeCall(_ scope: EdgeScope, _ method: String, _ path: String, body: String, auth: String) async throws -> [String: Any] {
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

	private func parseUser(_ d: [String: Any]) -> HgUser {
		let counts = d["counts"] as? [String: Any]
		let interactions = d["interactions"] as? [String: Any]
		return HgUser(
			id: APIJSON.int(d, "id"),
			username: APIJSON.string(d, "username"),
			nickname: APIJSON.string(d, "nickname"),
			avatar: absImg(APIJSON.string(d, "avatar")),
			avatarColor: APIJSON.string(d, "avatar_color").isEmpty ? "#8C8C8C" : APIJSON.string(d, "avatar_color"),
			sign: APIJSON.string(d, "sign"),
			desc: APIJSON.string(d, "desc"),
			likeCount: APIJSON.int(counts, "like"),
			collectCount: APIJSON.int(counts, "collect"),
			followingCount: APIJSON.int(counts, "following"),
			historyCount: APIJSON.int(counts, "history"),
			favoriteVideoIds: intArr(interactions?["favorite_video_ids"]),
			likeVideoIds: intArr(interactions?["like_video_ids"]),
			followUserIds: intArr(interactions?["follow_user_ids"])
		)
	}

	private func parseComment(_ any: Any?, fallbackIndex: Int = 0) -> CommentItem? {
		guard let d = any as? [String: Any] else { return nil }
		let user = d["user"] as? [String: Any]
		var id = APIJSON.string(d, "id", "comment_id")
		if id.isEmpty {
			let n = APIJSON.int(d, "id", "comment_id")
			if n != 0 { id = String(n) }
		}
		let text = APIJSON.string(d, "text", "content", "body")
		if id.isEmpty {
			// 无稳定 id 时仍展示，避免整页评论被 compactMap 丢掉
			let uid = APIJSON.int(user, "id")
			let created = APIJSON.string(d, "created_at", "createdAt")
			id = "\(uid)-\(created)-\(fallbackIndex)-\(text.hashValue)"
		}
		var userName = APIJSON.string(user, "nickname", "name")
		if userName.isEmpty {
			userName = APIJSON.string(d, "nickname", "name", "user_name")
		}
		if userName.isEmpty { userName = "用户" }
		return CommentItem(
			id: id,
			userId: APIJSON.int(user, "id"),
			userName: userName,
			avatar: absImg(APIJSON.string(user, "avatar")),
			text: text,
			createdAt: APIJSON.string(d, "created_at", "createdAt"),
			likeCount: APIJSON.int(d, "like", "likes", "like_count"),
			ep: APIJSON.int(d, "ep")
		)
	}

	private func parseHistoryPage(_ data: [String: Any]?, page: Int) -> PageResult<HistoryItem> {
		guard let data else { return PageResult(items: [], page: 1, pages: 1, total: 0) }
		let items = APIJSON.arr(data["items"]).compactMap { any -> HistoryItem? in
			guard let d = any as? [String: Any] else { return nil }
			return HistoryItem(
				id: APIJSON.int(d, "id"),
				videoId: APIJSON.string(d, "video_id"),
				title: APIJSON.string(d, "title"),
				cover: absImg(APIJSON.string(d, "cover")),
				lastEp: APIJSON.int(d, "last_ep"),
				categoryName: APIJSON.string(d, "category_name"),
				updatedAt: APIJSON.string(d, "updated_at")
			)
		}
		let pag = data["pagination"] as? [String: Any]
		return PageResult(items: items, page: APIJSON.int(pag, "page"), pages: max(APIJSON.int(pag, "pages"), 1), total: APIJSON.int(pag, "total"))
	}

	private func parsePostCard(_ any: Any?) -> PostCard? {
		guard let d = any as? [String: Any] else { return nil }
		let id = APIJSON.string(d, "id")
		if id.isEmpty { return nil }
		return PostCard(
			id: id,
			title: APIJSON.string(d, "title"),
			cover: absImg(APIJSON.string(d, "cover")),
			desc: APIJSON.string(d, "desc"),
			hot: APIJSON.int(d, "hot"),
			tags: APIJSON.arr(d["tags"]).compactMap { $0 as? String },
			createdAt: APIJSON.string(d, "created_at", "publish_time")
		)
	}

	private func parseCardPublic(_ any: Any?) -> VideoCard? {
		guard let d = any as? [String: Any] else { return nil }
		let id = APIJSON.string(d, "id", "video_id")
		if id.isEmpty { return nil }
		return VideoCard(
			id: id,
			title: APIJSON.string(d, "title"),
			cover: absImg(APIJSON.string(d, "cover")),
			score: APIJSON.double(d, "score"),
			hot: APIJSON.int(d, "hot"),
			episodeCount: APIJSON.int(d, "episode_count"),
			isFinished: APIJSON.bool(d, "is_finished"),
			tags: APIJSON.arr(d["tags"]).compactMap { $0 as? String },
			desc: APIJSON.string(d, "desc", "description"),
			badge: APIJSON.string(d, "badge"),
			durationSec: APIJSON.int(d, "duration"),
			cateId: APIJSON.string(d, "cate_id")
		)
	}

	private func parseCardPagePublic(_ data: [String: Any]) -> PageResult<VideoCard> {
		let items = APIJSON.arr(data["items"]).compactMap { parseCardPublic($0) }.uniquedPreservingOrder()
		let pag = data["pagination"] as? [String: Any]
		let page = APIJSON.int(pag, "page") > 0 ? APIJSON.int(pag, "page") : APIJSON.int(data, "page")
		let pages = max(APIJSON.int(pag, "pages") > 0 ? APIJSON.int(pag, "pages") : APIJSON.int(data, "pages"), 1)
		let total = APIJSON.int(pag, "total") > 0 ? APIJSON.int(pag, "total") : APIJSON.int(data, "total")
		return PageResult(items: items, page: page, pages: pages, total: total)
	}

	private func parseTopicPublic(_ any: Any?) -> TopicLite? {
		guard let d = any as? [String: Any] else { return nil }
		let id = APIJSON.string(d, "id")
		if id.isEmpty { return nil }
		return TopicLite(
			id: id,
			title: APIJSON.string(d, "title"),
			slug: APIJSON.string(d, "slug"),
			cover: absImg(APIJSON.string(d, "cover")),
			intro: APIJSON.string(d, "intro"),
			videoCount: APIJSON.int(d, "video_count")
		)
	}

	private func emptyPage() -> PageResult<CollectItem> {
		PageResult(items: [], page: 1, pages: 1, total: 0)
	}

	private func absImg(_ raw: String) -> String {
		if raw.isEmpty { return "" }
		if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return raw }
		if raw.hasPrefix("/") { return "https://pic.qnlycc.cn" + raw }
		return "https://pic.qnlycc.cn/" + raw
	}

	private func enc(_ s: String) -> String {
		s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
	}

	private func jsonEsc(_ s: String) -> String {
		s.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
			.replacingOccurrences(of: "\n", with: "\\n")
	}

	private func intArr(_ any: Any?) -> [Int] {
		APIJSON.arr(any).compactMap {
			if let i = $0 as? Int { return i }
			if let n = $0 as? NSNumber { return n.intValue }
			if let s = $0 as? String { return Int(s) }
			return nil
		}
	}
}

extension APIError {
	static func business(_ msg: String) -> APIError { .biz(msg) }
}
