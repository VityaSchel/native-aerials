import Foundation

nonisolated struct DryRun: Sendable {
	static let option = "--dry-run"

	let directory: URL

	var root: URL { directory.appending(path: "root", directoryHint: .isDirectory) }
	var preferencesFile: URL { directory.appending(path: "prefs/\(AerialPreferences.domain).plist") }
	var launchAgents: URL { directory.appending(path: "LaunchAgents", directoryHint: .isDirectory) }
	var supportDirectory: URL { directory.appending(path: "support", directoryHint: .isDirectory) }
	var loadedJobs: URL { directory.appending(path: "launchd", directoryHint: .isDirectory) }
	var lockFile: URL { directory.appending(path: "engine.lock") }
	var downloadActivityFile: URL { directory.appending(path: "downloads-in-flight") }
	var actionsLog: URL { directory.appending(path: "actions.log") }

	var arguments: [String] { [Self.option, directory.path] }

	static var environmentPath: String? {
		ProcessInfo.processInfo.environment["NATIVE_AERIALS_DRY_RUN"].flatMap { $0.isEmpty ? nil : $0 }
	}

	static func prepare(_ path: String) throws -> DryRun {
		let fileManager = FileManager.default
		try fileManager.createDirectory(atPath: path + "/root", withIntermediateDirectories: true)
		guard let resolved = SystemInfo.resolvedPath(path) else {
			throw InstallerError("cannot resolve \(path)")
		}
		let dryRun = DryRun(directory: URL(filePath: resolved, directoryHint: .isDirectory))
		try Data().write(to: dryRun.actionsLog)
		return dryRun
	}

	func record(_ action: String) {
		guard let handle = try? FileHandle(forWritingTo: actionsLog) else {
			return
		}
		defer { try? handle.close() }
		_ = try? handle.seekToEnd()
		try? handle.write(contentsOf: Data((action + "\n").utf8))
	}
}

nonisolated struct Locations: Sendable {
	static let extensionBundle = URL(filePath: "/System/Library/ExtensionKit/Extensions/WallpaperAerialsExtension.appex")
	static let extensionBinary = extensionBundle.appending(path: "Contents/MacOS/WallpaperAerialsExtension")
	static let extensionResources = extensionBundle.appending(path: "Contents/Resources", directoryHint: .isDirectory)
	static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!
	static let dateTimeSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Date-Time-Settings.extension")!

	let dryRun: DryRun?
	let home: URL
	let realWallpaperRoot: URL
	let wallpaperRoot: URL
	let launchAgents: URL
	let bundledCatalog: URL
	let downloadedCatalog: URL
	let videosDirectory: URL
	let applicationFolders: [String]?
	let environment: [String: String]

	init(dryRun: DryRun?, environment: [String: String] = ProcessInfo.processInfo.environment) {
		let environment = dryRun == nil ? [:] : environment
		let home = FileManager.default.homeDirectoryForCurrentUser
		let realRoot = home.appending(path: "Library/Application Support/com.apple.wallpaper", directoryHint: .isDirectory)
		self.dryRun = dryRun
		self.home = home
		self.environment = environment
		realWallpaperRoot = realRoot
		wallpaperRoot = dryRun?.root ?? realRoot
		launchAgents = dryRun?.launchAgents ?? home.appending(path: "Library/LaunchAgents", directoryHint: .isDirectory)
		let fixture = { (key: String) in environment[key].flatMap { $0.isEmpty ? nil : $0 } }
		bundledCatalog = fixture("NATIVE_AERIALS_BUNDLED").map { URL(filePath: $0) }
			?? Self.extensionResources.appending(path: "entries.json")
		downloadedCatalog = fixture("NATIVE_AERIALS_MANIFEST").map { URL(filePath: $0) }
			?? realRoot.appending(path: "aerials/manifest/entries.json")
		videosDirectory = fixture("NATIVE_AERIALS_VIDEOS").map { URL(filePath: SystemInfo.resolvedPath($0) ?? $0, directoryHint: .isDirectory) }
			?? realRoot.appending(path: "aerials/videos", directoryHint: .isDirectory)
		applicationFolders = dryRun == nil
			? SystemInfo.applicationFolders(home: home)
			: fixture("NATIVE_AERIALS_APPLICATIONS").map { $0.split(separator: ":").map(String.init) }
	}

	var catalogTarget: String { realWallpaperRoot.appending(path: "aerials/custom/entries.json").path }
	var realCustomDirectory: URL { realWallpaperRoot.appending(path: "aerials/custom", directoryHint: .isDirectory) }
	var customDirectory: URL { wallpaperRoot.appending(path: "aerials/custom", directoryHint: .isDirectory) }
	var catalogFile: URL { customDirectory.appending(path: "entries.json") }
	var stateFile: URL { customDirectory.appending(path: "native-aerials.json") }
	var manifestDirectory: URL { realWallpaperRoot.appending(path: "aerials/manifest", directoryHint: .isDirectory) }
	var thumbnailsDirectory: URL { realWallpaperRoot.appending(path: "aerials/thumbnails", directoryHint: .isDirectory) }
	var realIndexFile: URL { realWallpaperRoot.appending(path: "Store/Index.plist") }
	var indexFile: URL { wallpaperRoot.appending(path: "Store/Index.plist") }
	var stagedIndexFile: URL { wallpaperRoot.appending(path: "Store/.Index.plist.native-aerials") }
	var preferencesFile: URL {
		dryRun?.preferencesFile ?? home.appending(path: "Library/Preferences/\(AerialPreferences.domain).plist")
	}
	var supportDirectory: URL {
		dryRun?.supportDirectory ?? home.appending(path: "Library/Application Support/Native Aerials", directoryHint: .isDirectory)
	}
	var automaticRecordFile: URL { supportDirectory.appending(path: "automatic-choices.json") }
	var lockFile: URL {
		dryRun?.lockFile ?? SystemInfo.userTemporaryDirectory.appending(path: "dev.hloth.native-aerials.lock")
	}
	var downloadActivityFile: URL {
		dryRun?.downloadActivityFile ?? SystemInfo.userTemporaryDirectory.appending(path: "dev.hloth.native-aerials.downloads")
	}

	func allowsApp(at path: String) -> Bool {
		SystemInfo.isAllowedLocation(path, applicationFolders: applicationFolders)
	}

	var indexSource: URL {
		FileManager.default.fileExists(atPath: indexFile.path) ? indexFile : realIndexFile
	}

	var lockTimeout: TimeInterval {
		guard let text = environment["NATIVE_AERIALS_LOCK_TIMEOUT"], let seconds = TimeInterval(text) else {
			return 30
		}
		return seconds
	}

	var desktopSpaceIDs: Set<String>? { spaceIDs(desktopsOnly: true) }
	var liveSpaceIDs: Set<String>? { spaceIDs(desktopsOnly: false) }

	private func spaceIDs(desktopsOnly: Bool) -> Set<String>? {
		guard let list = environment["NATIVE_AERIALS_SPACES"] else {
			return SystemInfo.spaceIDs(desktopsOnly: desktopsOnly)
		}
		let ids = Set(list.split(separator: ",").map(String.init))
		return ids.isEmpty ? nil : ids
	}

	func videoFile(forAssetID id: String) -> URL {
		videosDirectory.appending(path: "\(id).mov")
	}

	func isDownloaded(assetID id: String) -> Bool {
		var info = stat()
		return stat(videoFile(forAssetID: id).path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG && info.st_size > 0
	}

	func thumbnail(forID id: String) -> URL? {
		[thumbnailsDirectory, Self.extensionResources].map { $0.appending(path: "\(id).png") }.first { FileManager.default.fileExists(atPath: $0.path) }
	}
}
