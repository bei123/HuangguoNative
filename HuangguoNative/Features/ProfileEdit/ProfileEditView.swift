import SwiftUI

struct ProfileEditView: View {
	@Environment(\.dismiss) private var dismiss
	@State private var nickname = SessionStore.shared.user.nickname
	@State private var sign = SessionStore.shared.user.sign
	@State private var desc = SessionStore.shared.user.desc
	@State private var tip = ""
	@State private var loading = false
	@State private var oldPwd = ""
	@State private var newPwd = ""
	@State private var confirmPwd = ""
	@State private var pwdLoading = false

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 14) {
				field("昵称", text: $nickname)
				field("签名", text: $sign)
				field("简介", text: $desc)
				Button {
					Task { await saveProfile() }
				} label: {
					HStack {
						if loading { ProgressView() }
						Text(loading ? "保存中…" : "保存资料")
							.font(.body.weight(.semibold))
					}
					.frame(maxWidth: .infinity, minHeight: 48)
				}
				.buttonStyle(.glassProminent)
				.tint(HGTheme.accent)
				.disabled(loading)

				Text("修改密码")
					.font(.headline)
					.foregroundStyle(HGTheme.textPrimary)
					.padding(.top, 12)
				SecureField("原密码", text: $oldPwd)
					.textContentType(.password)
					.padding().background(HGTheme.surface, in: RoundedRectangle(cornerRadius: 12))
					.foregroundStyle(HGTheme.textPrimary)
				SecureField("新密码", text: $newPwd)
					.textContentType(.newPassword)
					.padding().background(HGTheme.surface, in: RoundedRectangle(cornerRadius: 12))
					.foregroundStyle(HGTheme.textPrimary)
				SecureField("确认新密码", text: $confirmPwd)
					.textContentType(.newPassword)
					.padding().background(HGTheme.surface, in: RoundedRectangle(cornerRadius: 12))
					.foregroundStyle(HGTheme.textPrimary)
				Button {
					Task { await changePwd() }
				} label: {
					HStack {
						if pwdLoading { ProgressView() }
						Text(pwdLoading ? "提交中…" : "修改密码")
					}
					.frame(maxWidth: .infinity, minHeight: 44)
				}
				.buttonStyle(.bordered)
				.tint(HGTheme.accent)
				.disabled(pwdLoading)

				if !tip.isEmpty {
					Text(tip)
						.font(.caption)
						.foregroundStyle(HGTheme.textSecondary)
						.accessibilityLabel(tip)
				}
			}
			.padding(16)
		}
		.background(HGTheme.bg.ignoresSafeArea())
		.navigationTitle("编辑资料")
		.navigationBarTitleDisplayMode(.inline)
	}

	private func field(_ title: String, text: Binding<String>) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(title).font(.caption).foregroundStyle(HGTheme.textSecondary)
			TextField(title, text: text)
				.padding()
				.background(HGTheme.surface, in: RoundedRectangle(cornerRadius: 12))
				.foregroundStyle(HGTheme.textPrimary)
		}
	}

	private func saveProfile() async {
		loading = true
		tip = ""
		do {
			_ = try await APIService.shared.updateProfile(
				nickname: nickname,
				sign: sign,
				desc: desc,
				avatarColor: nil
			)
			tip = "已保存"
			dismiss()
		} catch {
			tip = error.localizedDescription
		}
		loading = false
	}

	private func changePwd() async {
		tip = ""
		pwdLoading = true
		defer { pwdLoading = false }
		do {
			try await APIService.shared.changePassword(old: oldPwd, new: newPwd, confirm: confirmPwd)
			tip = "密码已修改"
			oldPwd = ""; newPwd = ""; confirmPwd = ""
		} catch {
			tip = error.localizedDescription
		}
	}
}
