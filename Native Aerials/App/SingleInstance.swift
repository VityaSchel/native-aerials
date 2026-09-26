import AppKit

enum SingleInstance {
	static func olderCopy() -> NSRunningApplication? {
		guard let identifier = Bundle.main.bundleIdentifier else {
			return nil
		}
		let current = NSRunningApplication.current
		let rank = { (app: NSRunningApplication) in (app.launchDate ?? .distantFuture, app.processIdentifier) }
		return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first {
			$0 != current && $0.activationPolicy == .regular && !$0.isTerminated && rank($0) < rank(current)
		}
	}

	static func handOffToOlderCopy() -> Bool {
		guard let other = olderCopy() else {
			return false
		}
		NSApp.yieldActivation(to: other)
		other.activate()
		return true
	}
}
