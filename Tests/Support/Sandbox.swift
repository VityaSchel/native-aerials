import Foundation
import Testing

nonisolated struct CommandResult {
	let status: Int32
	let output: String
	let error: String

	var lines: [String] { output.split(separator: "\n").map(String.init) }
}

nonisolated final class Sandbox {
	static let builtApp = Bundle(for: Sandbox.self).bundleURL.deletingLastPathComponent().appending(path: "Native Aerials.app", directoryHint: .isDirectory)
	static let overrideKey = AerialPreferences.overrideKey
	static let forceLocalKey = AerialPreferences.forceLocalKey
	static let turnOnActions = ["set \(overrideKey)", "set \(forceLocalKey)", "restart", "bootstrap \(AgentJob.label)"]
	static let turnOnRestoringActions = ["set \(overrideKey)", "set \(forceLocalKey)", "replace", "restart", "bootstrap \(AgentJob.label)"]
	static let turnOffActions = ["delete \(overrideKey)", "delete \(forceLocalKey)", "remove-custom", "replace", "restart", "bootout \(AgentJob.label)"]

	let root: URL
	let directory: URL
	let dryRun: DryRun
	let paths: Locations
	var environment: [String: String] = [:]
	private var clonedApp: URL?

	var videos: URL { directory.appending(path: "videos", directoryHint: .isDirectory) }
	var defaultVideo: URL { directory.appending(path: "default/Golden Gate.mov") }
	var bundledCatalog: URL { directory.appending(path: "catalogs/bundled.json") }
	var manifest: URL { directory.appending(path: "catalogs/manifest.json") }
	var outside: URL { root.appending(path: "outside", directoryHint: .isDirectory) }
	var apps: URL { directory.appending(path: "Apps", directoryHint: .isDirectory) }
	var helper: URL { AgentHelper(directory: paths.supportDirectory).executable }
	var agentFile: URL { AgentJob.file(in: paths.launchAgents) }
	var agentRecordFile: URL { paths.supportDirectory.appending(path: AgentHelper.recordName) }
	var liveSpaces: Set<String> { Set((environment["NATIVE_AERIALS_SPACES"] ?? "").split(separator: ",").map(String.init)) }

	init(index: [String: Any] = IndexFixture.standard(), catalog: CatalogFixture = CatalogFixture(), videos placed: [AerialVideo] = []) throws {
		let base = FileManager.default.temporaryDirectory.appending(path: "NativeAerialsTests/\(UUID().uuidString)", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: base.appending(path: "dry"), withIntermediateDirectories: true)
		root = URL(filePath: try #require(SystemInfo.resolvedPath(base.path)), directoryHint: .isDirectory)
		let temporary = SystemInfo.resolvedPath(FileManager.default.temporaryDirectory.path) ?? FileManager.default.temporaryDirectory.path
		let home = SystemInfo.resolvedPath(FileManager.default.homeDirectoryForCurrentUser.path) ?? FileManager.default.homeDirectoryForCurrentUser.path
		try #require(root.path.hasPrefix(temporary + "/"), "sandbox \(root.path) is outside the temporary folder \(temporary)")
		try #require(!root.path.hasPrefix(home + "/Library/") && !root.path.hasPrefix("/Applications/"), "sandbox \(root.path) is in a real system location")
		dryRun = try DryRun.prepare(root.appending(path: "dry").path)
		directory = dryRun.directory
		paths = Locations(dryRun: dryRun, environment: [:])
		environment = [
			"NATIVE_AERIALS_DRY_RUN": directory.path,
			"NATIVE_AERIALS_BUNDLED": bundledCatalog.path,
			"NATIVE_AERIALS_MANIFEST": manifest.path,
			"NATIVE_AERIALS_VIDEOS": videos.path,
			"NATIVE_AERIALS_DEFAULT_VIDEO": defaultVideo.path,
			"NATIVE_AERIALS_SPACES": IndexFixture.liveSpace,
			"NATIVE_AERIALS_REGISTERED_APPS": "",
			"NATIVE_AERIALS_CONFIRM_DELAY": "1",
			"NATIVE_AERIALS_LOCK_TIMEOUT": "5",
		]
		_ = try locations()
		for folder in [videos, defaultVideo.deletingLastPathComponent(), outside, bundledCatalog.deletingLastPathComponent(), paths.preferencesFile.deletingLastPathComponent(), paths.indexFile.deletingLastPathComponent()] {
			try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		}
		try PropertyListSerialization.data(fromPropertyList: [String: Any](), format: .xml, options: 0).write(to: paths.preferencesFile)
		try writeIndex(index)
		try catalog.data.write(to: bundledCatalog)
		try catalog.data.write(to: manifest)
		place(placed)
	}

	deinit {
		try? FileManager.default.removeItem(at: root)
	}

	func locations(_ overrides: [String: String] = [:]) throws -> Locations {
		let locations = Locations(dryRun: dryRun, environment: environment.merging(overrides) { $1 })
		try #require(locations.dryRun?.directory == directory)
		let writes = [
			locations.wallpaperRoot, locations.indexFile, locations.stagedIndexFile, locations.catalogFile, locations.stateFile, locations.preferencesFile,
			locations.launchAgents, locations.supportDirectory, locations.automaticRecordFile, locations.lockFile, locations.downloadActivityFile,
		]
		for url in writes {
			try #require(url.path.hasPrefix(directory.path + "/"), "\(url.path) is outside the dry run")
		}
		for url in [locations.bundledCatalog, locations.downloadedCatalog, locations.videosDirectory, locations.defaultVideo] {
			try #require(url.path.hasPrefix(root.path + "/"), "\(url.path) is outside the sandbox")
		}
		return locations
	}

	func installer(_ overrides: [String: String] = [:]) throws -> Installer {
		Installer(locations: try locations(overrides), log: Log(echoes: false))
	}

	func engine(_ overrides: [String: String] = [:]) throws -> Engine {
		Engine(locations: try locations(overrides))
	}

	func snapshot(_ overrides: [String: String] = [:]) throws -> WallpaperSnapshot {
		WallpaperSnapshot(try installer(overrides))
	}

	var app: URL {
		get throws {
			if let clonedApp {
				return clonedApp
			}
			let target = apps.appending(path: "Native Aerials.app", directoryHint: .isDirectory)
			try cloneApp(to: target)
			clonedApp = target
			return target
		}
	}

	func cloneApp(to target: URL) throws {
		try #require(FileManager.default.fileExists(atPath: Self.builtApp.path), "Native Aerials.app is not built next to the test bundle")
		try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
		try FileManager.default.copyItem(at: Self.builtApp, to: target)
	}

	static func executable(of app: URL) -> URL {
		app.appending(path: "Contents/MacOS/Native Aerials")
	}

	@discardableResult
	func run(_ arguments: String..., executable: URL? = nil, environment overrides: [String: String] = [:]) async throws -> CommandResult {
		try await run(arguments, executable: executable, environment: overrides)
	}

	@discardableResult
	func run(_ arguments: [String], executable: URL? = nil, environment overrides: [String: String] = [:]) async throws -> CommandResult {
		let executable = try executable ?? Self.executable(of: app)
		_ = try locations(overrides)
		return try await execute(executable, arguments + dryRun.arguments, environment: Self.inherited.merging(environment) { $1 }.merging(overrides) { $1 })
	}

	func tool(_ path: String, _ arguments: String...) async throws -> CommandResult {
		try await execute(URL(filePath: path), arguments, environment: Self.inherited)
	}

	private static var inherited: [String: String] {
		ProcessInfo.processInfo.environment.filter { ["HOME", "PATH", "TMPDIR"].contains($0.key) }
	}

	private func execute(_ executable: URL, _ arguments: [String], environment: [String: String]) async throws -> CommandResult {
		let logs = root.appending(path: "logs", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
		let name = UUID().uuidString
		let output = logs.appending(path: "\(name).out")
		let error = logs.appending(path: "\(name).err")
		FileManager.default.createFile(atPath: output.path, contents: nil)
		FileManager.default.createFile(atPath: error.path, contents: nil)
		let process = Process()
		process.executableURL = executable
		process.arguments = arguments
		process.environment = environment
		process.currentDirectoryURL = root
		process.standardInput = FileHandle.nullDevice
		process.standardOutput = try FileHandle(forWritingTo: output)
		process.standardError = try FileHandle(forWritingTo: error)
		let status = try await Self.wait(for: process)
		return CommandResult(
			status: status,
			output: (try? String(contentsOf: output, encoding: .utf8)) ?? "",
			error: (try? String(contentsOf: error, encoding: .utf8)) ?? ""
		)
	}

	private static func wait(for process: Process, timeout: TimeInterval = 90) async throws -> Int32 {
		try await withCheckedThrowingContinuation { continuation in
			process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
			do {
				try process.run()
			} catch {
				process.terminationHandler = nil
				continuation.resume(throwing: error)
				return
			}
			let pid = process.processIdentifier
			DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak process] in
				if process?.isRunning == true {
					kill(pid, SIGKILL)
				}
			}
		}
	}

	var rawActions: [String] {
		((try? String(contentsOf: dryRun.actionsLog, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
	}

	var actions: [String] { rawActions.compactMap(Self.normalized) }

	var restarts: Int { actions.filter { $0 == "restart" }.count }

	static func normalized(_ action: String) -> String? {
		let words = action.split(separator: " ").map(String.init)
		switch words.first {
		case "/usr/bin/open": return nil
		case "/usr/bin/killall": return "restart"
		case "replace": return "replace"
		case "remove": return "remove-custom"
		case "set", "delete": return words.count > 2 && words[1] == AerialPreferences.domain ? "\(words[0]) \(words[2])" : action
		case "launchctl" where words.count > 2 && words[1] == "bootstrap":
			return "bootstrap " + URL(filePath: words.dropFirst(3).joined(separator: " ")).deletingPathExtension().lastPathComponent
		case "launchctl" where words.count > 2 && words[1] == "bootout":
			return "bootout " + (words[2].split(separator: "/").last.map(String.init) ?? "")
		default: return action
		}
	}

	var ownBootout: String { "launchctl bootout gui/\(getuid())/\(AgentJob.label)" }

	var installedCatalog: AerialCatalog? { AerialCatalog.loadIfValid(paths.catalogFile) }

	var combinedSetIDs: Set<String> { Set(installedCatalog?.combinedSets.map(\.subcategoryID) ?? []) }

	func anchors(of set: AerialSet) -> Int {
		(installedCatalog?.assetDictionaries ?? []).filter { AerialCatalog.belongs($0, to: set.subcategoryID) && !JSONTree.isNull(AerialCatalog.solar(of: $0)) }.count
	}

	var state: InstallState? { InstallState.load(from: paths.stateFile) }

	var record: AutomaticRecord? { AutomaticRecord.load(from: paths.automaticRecordFile) }

	var agentRecord: AgentRecord? { AgentRecord.load(from: agentRecordFile) }

	var agentPlist: [String: Any]? { Self.plist(at: agentFile) }

	var preferences: [String: Any] { Self.plist(at: paths.preferencesFile) ?? [:] }

	var hasOverride: Bool { preferences[Self.overrideKey] != nil }

	func setPreference(_ key: String, _ value: Any?) throws {
		var preferences = preferences
		preferences[key] = value
		try PropertyListSerialization.data(fromPropertyList: preferences, format: .xml, options: 0).write(to: paths.preferencesFile)
	}

	var indexRoot: [String: Any] {
		get throws { try WallpaperIndex(data: Data(contentsOf: paths.indexFile)).root }
	}

	func writeIndex(_ root: [String: Any]) throws {
		try WallpaperIndex(root: root).data().write(to: paths.indexFile, options: .atomic)
	}

	func editIndex(_ change: ([String: Any]) -> [String: Any]) throws {
		try writeIndex(change(indexRoot))
	}

	var desktops: IndexFixture.Desktops {
		get throws { IndexFixture.desktops(of: try indexRoot) }
	}

	var liveDesktops: IndexFixture.Desktops {
		get throws { IndexFixture.desktops(of: try indexRoot) { !IndexFixture.isDead($0, live: liveSpaces) } }
	}

	var deadDesktops: IndexFixture.Desktops {
		get throws { IndexFixture.desktops(of: try indexRoot) { IndexFixture.isDead($0, live: liveSpaces) } }
	}

	var savedChoiceIDs: Set<String> {
		get throws { WallpaperIndex(root: try indexRoot).choiceAssetIDs }
	}

	func repaint(dead: Bool, with choice: [String: Any], lastUse: Date? = nil) throws {
		let live = liveSpaces
		try editIndex { IndexFixture.repainting($0, where: { IndexFixture.isDead($0, live: live) == dead }, with: choice, lastUse: lastUse) }
	}

	func file(_ video: AerialVideo) -> URL {
		videos.appending(path: "\(video.assetID).mov")
	}

	func exists(_ video: AerialVideo) -> Bool {
		FileManager.default.fileExists(atPath: file(video).path)
	}

	func place(_ videos: [AerialVideo]) {
		for video in videos {
			FileManager.default.createFile(atPath: file(video).path, contents: Data("x".utf8))
		}
	}

	func remove(_ videos: [AerialVideo]) {
		for video in videos {
			try? FileManager.default.removeItem(at: file(video))
		}
	}

	func markDownloading(_ ids: [String], age: TimeInterval = 0) throws {
		try Data(ids.map { $0 + "\n" }.joined().utf8).write(to: paths.downloadActivityFile)
		try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-age)], ofItemAtPath: paths.downloadActivityFile.path)
	}

	func clearDownloads() {
		try? FileManager.default.removeItem(at: paths.downloadActivityFile)
	}

	func makeStateStale() throws {
		var state = try #require(state)
		state.osBuild = "25Z999"
		try state.save(to: paths.stateFile)
	}

	func write(_ catalog: CatalogFixture, named name: String) throws -> URL {
		let url = directory.appending(path: "catalogs/\(name).json")
		try catalog.data.write(to: url)
		return url
	}

	func write(_ data: Data, named name: String) throws -> URL {
		let url = directory.appending(path: "catalogs/\(name).json")
		try data.write(to: url)
		return url
	}

	func digest(_ url: URL) -> String {
		SystemInfo.sha256(of: url)
	}

	func exists(_ url: URL) -> Bool {
		FileManager.default.fileExists(atPath: url.path)
	}

	func contents(of folder: URL) -> [String] {
		((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
	}

	static func plist(at url: URL) -> [String: Any]? {
		(try? Data(contentsOf: url)).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
	}

	static func resolved(_ url: URL) -> String {
		SystemInfo.resolvedPath(url.path) ?? url.path
	}
}
