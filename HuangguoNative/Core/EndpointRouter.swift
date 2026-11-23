import Foundation

/// 多镜像域名测速：并行探测，选用最快可用地址
actor EndpointRouter {
	static let shared = EndpointRouter()

	/// 主站 + 备用访问地址（去重）
	static let candidates: [String] = [
		"huangguoai.com",
		"hgai29.com",
		"ea3.aqkmowihz.cc",
		"huangguo88.pages.dev",
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
	}

	func currentBaseURL() -> String { "https://\(host)" }

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
		let task = Task { await self.probeAll() }
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

	private func probeAll() async -> String {
		let hosts = Self.candidates
		print("[endpoint] probing \(hosts.count) hosts…")

		let results: [(String, Double)] = await withTaskGroup(of: (String, Double)?.self) { group in
			for h in hosts {
				group.addTask {
					await Self.measure(host: h)
				}
			}
			var out: [(String, Double)] = []
			for await item in group {
				if let item { out.append(item) }
			}
			return out
		}

		guard let best = results.min(by: { $0.1 < $1.1 }) else {
			print("[endpoint] all failed, keep \(host)")
			probedAt = Date()
			persist()
			return host
		}

		let changed = best.0 != host
		host = best.0
		probedAt = Date()
		HostCache.shared.host = host
		persist()
		let summary = results
			.sorted { $0.1 < $1.1 }
			.map { "\($0.0)=\(String(format: "%.0f", $0.1))ms" }
			.joined(separator: ", ")
		print("[endpoint] winner=\(host) (\(String(format: "%.0f", best.1))ms) [\(summary)]")
		if changed {
			await EdgeClient.shared.clearSessions()
		}
		return host
	}

	private func persist() {
		UserDefaults.standard.set(host, forKey: Self.hostKey)
		if let probedAt {
			UserDefaults.standard.set(probedAt, forKey: Self.probedAtKey)
		}
	}

	/// 对边缘握手入口做轻量 POST，测真实 API 可达性与延迟
	nonisolated private static func measure(host: String) async -> (String, Double)? {
		guard let url = URL(string: "https://\(host)/api/public/request") else { return nil }
		var req = URLRequest(url: url, timeoutInterval: probeTimeout)
		req.httpMethod = "POST"
		req.setValue("application/json", forHTTPHeaderField: "Content-Type")
		req.setValue("application/json", forHTTPHeaderField: "Accept")
		// 非法 hello 也会很快返回，足以证明线路通
		req.httpBody = Data(#"{"v":1,"type":"hello"}"#.utf8)

		let start = CFAbsoluteTimeGetCurrent()
		do {
			let (_, resp) = try await URLSession.shared.data(for: req)
			let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
			let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
			// 2xx/4xx 都说明主机可达；5xx/超时不算
			guard (200..<500).contains(code) else { return nil }
			return (host, ms)
		} catch {
			return nil
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
		_host = UserDefaults.standard.string(forKey: "hg_edge_host") ?? "huangguoai.com"
	}
}
