import SwiftUI
import AVKit
import UIKit

/// 系统播放控件 + 长按倍速（内联 / 系统全屏都生效）
struct HGPlayerContainer: UIViewControllerRepresentable {
	let player: AVPlayer
	var holdSpeed: Float = 2.0
	var onHoldSpeedChanged: ((Bool) -> Void)?
	var onFullscreenChanged: ((Bool) -> Void)?

	func makeCoordinator() -> Coordinator {
		Coordinator(
			holdSpeed: holdSpeed,
			onHoldSpeedChanged: onHoldSpeedChanged,
			onFullscreenChanged: onFullscreenChanged
		)
	}

	func makeUIViewController(context: Context) -> AVPlayerViewController {
		let vc = AVPlayerViewController()
		vc.player = player
		vc.showsPlaybackControls = true
		vc.allowsPictureInPicturePlayback = true
		vc.updatesNowPlayingInfoCenter = true
		vc.delegate = context.coordinator
		if #available(iOS 16.0, *) {
			vc.allowsVideoFrameAnalysis = false
		}

		_ = vc.view
		context.coordinator.bind(to: vc, player: player)
		context.coordinator.restorePlaybackIfNeeded()
		return vc
	}

	func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
		if uiViewController.player !== player {
			uiViewController.player = player
		}
		if #available(iOS 16.0, *) {
			uiViewController.allowsVideoFrameAnalysis = false
		}
		context.coordinator.holdSpeed = holdSpeed
		context.coordinator.onHoldSpeedChanged = onHoldSpeedChanged
		context.coordinator.onFullscreenChanged = onFullscreenChanged
		context.coordinator.bind(to: uiViewController, player: player)
		context.coordinator.restorePlaybackIfNeeded()
	}

	static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
		// 全屏过渡时 SwiftUI 会拆掉内联 AVC；先记下进度，回来后seek回去
		coordinator.capturePlayback()
	}

	final class Coordinator: NSObject, AVPlayerViewControllerDelegate, UIGestureRecognizerDelegate {
		var holdSpeed: Float
		var onHoldSpeedChanged: ((Bool) -> Void)?
		var onFullscreenChanged: ((Bool) -> Void)?
		weak var playerViewController: AVPlayerViewController?
		weak var player: AVPlayer?
		private var boosting = false
		private var previousRate: Float = 1
		private weak var hudLabel: UILabel?
		private var didInstall = false
		private var savedTime: CMTime = .invalid
		private var savedRate: Float = 0
		private var needsRestore = false

		init(
			holdSpeed: Float,
			onHoldSpeedChanged: ((Bool) -> Void)?,
			onFullscreenChanged: ((Bool) -> Void)?
		) {
			self.holdSpeed = holdSpeed
			self.onHoldSpeedChanged = onHoldSpeedChanged
			self.onFullscreenChanged = onFullscreenChanged
		}

		func bind(to vc: AVPlayerViewController, player: AVPlayer) {
			playerViewController = vc
			self.player = player
			if !didInstall {
				installInteraction(on: vc)
				didInstall = true
			}
		}

		func capturePlayback() {
			guard let player else { return }
			let t = player.currentTime()
			guard t.isValid, !t.isIndefinite else { return }
			savedTime = t
			savedRate = player.rate
			needsRestore = true
		}

		func restorePlaybackIfNeeded() {
			guard needsRestore, let player else { return }
			let t = savedTime
			guard t.isValid, !t.isIndefinite else {
				needsRestore = false
				return
			}
			needsRestore = false
			let rate = savedRate
			player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
				guard finished else { return }
				if rate > 0.01 {
					player.play()
					player.rate = rate
				}
			}
		}

		func installInteraction(on vc: AVPlayerViewController) {
			attachLongPress(to: vc.view)
			if let overlay = vc.contentOverlayView {
				overlay.isUserInteractionEnabled = true
				attachLongPress(to: overlay)
				ensureHUD(on: overlay)
			}
			refreshHUD()
		}

		private func attachLongPress(to view: UIView) {
			if view.gestureRecognizers?.contains(where: { $0 is SpeedLongPress }) == true {
				return
			}
			let gr = SpeedLongPress(target: self, action: #selector(handleLongPress(_:)))
			gr.minimumPressDuration = 0.35
			gr.allowableMovement = 48
			gr.cancelsTouchesInView = false
			gr.delegate = self
			view.addGestureRecognizer(gr)
		}

		private func ensureHUD(on overlay: UIView) {
			if let hudLabel, hudLabel.superview === overlay { return }
			hudLabel?.removeFromSuperview()
			let label = UILabel()
			label.textAlignment = .center
			label.font = .systemFont(ofSize: 15, weight: .semibold)
			label.textColor = .white
			label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
			label.layer.cornerRadius = 14
			label.clipsToBounds = true
			label.isHidden = true
			label.isUserInteractionEnabled = false
			label.translatesAutoresizingMaskIntoConstraints = false
			overlay.addSubview(label)
			NSLayoutConstraint.activate([
				label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
				label.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 18),
				label.heightAnchor.constraint(equalToConstant: 28),
				label.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
			])
			hudLabel = label
		}

		func refreshHUD() {
			guard let label = hudLabel else { return }
			label.text = "  \(String(format: "%.1f", holdSpeed))x  "
			label.isHidden = !boosting
		}

		@objc func handleLongPress(_ gr: UILongPressGestureRecognizer) {
			switch gr.state {
			case .began:
				guard let player, !boosting else { return }
				previousRate = player.rate > 0.05 ? player.rate : 1
				player.rate = holdSpeed
				boosting = true
				refreshHUD()
				onHoldSpeedChanged?(true)
				UIImpactFeedbackGenerator(style: .medium).impactOccurred()
			case .ended, .cancelled, .failed:
				guard boosting else { return }
				boosting = false
				player?.rate = previousRate > 0.05 ? previousRate : 1
				refreshHUD()
				onHoldSpeedChanged?(false)
			default:
				break
			}
		}

		func gestureRecognizer(
			_ gestureRecognizer: UIGestureRecognizer,
			shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
		) -> Bool {
			true
		}

		func gestureRecognizer(
			_ gestureRecognizer: UIGestureRecognizer,
			shouldReceive touch: UITouch
		) -> Bool {
			if let view = touch.view, view is UIControl || view is UISlider {
				return false
			}
			return true
		}

		func playerViewController(
			_ playerViewController: AVPlayerViewController,
			willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
		) {
			capturePlayback()
			onFullscreenChanged?(true)
			let reinstall = { [weak self] in
				self?.installInteraction(on: playerViewController)
				if let presented = playerViewController.presentedViewController {
					self?.attachLongPress(to: presented.view)
				}
				if let parent = playerViewController.view.superview {
					self?.attachLongPress(to: parent)
				}
			}
			coordinator.animate(alongsideTransition: { _ in reinstall() }, completion: { _ in reinstall() })
		}

		func playerViewController(
			_ playerViewController: AVPlayerViewController,
			willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
		) {
			capturePlayback()
			if boosting {
				boosting = false
				refreshHUD()
				onHoldSpeedChanged?(false)
			}
			coordinator.animate(alongsideTransition: { [weak self] _ in
				self?.installInteraction(on: playerViewController)
			}, completion: { [weak self] _ in
				self?.installInteraction(on: playerViewController)
				self?.restorePlaybackIfNeeded()
				// 延后清标记，避开退出全屏时 SwiftUI onDisappear 误伤
				DispatchQueue.main.async {
					self?.onFullscreenChanged?(false)
				}
			})
		}
	}
}

private final class SpeedLongPress: UILongPressGestureRecognizer {}
