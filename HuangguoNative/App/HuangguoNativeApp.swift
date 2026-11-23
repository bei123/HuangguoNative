import SwiftUI

@main
struct HuangguoNativeApp: App {
	init() {
		AudioSession.activatePlayback()
		// 启动即并行测速备用域名，后续 Edge 请求走最快线路
		Task { await EndpointRouter.shared.ensureReady() }
	}

	var body: some Scene {
		WindowGroup {
			RootTabView()
		}
	}
}
