import Foundation
import Testing

nonisolated struct DownloadGuardTests {
	static let gg = AerialSet.goldenGate
	static let tahoe = AerialSet.tahoe
	static let allVideos = AerialSet.all.flatMap(\.videos)

	@Test func refusesWhileAVideoDownloads() async throws {
		let sandbox = try Sandbox(videos: Self.allVideos)
		let index = sandbox.digest(sandbox.paths.indexFile)
		try sandbox.markDownloading([Self.tahoe.day.assetID])
		let enable = try await sandbox.run("enable")
		#expect(enable.status == 1 && enable.error.contains("\(Self.tahoe.day.name) is downloading"))
		#expect(sandbox.rawActions.isEmpty && sandbox.installedCatalog == nil)
		let select = try await sandbox.run("select", Self.gg.day.assetID)
		#expect(select.status == 1 && select.error.contains("\(Self.tahoe.day.name) is downloading"))
		#expect(sandbox.rawActions.isEmpty && sandbox.digest(sandbox.paths.indexFile) == index)
		try sandbox.markDownloading(["ABCDEF12"])
		let other = try await sandbox.run("select", Self.gg.day.assetID)
		#expect(other.status == 1 && other.error.contains("a wallpaper is downloading") && sandbox.rawActions.isEmpty)
		sandbox.clearDownloads()
		#expect(try await sandbox.run("enable").status == 0 && sandbox.combinedSetIDs == Set(AerialSet.all.map(\.subcategoryID)))
		let catalog = sandbox.digest(sandbox.paths.catalogFile)
		try sandbox.markDownloading([Self.tahoe.day.assetID])
		#expect(try await sandbox.run("disable").status == 1)
		#expect(sandbox.rawActions.isEmpty && sandbox.digest(sandbox.paths.catalogFile) == catalog && sandbox.preferences[Sandbox.forceLocalKey] != nil)
		sandbox.clearDownloads()
		#expect(try await sandbox.run("disable").status == 0 && sandbox.installedCatalog == nil)
	}
}
