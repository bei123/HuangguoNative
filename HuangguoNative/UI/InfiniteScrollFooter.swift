import SwiftUI

/// 列表底部：进入可视区域时触发加载更多；加载结束后若仍在屏内则继续请求
struct InfiniteScrollFooter: View {
	let hasMore: Bool
	let loading: Bool
	let onLoadMore: () -> Void

	var body: some View {
		Group {
			if hasMore {
				HStack(spacing: 8) {
					if loading {
						ProgressView()
							.tint(HGTheme.accent)
					}
					Text(loading ? "加载中…" : "上拉加载更多")
						.font(.caption)
						.foregroundStyle(HGTheme.textMuted)
				}
				.frame(maxWidth: .infinity, minHeight: 44)
				.padding(.vertical, 12)
				.onAppear { requestIfNeeded() }
				.onChange(of: loading) { _, isLoading in
					if !isLoading { requestIfNeeded() }
				}
			} else {
				Text("没有更多了")
					.font(.caption)
					.foregroundStyle(HGTheme.textMuted)
					.frame(maxWidth: .infinity, minHeight: 44)
					.padding(.vertical, 12)
			}
		}
		.accessibilityElement(children: .combine)
		.accessibilityLabel(hasMore ? (loading ? "正在加载更多" : "加载更多") : "没有更多了")
	}

	private func requestIfNeeded() {
		guard hasMore, !loading else { return }
		onLoadMore()
	}
}
