import Foundation

nonisolated struct AgentJob {
	static let label = "dev.hloth.native-aerials.agent"
	static let bundleIdentifier = "dev.hloth.native-aerials"
	static let argument = "--agent"
	static let handedOffArgument = "--handed-off"
	static let reloadArgument = "--reload-agent"
	static let throttleInterval = 5

	let directory: URL
	let helper: URL
	let watchedPaths: [String]

	var file: URL { Self.file(in: directory) }

	static func file(in directory: URL) -> URL {
		directory.appending(path: "\(label).plist")
	}

	func contents() throws -> Data {
		let plist: [String: Any] = [
			"Label": Self.label,
			"ProgramArguments": [helper.path, Self.argument],
			"RunAtLoad": true,
			"WatchPaths": watchedPaths,
			"ThrottleInterval": Self.throttleInterval,
			"ProcessType": "Background",
			"LowPriorityIO": true,
			"AbandonProcessGroup": true,
			"AssociatedBundleIdentifiers": [Self.bundleIdentifier],
		]
		return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
	}

	func digest() throws -> String {
		SystemInfo.sha256(of: try contents())
	}

	func write() throws -> Bool {
		let data = try contents()
		if (try? Data(contentsOf: file)) == data {
			return false
		}
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		try data.write(to: file, options: .atomic)
		return true
	}
}
