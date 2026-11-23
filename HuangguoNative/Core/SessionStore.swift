import Foundation
import Observation

@Observable
final class SessionStore {
	static let shared = SessionStore()

	private let tokenKey = "hg_auth_token"
	private let userKey = "hg_user_json"

	var token: String = "" {
		didSet {
			guard token != oldValue else { return }
			UserDefaults.standard.set(token, forKey: tokenKey)
		}
	}
	var user: HgUser = HgUser() {
		didSet {
			if let data = try? JSONEncoder().encode(CodableUser(user)),
			   let s = String(data: data, encoding: .utf8) {
				UserDefaults.standard.set(s, forKey: userKey)
			}
		}
	}

	var nickname: String {
		get { user.nickname.isEmpty ? user.username : user.nickname }
		set { user.nickname = newValue }
	}

	var isLoggedIn: Bool { !token.isEmpty }

	private init() {
		token = UserDefaults.standard.string(forKey: tokenKey) ?? ""
		if let s = UserDefaults.standard.string(forKey: userKey),
		   let data = s.data(using: .utf8),
		   let cu = try? JSONDecoder().decode(CodableUser.self, from: data) {
			user = cu.asUser()
		}
	}

	func applyLogin(token: String, user: HgUser) {
		self.token = token
		self.user = user
	}

	func updateUser(_ user: HgUser) {
		self.user = user
	}

	func signOut() {
		token = ""
		user = HgUser()
		Task { await EdgeClient.shared.clearSessions() }
	}

	func signOutRemote() async {
		await APIService.shared.logoutRemote()
		token = ""
		user = HgUser()
		await EdgeClient.shared.clearSessions()
	}
}

private struct CodableUser: Codable {
	var id: Int
	var username: String
	var nickname: String
	var avatar: String
	var avatarColor: String
	var sign: String
	var desc: String

	init(_ u: HgUser) {
		id = u.id; username = u.username; nickname = u.nickname
		avatar = u.avatar; avatarColor = u.avatarColor; sign = u.sign; desc = u.desc
	}

	func asUser() -> HgUser {
		var u = HgUser()
		u.id = id; u.username = username; u.nickname = nickname
		u.avatar = avatar; u.avatarColor = avatarColor; u.sign = sign; u.desc = desc
		return u
	}
}
