import Foundation
import Testing

nonisolated struct SyncTests {
	static let gg = AerialSet.goldenGate
	static let tahoe = AerialSet.tahoe
	static let allVideos = AerialSet.all.flatMap(\.videos)
	static let bothSets = Set(AerialSet.all.map(\.subcategoryID))

	static func enabled(_ videos: [AerialVideo], index: [String: Any] = IndexFixture.standard()) async throws -> Sandbox {
		let sandbox = try Sandbox(index: index, videos: videos)
		#expect(try await sandbox.run("enable").status == 0)
		return sandbox
	}

	@Test func changesNothingWhenNothingChanged() async throws {
		let sandbox = try await Self.enabled(Self.tahoe.videos + [Self.gg.day])
		let result = try await sandbox.run("sync")
		#expect(result.lines.contains("sync: unchanged") && sandbox.rawActions.isEmpty)
	}

	@Test func combinesASetThatBecameComplete() async throws {
		let sandbox = try await Self.enabled(Self.tahoe.videos + [Self.gg.day])
		let index = sandbox.digest(sandbox.paths.indexFile)
		sandbox.place(Self.gg.videos)
		let result = try await sandbox.run("sync")
		#expect(result.lines.contains("sync: updated"))
		#expect(sandbox.combinedSetIDs == Self.bothSets && sandbox.actions == ["restart"])
		#expect(sandbox.digest(sandbox.paths.indexFile) == index)
		#expect(sandbox.state?.mergedSets == AerialSet.all.map(\.slug))
	}

	@Test func splitsASetThatLostAVideo() async throws {
		let sandbox = try await Self.enabled(Self.allVideos)
		try await sandbox.run("select", Self.tahoe.subcategoryID)
		#expect(try sandbox.desktops == .init(IndexFixture.desktopCount, [Self.tahoe.subcategoryID]))
		sandbox.remove([Self.tahoe.day])
		let result = try await sandbox.run("sync")
		#expect(result.lines.contains("sync: updated"))
		#expect(sandbox.combinedSetIDs == [Self.gg.subcategoryID] && sandbox.actions == ["replace", "restart"])
		#expect(try sandbox.desktops == .init(IndexFixture.desktopCount, [Self.tahoe.morning.assetID]))
		#expect(sandbox.anchors(of: Self.tahoe) == 0 && sandbox.anchors(of: Self.gg) == 4)
		#expect(result.lines.contains("split \(Self.tahoe.displayName): not every video is on disk"))
	}

	@Test func staysOnWhenTheLastCombinedSetLosesAVideo() async throws {
		let sandbox = try await Self.enabled(Self.gg.videos)
		try await sandbox.run("select", Self.gg.subcategoryID)
		sandbox.remove([Self.gg.night])
		let result = try await sandbox.run("sync")
		#expect(result.lines.contains("sync: updated") && sandbox.combinedSetIDs.isEmpty && sandbox.actions == ["replace", "restart"])
		#expect(sandbox.installedCatalog != nil && sandbox.preferences[Sandbox.forceLocalKey] as? Bool == true && sandbox.state?.mergedSets == [])
		#expect(sandbox.exists(sandbox.agentFile) && FileManager.default.isExecutableFile(atPath: sandbox.helper.path))
		#expect(try sandbox.desktops == .init(IndexFixture.desktopCount, [Self.gg.day.assetID]))
		#expect(AerialSet.all.allSatisfy { sandbox.anchors(of: $0) == 0 })
		sandbox.place([Self.gg.night])
		let back = try await sandbox.run("sync")
		#expect(back.lines.contains("sync: updated") && sandbox.combinedSetIDs == [Self.gg.subcategoryID] && sandbox.actions == ["restart"])
	}

	@Test func fallsBackToTheDefaultWallpaperWithNoAerialOnDisk() async throws {
		let sandbox = try await Self.enabled(Self.tahoe.videos)
		try await sandbox.run("select", Self.tahoe.subcategoryID)
		sandbox.remove(Self.tahoe.videos)
		let result = try await sandbox.run("sync")
		#expect(result.lines.contains("sync: updated"))
		let system = try #require(((try sandbox.indexRoot["SystemDefault"] as? [String: Any])?["Linked"] as? [String: Any])?["Content"] as? [String: Any])
		let choice = try #require((system["Choices"] as? [[String: Any]])?.first)
		#expect(choice["Provider"] as? String == "default" && choice["Configuration"] as? Data == Data() && (choice["Files"] as? [Any])?.isEmpty == true)
		#expect(try sandbox.savedChoiceIDs.isDisjoint(with: [Self.tahoe.subcategoryID, Self.tahoe.day.assetID]))
		#expect(result.output.contains("\(Self.tahoe.combinedName) -> the default wallpaper"))
	}

	@Test func defersWhileAVideoDownloads() async throws {
		let sandbox = try await Self.enabled(Self.tahoe.videos + [Self.gg.morning, Self.gg.day, Self.gg.evening])
		try sandbox.makeStateStale()
		try sandbox.markDownloading([Self.gg.night.assetID])
		#expect(try await sandbox.run("sync").lines.contains("sync: deferred") && sandbox.rawActions.isEmpty)
		try sandbox.markDownloading([Self.gg.night.assetID], age: 7 * 60)
		let stale = try await sandbox.run("sync")
		#expect(!stale.lines.contains("sync: deferred") && sandbox.actions == ["restart"])
		sandbox.clearDownloads()
		sandbox.place([Self.gg.night])
		let done = try await sandbox.run("sync")
		#expect(done.lines.contains("sync: updated") && sandbox.combinedSetIDs == Self.bothSets && sandbox.actions == ["restart"])
	}

	@Test func picksAQueuedSetOnceItIsCombined() async throws {
		let sandbox = try await Self.enabled(Self.tahoe.videos + [Self.gg.morning, Self.gg.day, Self.gg.evening])
		#expect(try await sandbox.run("select", Self.gg.night.assetID).status == 1 && sandbox.rawActions.isEmpty)
		let index = sandbox.digest(sandbox.paths.indexFile)
		#expect(try await sandbox.run("sync", Self.gg.subcategoryID).lines.contains("sync: unchanged"))
		#expect(sandbox.rawActions.isEmpty && sandbox.digest(sandbox.paths.indexFile) == index)
		try sandbox.makeStateStale()
		try sandbox.markDownloading([Self.gg.night.assetID])
		#expect(try await sandbox.run("sync", Self.gg.subcategoryID).lines.contains("sync: deferred") && sandbox.rawActions.isEmpty)
		sandbox.clearDownloads()
		sandbox.place([Self.gg.night])
		#expect(try await sandbox.run("sync", Self.gg.subcategoryID).lines.contains("sync: updated"))
		#expect(sandbox.combinedSetIDs == Self.bothSets && sandbox.actions == ["replace", "restart"])
		#expect(try sandbox.desktops == .init(IndexFixture.desktopCount, [Self.gg.subcategoryID]))
		#expect(try await sandbox.run("sync", "00000000-0000-0000-0000-000000000000").status == 2 && sandbox.rawActions.isEmpty)
	}

	@Test func switchesOffWhenACombinedSetsLayoutChanges() async throws {
		let sandbox = try await Self.enabled(Self.allVideos)
		try await sandbox.run("select", Self.tahoe.subcategoryID)
		let reordered = try sandbox.write(CatalogFixture().reorderedAssets(.tahoe), named: "reordered")
		let result = try await sandbox.run(["sync"], environment: ["NATIVE_AERIALS_MANIFEST": reordered.path])
		#expect(result.status == 0 && result.lines.contains("sync: turned-off") && result.error.contains("unexpected aerial catalog"))
		#expect(sandbox.actions == Sandbox.turnOffActions)
		#expect(!sandbox.hasOverride && sandbox.preferences[Sandbox.forceLocalKey] == nil)
		#expect(!sandbox.exists(sandbox.paths.customDirectory) && !sandbox.exists(sandbox.agentFile) && !sandbox.exists(sandbox.paths.supportDirectory))
		#expect(try sandbox.desktops == .init(IndexFixture.desktopCount, [Self.tahoe.day.assetID]))
		let again = try await sandbox.run("sync")
		#expect(again.lines.contains("sync: not-on") && sandbox.rawActions.isEmpty)
	}

	@Test func keepsEverythingWhileNoCatalogCanBeRead() async throws {
		let sandbox = try await Self.enabled(Self.allVideos)
		let catalog = sandbox.digest(sandbox.paths.catalogFile)
		let invalid = try sandbox.write(CatalogFixture.invalidJSON, named: "invalid")
		let result = try await sandbox.run(["sync"], environment: ["NATIVE_AERIALS_MANIFEST": invalid.path, "NATIVE_AERIALS_BUNDLED": invalid.path])
		#expect(result.status == 1 && result.error.contains("could not read"))
		#expect(sandbox.rawActions.isEmpty && sandbox.digest(sandbox.paths.catalogFile) == catalog)
		#expect(sandbox.preferences[Sandbox.forceLocalKey] as? Bool == true && sandbox.exists(sandbox.agentFile))
	}

	@Test func waitsForAMissingManifest() async throws {
		let sandbox = try await Self.enabled(Self.allVideos)
		let catalog = sandbox.digest(sandbox.paths.catalogFile)
		let missing = sandbox.directory.appending(path: "catalogs/missing.json")
		let invalid = try sandbox.write(CatalogFixture.invalidJSON, named: "invalid")
		for manifest in [missing, invalid] {
			let result = try await sandbox.run(["sync"], environment: ["NATIVE_AERIALS_MANIFEST": manifest.path])
			#expect(result.status == 0 && result.lines.contains("sync: deferred"), "\(manifest.lastPathComponent)")
			#expect(sandbox.rawActions.isEmpty && sandbox.digest(sandbox.paths.catalogFile) == catalog)
			#expect(sandbox.state?.source == sandbox.manifest.path)
		}
		#expect(try await sandbox.run("sync").lines.contains("sync: unchanged") && sandbox.rawActions.isEmpty)
	}
}
