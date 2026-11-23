import SwiftUI

struct LoginView: View {
	@Environment(\.dismiss) private var dismiss
	@Binding var path: NavigationPath
	@State private var account = ""
	@State private var password = ""
	@State private var tip = ""
	@State private var loading = false

	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				TextField("账号", text: $account)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
					.textContentType(.username)
					.padding()
					.background(HGTheme.surface, in: RoundedRectangle(cornerRadius: 12))
					.foregroundStyle(HGTheme.textPrimary)

				SecureField("密码", text: $password)
					.textContentType(.password)
					.padding()
					.background(HGTheme.surface, in: RoundedRectangle(cornerRadius: 12))
					.foregroundStyle(HGTheme.textPrimary)

				if !tip.isEmpty {
					Text(tip)
						.font(.caption)
						.foregroundStyle(tip.contains("成功") ? HGTheme.accent : HGTheme.danger.opacity(0.9))
						.frame(maxWidth: .infinity, alignment: .leading)
						.accessibilityLabel(tip)
				}

				Button {
					Task { await doLogin() }
				} label: {
					HStack {
						if loading { ProgressView() }
						Text(loading ? "登录中…" : "登录")
							.font(.body.weight(.semibold))
					}
					.frame(maxWidth: .infinity, minHeight: 48)
				}
				.buttonStyle(.glassProminent)
				.tint(HGTheme.accent)
				.disabled(loading)
				.opacity(loading ? 0.7 : 1)

				Button {
					path.append(AppRoute.register)
				} label: {
					Text("没有账号？去注册")
						.font(.subheadline.weight(.medium))
						.frame(maxWidth: .infinity, minHeight: 44)
						.contentShape(Rectangle())
				}
				.buttonStyle(.bordered)
				.tint(HGTheme.accent)
				.disabled(loading)
			}
			.padding(20)
		}
		.background(HGTheme.bg.ignoresSafeArea())
		.navigationTitle("登录")
		.navigationBarTitleDisplayMode(.inline)
	}

	@MainActor
	private func doLogin() async {
		let u = account.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !u.isEmpty, !password.isEmpty else {
			tip = "请输入账号和密码"
			return
		}
		loading = true
		tip = ""
		defer { loading = false }
		do {
			_ = try await APIService.shared.login(username: u, password: password)
			tip = "登录成功"
			path = NavigationPath()
		} catch {
			tip = "登录失败：\(error.localizedDescription)"
		}
	}
}

struct RegisterView: View {
	@Binding var path: NavigationPath
	@State private var account = ""
	@State private var password = ""
	@State private var confirm = ""
	@State private var tip = ""
	@State private var loading = false

	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				TextField("账号", text: $account)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
					.textContentType(.username)
					.padding()
					.background(HGTheme.surface, in: RoundedRectangle(cornerRadius: 12))
					.foregroundStyle(HGTheme.textPrimary)

				SecureField("密码", text: $password)
					.textContentType(.newPassword)
					.padding()
					.background(HGTheme.surface, in: RoundedRectangle(cornerRadius: 12))
					.foregroundStyle(HGTheme.textPrimary)

				SecureField("确认密码", text: $confirm)
					.textContentType(.newPassword)
					.padding()
					.background(HGTheme.surface, in: RoundedRectangle(cornerRadius: 12))
					.foregroundStyle(HGTheme.textPrimary)

				if !tip.isEmpty {
					Text(tip)
						.font(.caption)
						.foregroundStyle(tip.hasPrefix("注册成功") ? HGTheme.accent : HGTheme.danger.opacity(0.9))
						.frame(maxWidth: .infinity, alignment: .leading)
						.accessibilityLabel(tip)
				}

				Button {
					Task { await doRegister() }
				} label: {
					HStack {
						if loading { ProgressView() }
						Text(loading ? "提交中…" : "注册并登录")
							.font(.body.weight(.semibold))
					}
					.frame(maxWidth: .infinity, minHeight: 48)
				}
				.buttonStyle(.glassProminent)
				.tint(HGTheme.accent)
				.disabled(loading)
				.opacity(loading ? 0.7 : 1)
			}
			.padding(20)
		}
		.background(HGTheme.bg.ignoresSafeArea())
		.navigationTitle("注册")
		.navigationBarTitleDisplayMode(.inline)
	}

	@MainActor
	private func doRegister() async {
		let u = account.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !u.isEmpty else {
			tip = "请填写账号"
			return
		}
		guard !password.isEmpty else {
			tip = "请填写密码"
			return
		}
		guard password == confirm else {
			tip = "两次密码不一致"
			return
		}
		loading = true
		tip = "正在注册…"
		defer { loading = false }
		do {
			_ = try await APIService.shared.register(username: u, password: password, confirm: confirm)
			tip = "注册成功"
			path = NavigationPath()
		} catch {
			tip = "注册失败：\(error.localizedDescription)"
		}
	}
}
