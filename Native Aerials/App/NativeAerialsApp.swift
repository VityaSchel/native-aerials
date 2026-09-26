import AppKit
import SwiftUI

@main
enum Launcher {
	static func main() {
		let arguments = CommandLine.arguments
		if CommandLineTool.handles(arguments) {
			exit(CommandLineTool.run(arguments))
		}
		NativeAerialsApp.main()
	}
}

struct NativeAerialsApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

	var body: some Scene {
		Window("Native Aerials", id: "main") {
			ContentView(model: appDelegate.model)
		}
		.windowToolbarStyle(.unified(showsTitle: true))
		.windowResizability(.contentSize)
		.windowBackgroundDragBehavior(.enabled)
		.restorationBehavior(.disabled)
		.defaultLaunchBehavior(.presented)
		.commands {
			StandardMenus()
		}
	}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
	let model = AppModel()

	func applicationWillFinishLaunching(_ notification: Notification) {
		if SingleInstance.handOffToOlderCopy() {
			exit(0)
		}
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		true
	}

	func applicationWillTerminate(_ notification: Notification) {
		model.stopWatchingDownloads()
	}

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		guard model.isWorking else {
			return .terminateNow
		}
		model.quitWhenIdle {
			sender.reply(toApplicationShouldTerminate: true)
		}
		return .terminateLater
	}
}
