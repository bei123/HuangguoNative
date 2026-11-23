import AVFoundation

enum AudioSession {
	/// 视频/音频播放：忽略静音拨片。勿在主线程同步 setActive，避免卡 UI。
	static func activatePlayback() {
		Task.detached(priority: .userInitiated) {
			await activatePlaybackAsync()
		}
	}

	static func activatePlaybackAsync() async {
		let session = AVAudioSession.sharedInstance()
		do {
			try session.setCategory(.playback, mode: .moviePlayback, options: [])
			try session.setActive(true)
		} catch {
			print("[audio] activate failed: \(error)")
		}
	}
}
