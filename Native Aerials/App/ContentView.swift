import AppKit
import SwiftUI

struct ContentView: View {
	let model: AppModel

	var body: some View {
		AerialsPanel(
			rows: model.state.rows,
			isLoaded: model.state.isLoaded,
			images: model.thumbnails.images,
			footnote: model.state.footnote,
			choose: { model.choose($0) },
			chooseMerged: { model.chooseMerged($0) },
			remove: { model.removeDownload($0) },
			open: { model.open($0) }
		)
		.toolbar {
			TitleBarControls(
				isOn: Binding {
					model.state.switchIsOn
				} set: { isOn in
					model.setEnabled(isOn)
				},
				isLoaded: model.state.isLoaded,
				isEnabled: model.state.canToggle,
				isWorking: model.state.isWorking
			)
		}
		.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
		.hudWindowChrome()
		.windowMinimizeBehavior(.disabled)
		.windowFullScreenBehavior(.disabled)
		.windowResizeAnchor(.topLeading)
		.task {
			await model.start()
		}
		.task {
			await model.watchLoginItems()
		}
		.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
			if model.state.isReady {
				Task { await model.reload() }
			}
		}
	}
}
