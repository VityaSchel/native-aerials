import AppKit
import SwiftUI

nonisolated enum HintPlacement {
	static let toolbarHeight: CGFloat = 52
	static let sidebarWidth: CGFloat = 240
	static let trafficLightsWidth: CGFloat = 96
	static let margin: CGFloat = 8

	static func appKitFrame(ofCGBounds bounds: CGRect, primaryHeight: CGFloat) -> CGRect {
		CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
	}

	static func origin(of size: CGSize, pointingInto window: CGRect, screens: [CGRect]) -> CGPoint? {
		let overlap = { (screen: CGRect) in screen.intersection(window).width * screen.intersection(window).height }
		guard let screen = screens.max(by: { overlap($0) < overlap($1) }) else {
			return nil
		}
		let tipX = (window.minX + sidebarWidth + window.maxX) / 2
		let lowX = max(screen.minX + margin, window.minX + trafficLightsWidth)
		let highX = min(screen.maxX, window.maxX) - margin - size.width
		let y = min(window.maxY - toolbarHeight, screen.maxY - size.height)
		guard lowX <= highX, y >= max(screen.minY, window.minY) else {
			return nil
		}
		return CGPoint(x: min(max(tipX - size.width / 2, lowX), highX), y: y)
	}
}

final class SettingsHint {
	private static let settingsBundleID = "com.apple.systempreferences"
	private static let lifetime: TimeInterval = 20
	private static let appearTimeout: TimeInterval = 3
	private static let fadeDuration: TimeInterval = 0.12
	private static let pollInterval = Duration.milliseconds(16)

	private var task: Task<Void, Never>?

	func show(_ text: String, thumbnail: NSImage?, while isRelevant: @escaping () -> Bool) {
		task?.cancel()
		task = Task {
			let panel = Self.makePanel(text, thumbnail: thumbnail)
			await Self.follow(panel, announcing: text, while: isRelevant)
			await Self.fade(panel, to: 0)
			panel.orderOut(nil)
		}
	}

	static func makePanel(_ text: String, thumbnail: NSImage? = nil) -> NSPanel {
		let host = NSHostingView(rootView: HintBubble(text: text, thumbnail: thumbnail))
		let panel = NSPanel(contentRect: CGRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
		panel.contentView = host
		panel.level = .floating
		panel.isOpaque = false
		panel.backgroundColor = .clear
		panel.hasShadow = true
		panel.ignoresMouseEvents = true
		panel.hidesOnDeactivate = false
		panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
		panel.alphaValue = 0
		return panel
	}

	private static func follow(_ panel: NSPanel, announcing text: String, while isRelevant: () -> Bool) async {
		let started = Date.now
		var wasShown = false
		var isShown = false
		while !Task.isCancelled, isRelevant() {
			let age = Date.now.timeIntervalSince(started)
			let window = settingsWindow()
			guard age < lifetime, window != nil || !wasShown && age < appearTimeout else {
				break
			}
			let origin = window.flatMap { HintPlacement.origin(of: panel.frame.size, pointingInto: $0, screens: NSScreen.screens.map(\.visibleFrame)) }
			if let origin, origin != panel.frame.origin {
				panel.setFrameOrigin(origin)
			}
			let shows = origin != nil && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == settingsBundleID
			if shows, !wasShown {
				wasShown = true
				AccessibilityNotification.Announcement(text).post()
			}
			if shows != isShown {
				isShown = shows
				if shows {
					panel.orderFrontRegardless()
					panel.invalidateShadow()
				}
				Task { await fade(panel, to: shows ? 1 : 0) }
			}
			try? await Task.sleep(for: pollInterval)
		}
		if !wasShown, !Task.isCancelled, isRelevant() {
			AccessibilityNotification.Announcement(text).post()
		}
	}

	private static func fade(_ panel: NSPanel, to alpha: CGFloat) async {
		await NSAnimationContext.runAnimationGroup { context in
			context.duration = fadeDuration
			panel.animator().alphaValue = alpha
		}
	}

	private static func settingsWindow() -> CGRect? {
		let owners = Set(NSRunningApplication.runningApplications(withBundleIdentifier: settingsBundleID).map(\.processIdentifier))
		let windows = owners.isEmpty ? [] : CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
		let frames = windows
			.filter { ($0[kCGWindowOwnerPID as String] as? pid_t).map(owners.contains) == true && $0[kCGWindowLayer as String] as? Int == 0 }
			.compactMap { ($0[kCGWindowBounds as String] as? NSDictionary).flatMap(CGRect.init(dictionaryRepresentation:)) }
		guard let primary = NSScreen.screens.first, let largest = frames.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
			return nil
		}
		return HintPlacement.appKitFrame(ofCGBounds: largest, primaryHeight: primary.frame.height)
	}
}
