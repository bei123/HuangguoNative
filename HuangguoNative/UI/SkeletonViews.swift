import SwiftUI

/// HIG：用与最终布局相近的占位，避免全屏阻塞转圈
enum HGSkeleton {
	static let placeholderTitle = "短剧标题占位两行文字"
	static let placeholderMeta = "9.0 · 12集"
	static let placeholderBody = "正文占位文字用来撑开骨架行高"
}

struct SkeletonPosterCard: View {
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			RoundedRectangle(cornerRadius: 10, style: .continuous)
				.fill(HGTheme.surface)
				.aspectRatio(1 / 1.35, contentMode: .fit)
			Text(HGSkeleton.placeholderTitle)
				.font(.subheadline.weight(.medium))
				.lineLimit(2)
				.frame(maxWidth: .infinity, alignment: .leading)
			Text(HGSkeleton.placeholderMeta)
				.font(.caption)
		}
		.redacted(reason: .placeholder)
		.accessibilityHidden(true)
	}
}

struct SkeletonPosterGrid: View {
	var count: Int = 9

	var body: some View {
		LazyVGrid(
			columns: [
				GridItem(.flexible(), spacing: 10, alignment: .top),
				GridItem(.flexible(), spacing: 10, alignment: .top),
				GridItem(.flexible(), spacing: 10, alignment: .top)
			],
			spacing: 14
		) {
			ForEach(0..<count, id: \.self) { _ in
				SkeletonPosterCard()
			}
		}
		.padding(.horizontal, 16)
		.padding(.top, 8)
		.accessibilityLabel("正在加载")
	}
}

struct SkeletonRowCard: View {
	var body: some View {
		HStack(spacing: 12) {
			RoundedRectangle(cornerRadius: 8, style: .continuous)
				.fill(HGTheme.surface)
				.frame(width: 84, height: 112)
			VStack(alignment: .leading, spacing: 6) {
				Text(HGSkeleton.placeholderTitle)
					.font(.body.weight(.semibold))
					.lineLimit(2)
				Text(HGSkeleton.placeholderMeta)
					.font(.caption)
				Text(HGSkeleton.placeholderBody)
					.font(.caption)
					.lineLimit(2)
			}
			Spacer(minLength: 0)
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 6)
		.redacted(reason: .placeholder)
		.accessibilityHidden(true)
	}
}

struct SkeletonRowList: View {
	var count: Int = 6

	var body: some View {
		LazyVStack(spacing: 4) {
			ForEach(0..<count, id: \.self) { _ in
				SkeletonRowCard()
			}
		}
		.padding(.top, 8)
		.accessibilityLabel("正在加载")
	}
}

struct SkeletonHomeBlocks: View {
	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.fill(HGTheme.surface)
				.frame(height: 44)
				.padding(.horizontal, 16)
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 12) {
					ForEach(0..<3, id: \.self) { _ in
						RoundedRectangle(cornerRadius: 14, style: .continuous)
							.fill(HGTheme.surface)
							.frame(width: 280, height: 150)
					}
				}
				.padding(.horizontal, 16)
			}
			Text("精选")
				.font(.title3.weight(.bold))
				.padding(.horizontal, 16)
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 12) {
					ForEach(0..<4, id: \.self) { _ in
						SkeletonPosterCard()
							.frame(width: 110)
					}
				}
				.padding(.horizontal, 16)
			}
		}
		.padding(.top, 12)
		.redacted(reason: .placeholder)
		.accessibilityLabel("正在加载首页")
	}
}

struct SkeletonDetailInfo: View {
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			RoundedRectangle(cornerRadius: 8, style: .continuous)
				.fill(HGTheme.surface)
				.aspectRatio(16 / 9, contentMode: .fit)
			Text(HGSkeleton.placeholderTitle)
				.font(.title2.weight(.bold))
			Text(HGSkeleton.placeholderMeta)
				.font(.caption)
			Text(HGSkeleton.placeholderBody)
				.font(.body)
				.lineLimit(3)
		}
		.padding(16)
		.redacted(reason: .placeholder)
		.accessibilityLabel("正在加载详情")
	}
}

struct SkeletonMessageRows: View {
	var count: Int = 5

	var body: some View {
		VStack(spacing: 10) {
			ForEach(0..<count, id: \.self) { _ in
				VStack(alignment: .leading, spacing: 6) {
					Text(HGSkeleton.placeholderTitle)
						.font(.body.weight(.semibold))
					Text(HGSkeleton.placeholderBody)
						.font(.subheadline)
					Text("刚刚")
						.font(.caption2)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(14)
				.background(HGTheme.surface, in: RoundedRectangle(cornerRadius: 12))
				.padding(.horizontal, 16)
			}
		}
		.padding(.top, 8)
		.redacted(reason: .placeholder)
		.accessibilityLabel("正在加载消息")
	}
}
