import SwiftUI

/// 线路测速与手动切换
struct EndpointLinesView: View {
	@State private var current = EndpointRouter.currentHost
	@State private var lines: [EndpointLine] = []
	@State private var probing = false
	@State private var toast = ""

	var body: some View {
		List {
			Section {
				HStack {
					VStack(alignment: .leading, spacing: 4) {
						Text("当前线路")
							.font(.caption)
							.foregroundStyle(HGTheme.textMuted)
						Text(current)
							.font(.body.weight(.semibold))
							.foregroundStyle(HGTheme.textPrimary)
							.lineLimit(2)
					}
					Spacer(minLength: 8)
					if let ms = lines.first(where: { $0.host == current })?.latencyMs {
						latencyBadge(ms, emphasize: true)
					}
				}
				.padding(.vertical, 4)
			} footer: {
				Text("延迟为访问边缘接口的往返时间。切换后会重建加密会话。")
			}

			Section("全部线路") {
				if probing && lines.isEmpty {
					HStack(spacing: 10) {
						ProgressView()
						Text("正在测速…")
							.foregroundStyle(HGTheme.textSecondary)
					}
					.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
				}

				ForEach(lines) { line in
					Button {
						Task { await select(line) }
					} label: {
						HStack(spacing: 12) {
							VStack(alignment: .leading, spacing: 4) {
								Text(line.host)
									.font(.body.weight(line.host == current ? .semibold : .regular))
									.foregroundStyle(line.isReachable ? HGTheme.textPrimary : HGTheme.textMuted)
									.lineLimit(2)
								Text(line.isReachable ? "可用" : "不可用 / 超时")
									.font(.caption2)
									.foregroundStyle(line.isReachable ? HGTheme.textSecondary : .red.opacity(0.85))
							}
							Spacer(minLength: 8)
							if let ms = line.latencyMs {
								latencyBadge(ms, emphasize: line.host == current)
							}
							if line.host == current {
								Image(systemName: "checkmark.circle.fill")
									.foregroundStyle(HGTheme.accent)
									.accessibilityLabel("当前选用")
							}
						}
						.padding(.vertical, 4)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					.disabled(!line.isReachable || probing || line.host == current)
					.accessibilityLabel(accessibilityLabel(for: line))
				}
			}
		}
		.listStyle(.insetGrouped)
		.navigationTitle("线路切换")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					Task { await probe(selectBest: false) }
				} label: {
					if probing {
						ProgressView()
					} else {
						Text("重新测速")
					}
				}
				.disabled(probing)
			}
		}
		.safeAreaInset(edge: .bottom) {
			VStack(spacing: 10) {
				if !toast.isEmpty {
					Text(toast)
						.font(.footnote.weight(.medium))
						.foregroundStyle(HGTheme.textPrimary)
						.padding(.horizontal, 14)
						.padding(.vertical, 8)
						.background(HGTheme.surface.opacity(0.96), in: Capsule())
				}
				Button {
					Task { await probe(selectBest: true) }
				} label: {
					Text(probing ? "测速中…" : "测速并选用最快")
						.font(.body.weight(.semibold))
						.frame(maxWidth: .infinity, minHeight: 48)
				}
				.buttonStyle(.borderedProminent)
				.tint(HGTheme.accent)
				.disabled(probing)
				.padding(.horizontal, 16)
				.padding(.bottom, 8)
			}
			.background(.ultraThinMaterial)
		}
		.task {
			current = await EndpointRouter.shared.currentHostName()
			let cached = await EndpointRouter.shared.cachedLines()
			if cached.isEmpty {
				await probe(selectBest: false)
			} else {
				lines = cached
			}
		}
	}

	private func latencyBadge(_ ms: Double, emphasize: Bool) -> some View {
		Text("\(Int(ms.rounded())) ms")
			.font(.subheadline.monospacedDigit().weight(.semibold))
			.foregroundStyle(latencyColor(ms))
			.padding(.horizontal, 10)
			.padding(.vertical, 5)
			.background(
				(emphasize ? HGTheme.accent.opacity(0.16) : HGTheme.surface),
				in: Capsule()
			)
	}

	private func latencyColor(_ ms: Double) -> Color {
		if ms < 200 { return .green }
		if ms < 450 { return HGTheme.accent }
		return .orange
	}

	private func accessibilityLabel(for line: EndpointLine) -> String {
		if let ms = line.latencyMs {
			return "\(line.host)，延迟 \(Int(ms.rounded())) 毫秒"
		}
		return "\(line.host)，不可用"
	}

	private func probe(selectBest: Bool) async {
		guard !probing else { return }
		probing = true
		defer { probing = false }
		_ = await EndpointRouter.shared.probeAll(selectBest: selectBest)
		current = await EndpointRouter.shared.currentHostName()
		lines = await EndpointRouter.shared.cachedLines()
		if selectBest {
			flash("已切换到最快线路")
		} else {
			flash("测速完成")
		}
	}

	private func select(_ line: EndpointLine) async {
		guard line.isReachable else { return }
		probing = true
		defer { probing = false }
		await EndpointRouter.shared.selectHost(line.host)
		current = await EndpointRouter.shared.currentHostName()
		flash("已切换到 \(line.host)")
	}

	private func flash(_ text: String) {
		toast = text
		Task {
			try? await Task.sleep(nanoseconds: 1_800_000_000)
			if toast == text { toast = "" }
		}
	}
}
