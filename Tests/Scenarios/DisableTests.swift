import Foundation
import Testing

nonisolated struct DisableTests {
	static let gg = AerialSet.goldenGate
	static let tahoe = AerialSet.tahoe
	static let allVideos = AerialSet.all.flatMap(\.videos)
	static let foreignCatalog = "/nonexistent/other-tool/entries.json"

	@Test func doesNothingWhenNotInstalled() async throws {
		let sandbox = try Sandbox(videos: Self.allVideos)
		let result = try await sandbox.run("disable")
		#expect(result.status == 0 && sandbox.rawActions.isEmpty)
		#expect(result.lines.contains("Native Aerials is not installed; nothing to do"))
	}

	@Test func leavesAnotherToolsOverrideAlone() async throws {
		let sandbox = try Sandbox(index: IndexFixture.combined, videos: Self.allVideos)
		try sandbox.setPreference(Sandbox.overrideKey, Self.foreignCatalog)
		try sandbox.setPreference(Sandbox.forceLocalKey, true)
		let preferences = sandbox.digest(sandbox.paths.preferencesFile)
		let index = sandbox.digest(sandbox.paths.indexFile)
		let enable = try await sandbox.run("enable")
		#expect(enable.status == 1 && enable.error.contains("already points at \(Self.foreignCatalog)"))
		#expect(sandbox.installedCatalog == nil && sandbox.rawActions.isEmpty && sandbox.digest(sandbox.paths.preferencesFile) == preferences)
		let disable = try await sandbox.run("disable")
		#expect(disable.status == 0 && disable.error.contains("which Native Aerials did not write"))
		#expect(sandbox.rawActions.isEmpty && sandbox.digest(sandbox.paths.preferencesFile) == preferences && sandbox.digest(sandbox.paths.indexFile) == index)
	}

	@Test func keepsChoicesOfSetsAppleCombines() async throws {
		let sandbox = try Sandbox(index: IndexFixture.combined, catalog: CatalogFixture().combiningWithoutSolar([.tahoe]), videos: Self.allVideos)
		#expect(try await sandbox.run("enable").status == 0)
		#expect(try await sandbox.run("disable").status == 0)
		let saved = try sandbox.savedChoiceIDs
		#expect(saved.contains(Self.tahoe.subcategoryID) && !saved.contains(Self.gg.subcategoryID) && saved.contains(Self.gg.day.assetID))
		#expect(!sandbox.exists(sandbox.paths.customDirectory) && !sandbox.hasOverride)
	}
}
