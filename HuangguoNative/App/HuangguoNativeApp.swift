import SwiftUI

@main
struct HuangguoNativeApp: App {
	init() {
		AudioSession.activatePlayback()
	}

	var body: some Scene {
		WindowGroup {
			RootTabView()
		}
	}
}
