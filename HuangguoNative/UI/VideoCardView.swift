import SwiftUI

struct VideoPosterCard: View {
	let item: VideoCard
	/// 横向滚动等场景固定宽度；网格里传 `nil` 用父级宽度
	var width: CGFloat? = 110

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HGCoverImage(url: item.cover, cornerRadius: 10)
				.frame(maxWidth: .infinity)
				.aspectRatio(1 / 1.35, contentMode: .fit)
				.frame(width: width, height: width.map { $0 * 1.35 })
				.overlay(alignment: .topLeading) {
					if !item.badge.isEmpty {
						Text(item.badge)
							.font(.caption2.weight(.semibold))
							.foregroundStyle(.black)
							.padding(.horizontal, 6)
							.padding(.vertical, 3)
							.background(HGTheme.accent, in: Capsule())
							.padding(6)
					}
				}
			Text(item.title)
				.font(.subheadline.weight(.medium))
				.foregroundStyle(HGTheme.textPrimary)
				.lineLimit(2)
				.multilineTextAlignment(.leading)
				.frame(width: width, height: titleBlockHeight, alignment: .topLeading)
				.frame(maxWidth: width == nil ? .infinity : nil, alignment: .topLeading)
			Text(meta)
				.font(.caption)
				.foregroundStyle(HGTheme.textSecondary)
				.lineLimit(1)
				.frame(width: width, alignment: .leading)
				.frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
		}
		.frame(width: width, alignment: .topLeading)
	}

	/// 固定两行标题占位，避免长短名把同排封面挤乱
	private var titleBlockHeight: CGFloat {
		UIFont.preferredFont(forTextStyle: .subheadline).lineHeight * 2
	}

	private var meta: String {
		let score = item.score > 0 ? String(format: "%.1f", item.score) : "-"
		return "\(score) · \(item.episodeCount)集"
	}
}

struct VideoRowCard: View {
	let item: VideoCard

	var body: some View {
		HStack(spacing: 12) {
			HGCoverImage(url: item.cover, cornerRadius: 8)
				.frame(width: 84, height: 112)
			VStack(alignment: .leading, spacing: 6) {
				Text(item.title)
					.font(.body.weight(.semibold))
					.foregroundStyle(HGTheme.textPrimary)
					.lineLimit(2)
				Text(meta)
					.font(.caption)
					.foregroundStyle(HGTheme.textSecondary)
				if !item.desc.isEmpty {
					Text(item.desc)
						.font(.caption)
						.foregroundStyle(HGTheme.textMuted)
						.lineLimit(2)
				}
			}
			Spacer(minLength: 0)
		}
		.padding(.vertical, 6)
		.contentShape(Rectangle())
	}

	private var meta: String {
		let score = item.score > 0 ? String(format: "%.1f", item.score) : "-"
		return "评分 \(score) · \(item.episodeCount)集"
	}
}

struct SectionHeader: View {
	let title: String
	var actionTitle: String? = nil
	var action: (() -> Void)? = nil

	var body: some View {
		HStack {
			Text(title)
				.font(.title3.weight(.bold))
				.foregroundStyle(HGTheme.textPrimary)
			Spacer()
			if let actionTitle, let action {
				Button(actionTitle, action: action)
					.font(.subheadline.weight(.medium))
					.foregroundStyle(HGTheme.accent)
					.frame(minHeight: 44)
					.padding(.horizontal, 4)
					.contentShape(Rectangle())
					.accessibilityLabel(actionTitle)
			}
		}
		.padding(.horizontal, 16)
		.padding(.top, 18)
		.padding(.bottom, 10)
	}
}

struct StateBox: View {
	let text: String
	var actionTitle: String = "点击重试"
	var action: (() -> Void)?

	var body: some View {
		VStack(spacing: 12) {
			Text(text)
				.font(.body)
				.foregroundStyle(HGTheme.textSecondary)
				.multilineTextAlignment(.center)
			if let action {
				Button(actionTitle, action: action)
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(HGTheme.accent)
					.frame(minHeight: 44)
			}
		}
		.frame(maxWidth: .infinity)
		.padding(32)
	}
}
