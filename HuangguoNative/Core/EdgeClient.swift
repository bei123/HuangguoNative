import Foundation

/// dx150 会话与调用逻辑（actor，避免 async 上下文里用 NSLock）
actor EdgeClient {
	static let shared = EdgeClient()

	private let visitorKey = "hg_visitor_id"
	private var sessions: [String: Session] = [:]
	private var handshaking: [String: [CheckedContinuation<Session, Error>]] = [:]
	private var failStreak = 0

	struct Session: Sendable {
		var privB64: String
		var kid: String
		var sid: String
		var info: String
		var reqKey: String
		var resKey: String
		var seq: Int
		var expiresAt: Int
		var clockOffset: Int
	}

	func clearSessions() {
		sessions.removeAll()
		handshaking.removeAll()
	}

	func edgeRequest(scope: String, method: String, path: String, bodyJson: String, authToken: String) async throws -> String {
		_ = await EndpointRouter.shared.ensureReady()
		let ticket = DxCrypto.nextScopeTicket(scope)
		var guardCount = 0
		while DxCrypto.scopeServing(scope) + 1 < ticket {
			try await Task.sleep(nanoseconds: 8_000_000)
			guardCount += 1
			if guardCount > 2500 {
				throw NSError(domain: "hg-edge", code: 10, userInfo: [NSLocalizedDescriptionKey: "scope queue timeout \(scope)"])
			}
		}
		defer { DxCrypto.advanceScopeServing(scope, ticket) }
		do {
			let out = try await edgeRequestLocked(scope: scope, method: method, path: path, bodyJson: bodyJson, authToken: authToken)
			failStreak = 0
			return out
		} catch {
			failStreak += 1
			// 连续失败换一条更快/可用线路再试一次
			if failStreak >= 2 {
				failStreak = 0
				_ = await EndpointRouter.shared.invalidateAndReprobe()
				clearSessions()
				return try await edgeRequestLocked(scope: scope, method: method, path: path, bodyJson: bodyJson, authToken: authToken)
			}
			throw error
		}
	}

	private func edgeRequestLocked(scope: String, method: String, path: String, bodyJson: String, authToken: String) async throws -> String {
		var session = try await ensureSession(scope)
		do {
			return try await callOnce(scope: scope, session: &session, method: method, path: path, bodyJson: bodyJson, authToken: authToken)
		} catch {
			let msg = "\(error)"
			if !(msg.contains("session_expired") || msg.contains("replay")) {
				throw error
			}
			sessions.removeValue(forKey: scope)
			session = try await handshake(scope)
			return try await callOnce(scope: scope, session: &session, method: method, path: path, bodyJson: bodyJson, authToken: authToken)
		}
	}

	private func baseURL() async -> String {
		await EndpointRouter.shared.currentBaseURL()
	}

	private func nowSec() -> Int { Int(Date().timeIntervalSince1970) }

	private func getVisitorId() -> String {
		if let cached = UserDefaults.standard.string(forKey: visitorKey), cached.count == 32 {
			return cached
		}
		let id = DxCrypto.randomHex("16")
		UserDefaults.standard.set(id, forKey: visitorKey)
		return id
	}

	private func sessionValid(_ s: Session) -> Bool {
		(s.expiresAt - nowSec()) > 5 && s.seq < 16384
	}

	private func ensureSession(_ scope: String) async throws -> Session {
		if let cur = sessions[scope], sessionValid(cur) {
			return cur
		}
		return try await handshake(scope)
	}

	private func handshake(_ scope: String) async throws -> Session {
		if handshaking[scope] != nil {
			return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Session, Error>) in
				handshaking[scope, default: []].append(cont)
			}
		}
		handshaking[scope] = []

		do {
			let s = try await doHandshake(scope)
			sessions[scope] = s
			let waiters = handshaking.removeValue(forKey: scope) ?? []
			for w in waiters { w.resume(returning: s) }
			return s
		} catch {
			let waiters = handshaking.removeValue(forKey: scope) ?? []
			for w in waiters { w.resume(throwing: error) }
			throw error
		}
	}

	private func doHandshake(_ scope: String) async throws -> Session {
		let kpJson = DxCrypto.generateClientKeyPair()
		guard let kp = jsonObj(kpJson),
			  let privB64 = kp["priv"] as? String, !privB64.isEmpty,
			  let pubB64url = kp["pub"] as? String, !pubB64url.isEmpty else {
			throw err("keypair empty")
		}
		let localAtHello = nowSec()
		let base = await baseURL()
		let helloRes = try await postJson(
			url: "\(base)/api/\(scope)/request",
			body: ["v": 1, "type": "hello", "client_pub": pubB64url]
		)
		guard let kid = helloRes["kid"] as? String, !kid.isEmpty,
			  let sid = helloRes["sid"] as? String, !sid.isEmpty,
			  let serverPub = helloRes["server_pub"] as? String, !serverPub.isEmpty,
			  let salt = helloRes["salt"] as? String, !salt.isEmpty else {
			throw err("hello incomplete")
		}
		let site = (helloRes["site"] as? String) ?? "huangguoai.com"
		let serverTime = intVal(helloRes["server_time"])
		let expiresAt = intVal(helloRes["expires_at"])
		guard expiresAt > serverTime, (expiresAt - serverTime) <= 600 else {
			throw err("hello expires invalid")
		}
		let derivedJson = DxCrypto.deriveSessionKeys(privB64, serverPub, salt, scope, site, kid, sid)
		guard let derived = jsonObj(derivedJson),
			  let reqKey = derived["req"] as? String, !reqKey.isEmpty,
			  let resKey = derived["res"] as? String, !resKey.isEmpty,
			  let info = derived["info"] as? String, !info.isEmpty else {
			throw err("derive failed")
		}
		return Session(
			privB64: privB64, kid: kid, sid: sid, info: info,
			reqKey: reqKey, resKey: resKey, seq: 1,
			expiresAt: expiresAt, clockOffset: serverTime - localAtHello
		)
	}

	private func callOnce(scope: String, session: inout Session, method: String, path: String, bodyJson: String, authToken: String) async throws -> String {
		let seqInt = session.seq
		let tsInt = nowSec() + session.clockOffset
		let seqStr = "\(seqInt)"
		let tsStr = "\(tsInt)"
		let plaintext = buildInnerRequest(method: method, path: path, bodyJson: bodyJson, authToken: authToken)
		let aadReq = session.info + "\nreq\n" + seqStr + "\n" + tsStr
		let ciphertext = DxCrypto.aesGcmEncrypt(session.reqKey, seqStr, aadReq, plaintext)
		let callBody: [String: Any] = [
			"v": 1, "type": "call", "kid": session.kid, "sid": session.sid,
			"seq": seqInt, "ts": tsInt, "ciphertext": ciphertext
		]
		let callRes: [String: Any]
		do {
			let base = await baseURL()
			callRes = try await postJson(url: "\(base)/api/\(scope)/request", body: callBody)
		} catch {
			if "\(error)".contains("session_expired") { throw err("session_expired") }
			throw error
		}
		if (callRes["type"] as? String) == "error" {
			let e = (callRes["error"] as? String) ?? "edge error"
			if e.contains("session_expired") { throw err("session_expired") }
			throw err(e)
		}
		let rKid = callRes["kid"] as? String ?? ""
		let rSid = callRes["sid"] as? String ?? ""
		let rSeq = intVal(callRes["seq"])
		let rTs = intVal(callRes["ts"])
		let rCipher = callRes["ciphertext"] as? String ?? ""
		guard rKid == session.kid, rSid == session.sid, rSeq == seqInt, rTs == tsInt else {
			throw err("response mismatch")
		}
		guard !rCipher.isEmpty else { throw err("empty ciphertext") }
		let aadRes = session.info + "\nres\n" + seqStr + "\n" + tsStr
		let wrappedJson = DxCrypto.aesGcmDecrypt(session.resKey, seqStr, aadRes, rCipher)
		session.seq = seqInt + 1
		sessions[scope] = session

		guard let wrapped = jsonObj(wrappedJson) else { throw err("bad wrapped json") }
		let httpStatus = intVal(wrapped["status"])
		let bodyB64 = wrapped["body"] as? String ?? ""
		if httpStatus != 200 {
			var decoded = ""
			if !bodyB64.isEmpty { decoded = DxCrypto.stdB64DecodeToUtf8(bodyB64) }
			if decoded.contains("session_expired") { throw err("session_expired") }
			throw err("inner http \(httpStatus) \(decoded)")
		}
		if bodyB64.isEmpty { return "{}" }
		return DxCrypto.stdB64DecodeToUtf8(bodyB64)
	}

	private func buildInnerRequest(method: String, path: String, bodyJson: String, authToken: String) -> String {
		let visitorId = getVisitorId()
		let methodUp = method.uppercased()
		let pathNorm = normalizePath(path)
		var bodyB64 = ""
		var contentType = ""
		if !bodyJson.isEmpty {
			bodyB64 = DxCrypto.stdB64EncodeUtf8(bodyJson)
			contentType = "application/json"
		}
		let req = "{\"method\":\"\(jsonEscape(methodUp))\",\"path\":\"\(jsonEscape(pathNorm))\",\"body\":\"\(jsonEscape(bodyB64))\",\"content_type\":\"\(jsonEscape(contentType))\",\"visitor_id\":\"\(jsonEscape(visitorId))\",\"channel_code\":\"\"}"
		if !authToken.isEmpty {
			return "{\"request\":\(req),\"authorization\":\"Bearer \(jsonEscape(authToken))\"}"
		}
		return "{\"request\":\(req)}"
	}

	private func normalizePath(_ raw: String) -> String {
		var p = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		if let range = p.range(of: "://") {
			let after = p[range.upperBound...]
			if let slash = after.firstIndex(of: "/") {
				p = String(after[slash...])
			}
		}
		return p.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private func jsonEscape(_ s: String) -> String {
		s.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
			.replacingOccurrences(of: "\n", with: "\\n")
			.replacingOccurrences(of: "\r", with: "\\r")
			.replacingOccurrences(of: "\t", with: "\\t")
	}

	private func postJson(url: String, body: [String: Any]) async throws -> [String: Any] {
		guard let u = URL(string: url) else { throw err("bad url") }
		var req = URLRequest(url: u, timeoutInterval: 30)
		req.httpMethod = "POST"
		req.setValue("application/json", forHTTPHeaderField: "Content-Type")
		req.setValue("application/json", forHTTPHeaderField: "Accept")
		req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
		let (data, resp) = try await URLSession.shared.data(for: req)
		let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
		guard code >= 200 && code < 300 else {
			let text = String(data: data, encoding: .utf8) ?? ""
			throw err("http \(code) \(text)")
		}
		guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw err("invalid json response")
		}
		return obj
	}

	private func jsonObj(_ s: String) -> [String: Any]? {
		guard let d = s.data(using: .utf8) else { return nil }
		return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
	}

	private func intVal(_ v: Any?) -> Int {
		if let i = v as? Int { return i }
		if let n = v as? NSNumber { return n.intValue }
		if let s = v as? String, let i = Int(s) { return i }
		return 0
	}

	private func err(_ msg: String) -> NSError {
		NSError(domain: "hg-edge", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
	}
}
