import Foundation

struct EndpointLine: Identifiable, Sendable, Equatable {
	var id: String { host }
	let host: String
	/// 探测 RTT（毫秒）；`nil` 表示超时或不可用
	let latencyMs: Double?
	var isReachable: Bool { latencyMs != nil }
}

/// 多镜像域名测速：并行探测，选用最快可用地址
actor EndpointRouter {
	static let shared = EndpointRouter()

	/// 主站 + 备用访问地址（须支持 POST `/api/*/request`；静态 Pages 等会 405，勿列入）
	static let candidates: [String] = [
		"huangguoai.com",
		"ea3.aqkmowihz.cc",
		"wvyj3.aqkmowihz.cc",
		"hccm.aqkmowihz.cc",
		"fs0k.kplsifomz.cc",
	]

	private static let hostKey = "hg_edge_host"
	private static let probedAtKey = "hg_edge_host_probed_at"
	/// 缓存结果有效期：30 分钟后再测
	private static let cacheTTL: TimeInterval = 30 * 60
	private static let probeTimeout: TimeInterval = 2.8

	private var host: String
	private var probedAt: Date?
	private var probing: Task<String, Never>?
	private var lastLines: [EndpointLine] = []

	nonisolated static var currentHost: String { HostCache.shared.host }
	nonisolated static var baseURL: String { "https://\(currentHost)" }
	nonisolated static var referer: String { "https://\(currentHost)/" }

	init() {
		let saved = UserDefaults.standard.string(forKey: Self.hostKey) ?? "huangguoai.com"
		host = Self.candidates.contains(saved) ? saved : "huangguoai.com"
		HostCache.shared.host = host
		if let ts = UserDefaults.standard.object(forKey: Self.probedAtKey) as? Date {
			probedAt = ts
		}
		// 缓存了已剔除的坏域名时，立刻作废，下次 ensureReady 重测
		// init 为 nonisolated，不能直接调 actor 隔离的 persist()
		if !Self.candidates.contains(saved) {
			probedAt = nil
			Self.writeDefaults(host: host, probedAt: nil)
		}
	}

	func currentBaseURL() -> String { "https://\(host)" }

	func currentHostName() -> String { host }

	func cachedLines() -> [EndpointLine] { lastLines }

	/// 启动或请求前调用；有缓存且未过期则跳过
	@discardableResult
	func ensureReady(force: Bool = false) async -> String {
		if !force,
		   let probedAt,
		   Date().timeIntervalSince(probedAt) < Self.cacheTTL,
		   Self.candidates.contains(host) {
			return host
		}
		if let probing {
			return await probing.value
		}
		let task = Task { await self.probeAll(selectBest: true) }
		probing = task
		let winner = await task.value
		probing = nil
		return winner
	}

	/// 连续失败时可强制换线
	func invalidateAndReprobe() async -> String {
		probedAt = nil
		return await ensureReady(force: true)
	}

	/// 测速全部线路；`selectBest` 为真时自动切到最快可用
	@discardableResult
	func probeAll(selectBest: Bool) async -> String {
		let hosts = Self.candidates
		print("[endpoint] probing \(hosts.count) hosts…")

		let results: [EndpointLine] = await withTaskGroup(of: EndpointLine.self) { group in
			for h in hosts {
				group.addTask {
					await Self.measure(host: h)
				}
			}
			var out: [EndpointLine] = []
			for await item in group {
				out.append(item)
			}
			return out.sorted { a, b in
				switch (a.latencyMs, b.latencyMs) {
				case let (x?, y?): return x < y
				case (_?, nil): return true
				case (nil, _?): return false
				case (nil, nil): return a.host < b.host
				}
			}
		}
		lastLines = results

		let reachable = results.filter(\.isReachable)
		if selectBest, let best = reachable.first {
			await applyHost(best.host, clearSessionIfChanged: true)
		} else {
			probedAt = Date()
			persist()
		}

		let summary = results
			.map { line in
				if let ms = line.latencyMs {
					return "\(line.host)=\(String(format: "%.0f", ms))ms"
				}
				return "\(line.host)=fail"
			}
			.joined(separator: ", ")
		print("[endpoint] current=\(host) [\(summary)]")
		return host
	}

	/// 用户手动切换线路
	func selectHost(_ newHost: String) async {
		guard Self.candidates.contains(newHost) else { return }
		await applyHost(newHost, clearSessionIfChanged: true)
	}

	private func applyHost(_ newHost: String, clearSessionIfChanged: Bool) async {
		let changed = newHost != host
		host = newHost
		probedAt = Date()
		HostCache.shared.host = host
		persist()
		if changed, clearSessionIfChanged {
			await EdgeClient.shared.clearSessions()
		}
	}

	private func persist() {
		Self.writeDefaults(host: host, probedAt: probedAt)
	}

	nonisolated private static func writeDefaults(host: String, probedAt: Date?) {
		UserDefaults.standard.set(host, forKey: hostKey)
		if let probedAt {
			UserDefaults.standard.set(probedAt, forKey: probedAtKey)
		} else {
			UserDefaults.standard.removeObject(forKey: probedAtKey)
		}
	}

	/// 对边缘握手入口做轻量 POST，测真实 API 可达性与延迟
	nonisolated private static func measure(host: String) async -> EndpointLine {
		guard let url = URL(string: "https://\(host)/api/public/request") else {
			return EndpointLine(host: host, latencyMs: nil)
		}
		var req = URLRequest(url: url, timeoutInterval: probeTimeout)
		req.httpMethod = "POST"
		req.setValue("application/json", forHTTPHeaderField: "Content-Type")
		req.setValue("application/json", forHTTPHeaderField: "Accept")
		// 非法 hello：真边缘会很快回 JSON（多为 400 invalid_request）
		req.httpBody = Data(#"{"v":1,"type":"hello"}"#.utf8)

		let start = CFAbsoluteTimeGetCurrent()
		do {
			let (data, resp) = try await URLSession.shared.data(for: req)
			let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
			let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
			// 静态站 / 错误镜像常见：405 Method Not Allowed、404 HTML —— 绝不能当可用线路
			guard (200..<500).contains(code), code != 405, code != 404 else {
				return EndpointLine(host: host, latencyMs: nil)
			}
			let text = String(data: data, encoding: .utf8) ?? ""
			let looksLikeEdge =
				text.contains("\"error\"")
				|| text.contains("\"kid\"")
				|| text.contains("\"type\"")
				|| text.contains("invalid_request")
			guard looksLikeEdge else {
				return EndpointLine(host: host, latencyMs: nil)
			}
			return EndpointLine(host: host, latencyMs: ms)
		} catch {
			return EndpointLine(host: host, latencyMs: nil)
		}
	}
}

/// 跨线程同步读当前域名（封面 Referer 等）
private final class HostCache: @unchecked Sendable {
	static let shared = HostCache()
	private let lock = NSLock()
	private var _host: String
	var host: String {
		get { lock.lock(); defer { lock.unlock() }; return _host }
		set { lock.lock(); _host = newValue; lock.unlock() }
	}
	private init() {
		let saved = UserDefaults.standard.string(forKey: "hg_edge_host") ?? "huangguoai.com"
		_host = EndpointRouter.candidates.contains(saved) ? saved : "huangguoai.com"
	}
}
