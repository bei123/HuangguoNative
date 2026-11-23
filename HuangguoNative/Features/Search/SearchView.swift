import SwiftUI

struct SearchView: View {
	@Binding var path: NavigationPath

	@State private var keyword = ""
	@FocusState private var fieldFocused: Bool
	@State private var hotWords: [String] = []
	@State private var suggests: [String] = []
	@State private var items: [VideoCard] = []
	@State private var loading = false
	@State private var errorText = ""
	@State private var page = 1
	@State private var pages = 1
	@State private var didSearch = false
	@State private var lastQuery = ""

	var body: some View {
		VStack(spacing: 0) {
			searchBar
				.padding(.horizontal, 16)
				.padding(.vertical, 10)
			if !suggests.isEmpty && !didSearch {
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 8) {
						ForEach(suggests, id: \.self) { s in
							Button(s) {
								keyword = s
								submitSearch(s)
							}
							.font(.caption)
							.foregroundStyle(HGTheme.textPrimary)
							.padding(.horizontal, 10)
							.padding(.vertical, 8)
							.background(HGTheme.surface, in: Capsule())
							.frame(minHeight: 44)
						}
					}
					.padding(.horizontal, 16)
				}
			}
			content
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(HGTheme.bg.ignoresSafeArea())
		.navigationTitle("搜索")
		.navigationBarTitleDisplayMode(.large)
		.toolbar {
			ToolbarItemGroup(placement: .keyboard) {
				Spacer()
				Button("完成") { dismissKeyboard() }
					.accessibilityLabel("收起键盘")
			}
		}
		.task {
			if hotWords.isEmpty {
				hotWords = (try? await APIService.shared.fetchHotWords()) ?? []
			}
		}
	}

	private var searchBar: some View {
		HStack(spacing: 10) {
			Image(systemName: "magnifyingglass")
				.foregroundStyle(HGTheme.textSecondary)
				.accessibilityHidden(true)
			TextField("搜索短剧", text: $keyword)
				.accessibilityLabel("搜索短剧")
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
				.submitLabel(.search)
				.focused($fieldFocused)
				.foregroundStyle(HGTheme.textPrimary)
				.onSubmit { submitSearch(keyword) }
				.onChange(of: keyword) { _, newValue in
					let q = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
					guard q.count >= 2 else {
						suggests = []
						return
					}
					Task {
						suggests = (try? await APIService.shared.fetchSuggest(q: q)) ?? []
					}
				}
			if !keyword.isEmpty {
				Button {
					keyword = ""
					didSearch = false
					items = []
					errorText = ""
					lastQuery = ""
					suggests = []
					dismissKeyboard()
				} label: {
					Image(systemName: "xmark.circle.fill")
						.foregroundStyle(HGTheme.textMuted)
				}
				.buttonStyle(.plain)
				.frame(minWidth: 44, minHeight: 44)
				.accessibilityLabel("清除搜索")
			}
			Button("搜索") { submitSearch(keyword) }
			.font(.subheadline.weight(.semibold))
			.foregroundStyle(HGTheme.accent)
			.frame(minHeight: 44)
			.buttonStyle(.plain)
			.accessibilityLabel("开始搜索")
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 6)
		.background(HGTheme.surface, in: Capsule())
	}

	private func submitSearch(_ raw: String) {
		suggests = []
		dismissKeyboard()
		Task { await runSearch(raw, reset: true) }
	}

	private func dismissKeyboard() {
		fieldFocused = false
		UIApplication.shared.sendAction(
			#selector(UIResponder.resignFirstResponder),
			to: nil,
			from: nil,
			for: nil
		)
	}

	@ViewBuilder
	private var content: some View {
		if !didSearch {
			ScrollView {
				if hotWords.isEmpty {
					StateBox(text: "输入关键词后点搜索")
						.padding(.top, 40)
				} else {
					SectionHeader(title: "热搜")
					LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], spacing: 10) {
						ForEach(hotWords, id: \.self) { w in
							Button(w) {
								keyword = w
								submitSearch(w)
							}
							.font(.subheadline.weight(.medium))
							.foregroundStyle(HGTheme.textPrimary)
							.frame(maxWidth: .infinity, minHeight: 44)
							.background(HGTheme.surface, in: Capsule())
							.buttonStyle(.plain)
						}
					}
					.padding(.horizontal, 16)
				}
			}
			.scrollDismissesKeyboard(.interactively)
			.simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
		} else if loading && items.isEmpty {
			ScrollView {
				SkeletonRowList()
			}
			.onTapGesture { dismissKeyboard() }
		} else if !errorText.isEmpty && items.isEmpty {
			StateBox(text: errorText) {
				Task { await runSearch(lastQuery, reset: true) }
			}
			.onTapGesture { dismissKeyboard() }
		} else if items.isEmpty {
			StateBox(text: "没有结果")
				.onTapGesture { dismissKeyboard() }
		} else {
			ScrollView {
				LazyVStack(spacing: 4) {
					SectionHeader(title: "「\(lastQuery)」的结果")
					ForEach(items) { item in
						Button { path.append(AppRoute.detail(item.id)) } label: {
							VideoRowCard(item: item).padding(.horizontal, 16)
						}
						.buttonStyle(.plain)
					}
					InfiniteScrollFooter(hasMore: page <= pages, loading: loading) {
						Task { await runSearch(lastQuery, reset: false) }
					}
				}
			}
			.scrollDismissesKeyboard(.interactively)
		}
	}

	private func runSearch(_ raw: String, reset: Bool) async {
		let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !q.isEmpty else { return }
		if !reset {
			guard !loading, page <= pages else { return }
		}
		if reset, q == lastQuery, !items.isEmpty, errorText.isEmpty { return }

		didSearch = true
		lastQuery = q
		if reset {
			page = 1
			items = []
			errorText = ""
		}
		loading = true
		do {
			let result = try await APIService.shared.fetchSearch(q: q, page: page)
			if reset { items = result.items } else { items.mergeUnique(result.items) }
			pages = max(result.pages, 1)
			page = result.page + 1
		} catch {
			errorText = error.localizedDescription
		}
		loading = false
	}
}
