import Foundation
import Testing

nonisolated struct LocationsTests {
	@Test(.enabled(if: !SystemInfo.isRoot, "permissions don't apply to root"))
	func locatesTheApp() throws {
		let sandbox = try Sandbox()
		let blocked = sandbox.outside.appending(path: "blocked", directoryHint: .isDirectory)
		let app = blocked.appending(path: "Native Aerials.app", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: app.appending(path: "Contents"), withIntermediateDirectories: true)
		try Data("x".utf8).write(to: app.appending(path: "Contents/Info.plist"))
		#expect(AppLocator.presence(ofCopy: app) == .exists)
		var locator = AppLocator(locations: sandbox.paths)
		locator.gracePeriod = 0
		locator.confirmationDelay = 0
		locator.registeredCopies = { [] }
		try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: blocked.path)
		defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: blocked.path) }
		#expect(AppLocator.presence(ofCopy: app) == .unknown)
		#expect(locator.locate(AgentRecord(appPath: app.path, appBookmark: nil, sourceDigest: "x")) == .unreachable(URL(filePath: app.path, directoryHint: .isDirectory)))
		let absent = sandbox.outside.appending(path: "no-such/Native Aerials.app", directoryHint: .isDirectory)
		#expect(AppLocator.presence(ofCopy: absent) == .missing)
		#expect(locator.locate(AgentRecord(appPath: absent.path, appBookmark: nil, sourceDigest: "x")) == .gone)
	}

	@Test func onlyApplicationsCanHostTheApp() {
		let home = URL(filePath: "/nonexistent/someone", directoryHint: .isDirectory)
		let folders = SystemInfo.applicationFolders(home: home)
		#expect(folders == ["/Applications", "/nonexistent/someone/Applications"])
		#expect(SystemInfo.applicationFolders(home: URL(filePath: "/Volumes/External/Users/someone", directoryHint: .isDirectory)) == ["/Applications"])
		let cases = [
			("Applications/Native Aerials.app", true),
			("Applications/Tools/Native Aerials.app", true),
			("Desktop/Native Aerials.app", false),
			("Downloads/Native Aerials.app", false),
			("Documents/Apps/Native Aerials.app", false),
			("Library/Mobile Documents/com~apple~CloudDocs/Native Aerials.app", false),
			("Library/Developer/Xcode/DerivedData/Native_Aerials-abc/Build/Products/Debug/Native Aerials.app", false),
			(".Trash/Native Aerials.app", false),
			("ApplicationsOld/Native Aerials.app", false),
		].map { ("\(home.path)/\($0.0)", $0.1) } + [
			("/Applications/Native Aerials.app", true),
			("/Applications/Utilities/Native Aerials.app", true),
			("/Volumes/External/Applications/Native Aerials.app", false),
			("/private/var/folders/ab/xyz/T/AppTranslocation/5E7A/d/Native Aerials.app", false),
			("/private/tmp/Native Aerials.app", false),
			("/Native Aerials.app", false),
		]
		for (app, allowed) in cases {
			#expect(SystemInfo.isAllowedLocation("\(app)/Contents/MacOS/Native Aerials", applicationFolders: folders) == allowed, "\(app)")
		}
		#expect(SystemInfo.isAllowedLocation("/private/tmp/Native Aerials.app/Contents/MacOS/Native Aerials", applicationFolders: nil))
		#expect(!SystemInfo.isAllowedLocation("\(home.path)/.Trash/Native Aerials.app/Contents/MacOS/Native Aerials", applicationFolders: nil))
	}

	@Test func handsOffOnlyToOpenedCopies() throws {
		let sandbox = try Sandbox()
		let app = sandbox.outside.appending(path: "Native Aerials.app", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
		#expect(AppLocator.isApproved(app))
		for (flags, approved) in [("0083", false), ("0081", false), ("01c1", true), ("03c1", true), ("??", false)] {
			let quarantine = "\(flags);68cc8650;Safari;"
			#expect(setxattr(app.path, "com.apple.quarantine", quarantine, quarantine.utf8.count, 0, 0) == 0)
			#expect(AppLocator.isApproved(app) == approved, "\(flags)")
		}
		#expect(!AppLocator.isApproved(sandbox.outside.appending(path: "Missing.app", directoryHint: .isDirectory)))
	}

	@Test func honorsTestOverridesOnlyInDryRun() throws {
		let sandbox = try Sandbox()
		let overrides = ["NATIVE_AERIALS_BUNDLED": "/x/bundled.json", "NATIVE_AERIALS_MANIFEST": "/x/manifest.json", "NATIVE_AERIALS_VIDEOS": "/x/videos", "NATIVE_AERIALS_DEFAULT_VIDEO": "/x/default.mov", "NATIVE_AERIALS_SPACES": "A,B", "NATIVE_AERIALS_APPLICATIONS": "/x/Apps:/x/More"]
		let real = Locations(dryRun: nil, environment: overrides)
		#expect(![real.bundledCatalog, real.downloadedCatalog, real.videosDirectory, real.defaultVideo].contains { $0.path.hasPrefix("/x/") })
		#expect(real.environment.isEmpty && real.applicationFolders == SystemInfo.applicationFolders(home: real.home))
		let dry = Locations(dryRun: sandbox.dryRun, environment: overrides)
		#expect(dry.bundledCatalog.path == "/x/bundled.json" && dry.downloadedCatalog.path == "/x/manifest.json" && dry.videosDirectory.path == "/x/videos" && dry.defaultVideo.path == "/x/default.mov")
		#expect(dry.applicationFolders == ["/x/Apps", "/x/More"] && sandbox.paths.applicationFolders == nil)
		#expect(dry.desktopSpaceIDs == ["A", "B"])
		#expect(Locations(dryRun: sandbox.dryRun, environment: ["NATIVE_AERIALS_SPACES": ""]).desktopSpaceIDs == nil)
	}

	@Test func readsDesktopSpacesFromTheSpacesConfiguration() {
		let fullScreen: [String: Any] = ["uuid": "FULL", "type": 4, "WallSpace": ["uuid": "WALL", "type": 6], "TileLayoutManager": ["TileSpaces": [["uuid": "TILE", "type": 5]]]]
		let configuration: [String: Any] = ["Management Data": ["Monitors": [
			["Current Space": fullScreen, "Spaces": [["uuid": "DESK", "type": 0], fullScreen]],
			["Collapsed Space": ["uuid": "OTHER", "type": 0]],
		]]]
		#expect(SystemInfo.spaceIDs(in: configuration, desktopsOnly: true) == ["DESK", "OTHER"])
		#expect(SystemInfo.spaceIDs(in: ["Monitors": [["uuid": "FULL", "type": 4]]], desktopsOnly: true) == nil)
		#expect(SystemInfo.spaceIDs(in: configuration, desktopsOnly: false) == ["DESK", "FULL", "WALL", "TILE", "OTHER"])
		let single = SystemInfo.spaceIDs(in: ["Monitors": [["Current Space": ["uuid": "", "type": 0], "Spaces": [["uuid": "", "type": 0], ["uuid": "FULL", "type": 4]]]]], desktopsOnly: true)
		#expect(single == [""])
		var root = WallpaperIndexTests.otherSpaceUsedLater.root
		root = IndexFixture.renamingSpace(root, IndexFixture.liveSpace, to: "")
		root = IndexFixture.renamingSpace(root, IndexFixture.otherSpace, to: "FULL")
		let index = WallpaperIndex(root: root)
		#expect(index.inUse(spaces: single, includingRecent: false).currentDesktopAssetID == AerialSet.tahoe.day.assetID)
		#expect(index.inUse(spaces: nil, includingRecent: false).currentDesktopAssetID == AerialSet.tahoe.evening.assetID)
	}

	@MainActor @Test func engineRunsWorkOffTheMainThread() async throws {
		let sandbox = try Sandbox()
		let engine = try sandbox.engine()
		let (snapshot, ranOnMain) = try await engine.run { ($0.snapshot(), Thread.isMainThread) }
		#expect(!ranOnMain)
		#expect(snapshot.sets.map(\.subcategoryID) == (try sandbox.installer().mergePlan().listedSets.map(\.subcategoryID)))
		#expect(snapshot.dryRunDirectory == sandbox.directory.path)
	}
}
