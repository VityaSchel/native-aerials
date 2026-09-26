import AppKit
import SwiftUI

extension View {
	func hudWindowChrome() -> some View {
		containerBackground(for: .window) {
			VisualEffectBackground(material: .hudWindow)
		}
		.background(WindowChrome())
	}
}

struct VisualEffectBackground: NSViewRepresentable {
	let material: NSVisualEffectView.Material

	func makeNSView(context: Context) -> NSVisualEffectView {
		let view = NSVisualEffectView()
		view.blendingMode = .behindWindow
		view.state = .active
		return view
	}

	func updateNSView(_ view: NSVisualEffectView, context: Context) {
		view.material = material
	}
}

private struct WindowChrome: NSViewRepresentable {
	func makeNSView(context: Context) -> ChromeView {
		ChromeView()
	}

	func updateNSView(_ view: ChromeView, context: Context) {
		view.applyChrome()
	}

	final class ChromeView: NSView {
		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			applyChrome()
		}

		func applyChrome() {
			guard let window else {
				return
			}
			window.isOpaque = false
			window.backgroundColor = .clear
		}
	}
}
