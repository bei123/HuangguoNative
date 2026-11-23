import SwiftUI

struct MessagesView: View {
	@State private var items: [MessageItem] = []
	@State private var page = 1
	@State private var pages = 1
	@State private var loading = true
	@State private var errorText = ""
	@State private var confirmReadAll = false

	var body: some View {
		Group {
			if loading && items.isEmpty {
				ScrollView {
					SkeletonMessageRows()
				}
			} else if !errorText.isEmpty && items.isEmpty {
				StateBox(text: errorText) { Task { await load(reset: true) } }
			} else if items.isEmpty {
				StateBox(text: "暂无消息")
			} else {
				List {
					Section {
						ForEach(items) { m in
							VStack(alignment: .leading, spacing: 6) {
								HStack {
									Text(m.title.isEmpty ? "系统消息" : m.title)
										.font(.body.weight(.semibold))
										.foregroundStyle(HGTheme.textPrimary)
									Spacer()
									if !m.read {
										Text("未读")
											.font(.caption2.weight(.semibold))
											.foregroundStyle(.black)
											.padding(.horizontal, 6)
											.padding(.vertical, 2)
											.background(HGTheme.accent, in: Capsule())
											.accessibilityLabel("未读")
									}
								}
								Text(m.content)
									.font(.subheadline)
									.foregroundStyle(HGTheme.textSecondary)
								Text(m.createdAt)
									.font(.caption2)
									.foregroundStyle(HGTheme.textMuted)
							}
							.padding(.vertical, 4)
							.listRowBackground(HGTheme.surface)
							.accessibilityElement(children: .combine)
							.accessibilityValue(m.read ? "已读" : "未读")
						}
					}
					Section {
						InfiniteScrollFooter(hasMore: page <= pages, loading: loading) {
							Task { await load(reset: false) }
						}
						.listRowBackground(Color.clear)
						.listRowInsets(EdgeInsets())
					}
				}
				.listStyle(.insetGrouped)
				.scrollContentBackground(.hidden)
			}
		}
		.background(HGTheme.bg.ignoresSafeArea())
		.navigationTitle("消息")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button("全部已读") { confirmReadAll = true }
					.foregroundStyle(HGTheme.accent)
					.disabled(items.isEmpty)
			}
		}
		.alert("全部标为已读？", isPresented: $confirmReadAll) {
			Button("全部已读", role: .destructive) {
				Task {
					try? await APIService.shared.readAllMessages()
					await load(reset: true)
				}
			}
			Button("取消", role: .cancel) {}
		} message: {
			Text("将清除所有未读标记。")
		}
		.task { await load(reset: true) }
	}

	private func load(reset: Bool) async {
		if !reset { guard !loading, page <= pages else { return } }
		if reset { page = 1; items = []; errorText = "" }
		loading = true
		do {
			let r = try await APIService.shared.fetchMessages(page: page)
			if reset { items = r.items } else { items.mergeUnique(r.items) }
			pages = max(r.pages, 1)
			page = r.page + 1
		} catch {
			errorText = error.localizedDescription
		}
		loading = false
	}
}
