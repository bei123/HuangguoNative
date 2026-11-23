import SwiftUI

struct MineView: View {
	@Binding var path: NavigationPath
	private let session = SessionStore.shared
	@State private var unread = 0
	@State private var refreshTick = 0
	@State private var confirmSignOut = false

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				header
				if session.isLoggedIn {
					VStack(spacing: 0) {
						mineRow("观看历史", system: "clock") { path.append(AppRoute.myList(.history)) }
						Divider().background(HGTheme.glassStroke)
						mineRow("我的收藏", system: "star") { path.append(AppRoute.myList(.collects)) }
						Divider().background(HGTheme.glassStroke)
						mineRow("我的点赞", system: "heart") { path.append(AppRoute.myList(.likes)) }
						Divider().background(HGTheme.glassStroke)
						mineRow("我的关注", system: "person.2") { path.append(AppRoute.myList(.follows)) }
						Divider().background(HGTheme.glassStroke)
						mineRow(unread > 0 ? "消息（\(unread)）" : "消息", system: "bell") { path.append(AppRoute.messages) }
						Divider().background(HGTheme.glassStroke)
						mineRow("编辑资料", system: "pencil") { path.append(AppRoute.profileEdit) }
					}
					.background(HGTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
				}

				VStack(spacing: 0) {
					mineRow("热播榜", system: "flame") { path.append(AppRoute.rank) }
					Divider().background(HGTheme.glassStroke)
					mineRow("专题", system: "rectangle.stack") { path.append(AppRoute.topics) }
					Divider().background(HGTheme.glassStroke)
					mineRow("最近更新", system: "clock") { path.append(AppRoute.latest) }
					Divider().background(HGTheme.glassStroke)
					mineRow("图文", system: "doc.text") { path.append(AppRoute.posts) }
					Divider().background(HGTheme.glassStroke)
					mineRow("推荐流", system: "sparkles") { path.append(AppRoute.feed) }
					Divider().background(HGTheme.glassStroke)
					mineRow("更多", system: "ellipsis.circle") { path.append(AppRoute.more) }
				}
				.background(HGTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

				if session.isLoggedIn {
					Button("退出登录", role: .destructive) {
						confirmSignOut = true
					}
					.font(.body.weight(.medium))
					.frame(maxWidth: .infinity, minHeight: 48)
					.background(HGTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
				}
			}
			.padding(16)
			.padding(.bottom, 24)
		}
		.background(HGTheme.bg.ignoresSafeArea())
		.navigationTitle("我的")
		.navigationBarTitleDisplayMode(.large)
		.id(refreshTick)
		.alert("退出登录？", isPresented: $confirmSignOut) {
			Button("退出", role: .destructive) {
				Task {
					await SessionStore.shared.signOutRemote()
					refreshTick += 1
				}
			}
			Button("取消", role: .cancel) {}
		} message: {
			Text("退出后收藏与历史将不再同步到本机会话。")
		}
		.task {
			if session.isLoggedIn {
				_ = try? await APIService.shared.fetchMe()
				unread = (try? await APIService.shared.fetchUnreadCount()) ?? 0
				refreshTick += 1
			}
		}
	}

	private var header: some View {
		HStack(spacing: 14) {
			ZStack {
				Circle().fill(Color(hex: session.user.avatarColor) ?? HGTheme.surface)
					.frame(width: 64, height: 64)
				if !session.user.avatar.isEmpty {
					HGCoverImage(url: session.user.avatar, cornerRadius: 32)
						.frame(width: 64, height: 64)
				} else {
					Image(systemName: "person.fill")
						.font(.title2)
						.foregroundStyle(HGTheme.accent)
						.accessibilityHidden(true)
				}
			}
			.accessibilityLabel(session.isLoggedIn ? "头像" : "未登录头像")
			VStack(alignment: .leading, spacing: 4) {
				Text(session.isLoggedIn ? session.nickname : "未登录")
					.font(.title3.weight(.semibold))
					.foregroundStyle(HGTheme.textPrimary)
				Text(session.isLoggedIn ? (session.user.sign.isEmpty ? "欢迎回来" : session.user.sign) : "登录后可同步收藏与历史")
					.font(.caption)
					.foregroundStyle(HGTheme.textSecondary)
					.lineLimit(2)
			}
			Spacer()
			if !session.isLoggedIn {
				Button("登录") { path.append(AppRoute.login) }
					.buttonStyle(.glassProminent)
					.tint(HGTheme.accent)
					.frame(minHeight: 44)
			}
		}
		.padding(16)
		.background(HGTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}

	private func mineRow(_ title: String, system: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			HStack {
				Image(systemName: system)
					.foregroundStyle(HGTheme.accent)
					.frame(width: 28)
					.accessibilityHidden(true)
				Text(title)
					.foregroundStyle(HGTheme.textPrimary)
				Spacer()
				Image(systemName: "chevron.right")
					.font(.caption.weight(.semibold))
					.foregroundStyle(HGTheme.textMuted)
					.accessibilityHidden(true)
			}
			.padding(.horizontal, 16)
			.frame(minHeight: 52)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(title)
	}
}

extension Color {
	init?(hex: String) {
		var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
		if s.hasPrefix("#") { s.removeFirst() }
		guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
		self.init(
			red: Double((v >> 16) & 0xff) / 255,
			green: Double((v >> 8) & 0xff) / 255,
			blue: Double(v & 0xff) / 255
		)
	}
}
