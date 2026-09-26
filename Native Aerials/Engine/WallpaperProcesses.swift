import Foundation

nonisolated enum Subprocess {
	@discardableResult
	static func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
		let process = Process()
		let pipe = Pipe()
		process.executableURL = URL(filePath: executable)
		process.arguments = arguments
		process.standardOutput = pipe
		process.standardError = FileHandle.nullDevice
		do {
			try process.run()
		} catch {
			return (-1, "")
		}
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return (process.terminationStatus, String(decoding: data, as: UTF8.self))
	}
}

nonisolated struct WallpaperProcesses {
	static let processNames = ["WallpaperAgent", "WallpaperAerialsExtension"]

	let dryRun: DryRun?
	let log: Log

	static func pid(of name: String) -> String? {
		Subprocess.run("/usr/bin/pgrep", ["-x", "-U", String(getuid()), name]).output
			.split(separator: "\n")
			.first
			.map(String.init)
	}

	func restart(beforeKill prepare: () throws -> Void) rethrows {
		let oldAgent = Self.pid(of: "WallpaperAgent")
		try prepare()
		let killall = ["/usr/bin/killall"] + Self.processNames
		if let dryRun {
			log.note("[dry-run] would run: \(killall.joined(separator: " "))")
			dryRun.record(killall.joined(separator: " "))
			return
		}
		log.note("run: \(killall.joined(separator: " "))")
		Subprocess.run(killall[0], Array(killall.dropFirst()))
		let deadline = Date.now.addingTimeInterval(10)
		while Date.now < deadline {
			if let newAgent = Self.pid(of: "WallpaperAgent"), newAgent != oldAgent {
				return
			}
			Thread.sleep(forTimeInterval: 0.25)
		}
		log.note(
			"WallpaperAgent has not come back yet; macOS starts it again when it is needed",
			notice: "The wallpaper service hasn’t restarted yet. macOS starts it again when it’s needed."
		)
	}

	func pause(seconds: TimeInterval) {
		guard dryRun == nil else {
			return
		}
		Thread.sleep(forTimeInterval: seconds)
	}

	func openWallpaperSettings() {
		let command = "/usr/bin/open \(Locations.settingsURL.absoluteString)"
		if let dryRun {
			log.note("[dry-run] would run: \(command)")
			dryRun.record(command)
			return
		}
		log.note("run: \(command)")
		Subprocess.run("/usr/bin/open", [Locations.settingsURL.absoluteString])
	}
}
