import SwiftUI

struct HGImageLightboxItem: Identifiable {
	let id = UUID()
	var urls: [String]
	var index: Int
}

/// 全屏看图：未放大左右滑切换；放大后拖移；双指缩放 / 双击放大
struct HGImageLightbox: View {
	let urls: [String]
	@State private var index: Int
	@Environment(\.dismiss) private var dismiss

	@State private var scale: CGFloat = 1
	@State private var lastScale: CGFloat = 1
	@State private var offset: CGSize = .zero
	@State private var lastOffset: CGSize = .zero
	@State private var dragTranslation: CGSize = .zero

	init(urls: [String], startIndex: Int) {
		self.urls = urls
		_index = State(initialValue: min(max(0, startIndex), max(urls.count - 1, 0)))
	}

	private var zoomed: Bool { scale > 1.05 }

	var body: some View {
		ZStack {
			Color.black.ignoresSafeArea()

			if urls.indices.contains(index) {
				GeometryReader { geo in
					HGCoverImage(url: urls[index], cornerRadius: 0, contentMode: .fit)
						.frame(width: geo.size.width, height: geo.size.height)
						.scaleEffect(scale)
						.offset(
							x: offset.width + (zoomed ? dragTranslation.width : (urls.count > 1 ? dragTranslation.width : 0)),
							y: offset.height + (zoomed ? dragTranslation.height : 0)
						)
						.gesture(magnifyGesture)
						.simultaneousGesture(pageOrPanGesture(size: geo.size))
						.onTapGesture(count: 2, perform: toggleZoom)
						.contentShape(Rectangle())
						.id(urls[index])
				}
				.ignoresSafeArea()
			}

			VStack {
				HStack {
					if urls.count > 1 {
						Text("\(index + 1) / \(urls.count)")
							.font(.subheadline.weight(.semibold))
							.foregroundStyle(.white.opacity(0.9))
							.padding(.horizontal, 12)
							.padding(.vertical, 8)
							.background(.ultraThinMaterial, in: Capsule())
					}
					Spacer()
					Button {
						dismiss()
					} label: {
						Image(systemName: "xmark")
							.font(.body.weight(.semibold))
							.foregroundStyle(.white)
							.frame(width: 44, height: 44)
							.background(.ultraThinMaterial, in: Circle())
					}
					.buttonStyle(.plain)
					.accessibilityLabel("关闭")
				}
				.padding(.horizontal, 16)
				.padding(.top, 8)
				Spacer()
			}
		}
		.statusBarHidden(true)
	}

	private var magnifyGesture: some Gesture {
		MagnifyGesture()
			.onChanged { value in
				scale = min(max(lastScale * value.magnification, 1), 4)
			}
			.onEnded { _ in
				lastScale = scale
				if scale <= 1.05 {
					withAnimation(.snappy) { resetZoom() }
				}
			}
	}

	private func pageOrPanGesture(size: CGSize) -> some Gesture {
		DragGesture(minimumDistance: 12)
			.onChanged { value in
				dragTranslation = value.translation
			}
			.onEnded { value in
				defer { dragTranslation = .zero }
				if zoomed {
					offset = CGSize(
						width: lastOffset.width + value.translation.width,
						height: lastOffset.height + value.translation.height
					)
					lastOffset = offset
					return
				}
				guard urls.count > 1 else { return }
				let dx = value.translation.width
				let predicted = value.predictedEndTranslation.width
				let threshold = min(size.width * 0.22, 90)
				if dx < -threshold || predicted < -threshold * 1.4 {
					go(to: index + 1)
				} else if dx > threshold || predicted > threshold * 1.4 {
					go(to: index - 1)
				}
			}
	}

	private func go(to newIndex: Int) {
		guard urls.indices.contains(newIndex) else { return }
		withAnimation(.snappy(duration: 0.25)) {
			index = newIndex
			resetZoom()
		}
	}

	private func toggleZoom() {
		withAnimation(.snappy) {
			if zoomed {
				resetZoom()
			} else {
				scale = 2.2
				lastScale = 2.2
			}
		}
	}

	private func resetZoom() {
		scale = 1
		lastScale = 1
		offset = .zero
		lastOffset = .zero
		dragTranslation = .zero
	}
}
