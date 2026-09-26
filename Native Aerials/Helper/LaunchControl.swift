import Foundation

nonisolated struct LaunchControl {
	static let tool = "/bin/launchctl"

	let label: String
	let dryRun: DryRun?

	private var domain: String { "gui/\(getuid())" }
	private var service: String { "\(domain)/\(label)" }
	private var dryRunMarker: URL? { dryRun?.loadedJobs.appending(path: label) }

	var isLoaded: Bool {
		if let dryRunMarker {
			return FileManager.default.fileExists(atPath: dryRunMarker.path)
		}
		return Subprocess.run(Self.tool, ["print", service]).status == 0
	}

	func reload(_ plist: URL) throws {
		if isLoaded {
			bootout()
			let deadline = Date.now.addingTimeInterval(25)
			while isLoaded && Date.now < deadline {
				Thread.sleep(forTimeInterval: 0.1)
			}
		}
		try bootstrap(plist)
	}

	func bootstrap(_ plist: URL) throws {
		if let dryRun, let dryRunMarker {
			dryRun.record("launchctl bootstrap \(domain) \(plist.path)")
			try FileManager.default.createDirectory(at: dryRun.loadedJobs, withIntermediateDirectories: true)
			try Data(plist.path.utf8).write(to: dryRunMarker)
			return
		}
		guard Subprocess.run(Self.tool, ["bootstrap", domain, plist.path]).status == 0 || isLoaded else {
			throw InstallerError(
				"launchctl bootstrap \(domain) \(plist.path) failed",
				summary: "The background helper couldn’t start. If Native Aerials is turned off in Login Items, turn it on."
			)
		}
	}

	func bootout() {
		if let dryRun, let dryRunMarker {
			dryRun.record("launchctl bootout \(service)")
			try? FileManager.default.removeItem(at: dryRunMarker)
			return
		}
		Subprocess.run(Self.tool, ["bootout", service])
	}
}
