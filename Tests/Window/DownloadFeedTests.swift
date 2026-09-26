import Foundation
import Testing

struct DownloadFeedTests {
	nonisolated static var canStreamTheLog: Bool {
		getuid() == 0 || Subprocess.run("/usr/bin/id", ["-Gn"]).output.split(whereSeparator: \.isWhitespace).contains("admin")
	}

	static func feedProcesses() -> Int {
		Subprocess.run("/usr/bin/pgrep", ["-P", String(getpid()), "-f", "log stream"]).output.split(separator: "\n").count
	}

	@Test(.enabled(if: canStreamTheLog, "log stream needs an admin account"))
	func readsTheLogOnlyWhileTheWindowIsOpen() async throws {
		let sandbox = try Sandbox()
		let window = WindowHarness(sandbox)
		try await window.start(watchingDownloads: true)
		defer { window.stop() }
		#expect(await window.until(5) { Self.feedProcesses() == 1 })
		window.send(AerialSet.tahoe.morning, .requested)
		#expect(window.marker.contains(AerialSet.tahoe.morning.assetID))
		window.model.stopWatchingDownloads()
		#expect(await window.until(5) { Self.feedProcesses() == 0 })
		#expect(window.marker.isEmpty && !sandbox.exists(sandbox.paths.downloadActivityFile))
	}
}
