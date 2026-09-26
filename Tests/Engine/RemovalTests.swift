import Foundation
import Testing

nonisolated struct RemovalTests {
	static let gg = AerialSet.goldenGate
	static let tahoe = AerialSet.tahoe
	static let allVideos = AerialSet.all.flatMap(\.videos)

	static func refuses(_ body: () throws -> Void) -> Bool {
		do {
			try body()
			return false
		} catch {
			return true
		}
	}

	@Test func removesOnlyUnusedDownloads() throws {
		let sandbox = try Sandbox(videos: Self.allVideos)
		let remover = try sandbox.installer()
		let indexDigest = sandbox.digest(sandbox.paths.indexFile)
		#expect(try remover.removeDownload(of: .video(Self.tahoe.morning.assetID)) == [Self.tahoe.morning.assetID])
		#expect(!sandbox.exists(Self.tahoe.morning))
		#expect(sandbox.rawActions == ["remove-download \(sandbox.file(Self.tahoe.morning).path)"])
		#expect(Self.refuses { try remover.removeDownload(of: .video(Self.tahoe.day.assetID)) } && sandbox.exists(Self.tahoe.day))
		#expect(Self.refuses { try remover.removeDownload(of: .video(Self.gg.morning.assetID)) } && sandbox.exists(Self.gg.morning))
		#expect(Self.refuses { try remover.removeDownload(of: .video(Self.gg.night.assetID), keeping: [Self.gg.night.assetID]) } && sandbox.exists(Self.gg.night))
		#expect(Self.refuses { try remover.removeDownload(of: .automatic(Self.tahoe.subcategoryID)) } && sandbox.exists(Self.tahoe.night))
		#expect(Self.refuses { try remover.removeDownload(of: .video(Self.tahoe.morning.assetID)) })

		let link = sandbox.file(Self.tahoe.night)
		let target = sandbox.outside.appending(path: "target.mov")
		try Data("target".utf8).write(to: target)
		try FileManager.default.removeItem(at: link)
		try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
		#expect(Self.refuses { try remover.removeDownload(of: .video(Self.tahoe.night.assetID)) })
		#expect(sandbox.exists(target) && (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil)

		#expect(Set(try remover.removeDownload(of: .automatic(Self.gg.subcategoryID))) == Set([Self.gg.day, Self.gg.evening, Self.gg.night].map(\.assetID)))
		#expect(sandbox.exists(Self.gg.morning) && ![Self.gg.day, Self.gg.evening, Self.gg.night].contains(where: sandbox.exists))
		#expect(sandbox.digest(sandbox.paths.indexFile) == indexDigest)
		#expect(!sandbox.rawActions.contains { $0.contains("killall") })
	}

	@Test func keepsVideosOtherLiveOrRecentSpacesUse() throws {
		let sandbox = try Sandbox(videos: Self.allVideos)
		let evening = Self.tahoe.evening
		let usedAMinuteAgo = IndexFixture.standardSpaces.map { space in
			IndexFixture.Space(id: space.id, assetID: space.assetID, lastUse: space.id == IndexFixture.otherSpace ? .now.addingTimeInterval(-60) : space.lastUse)
		}
		let kept: [(spaces: String, index: [String: Any])] = [
			("\(IndexFixture.liveSpace),\(IndexFixture.otherSpace)", IndexFixture.standard()),
			("", IndexFixture.standard()),
			(IndexFixture.liveSpace, IndexFixture.standard(spaces: usedAMinuteAgo)),
			(IndexFixture.liveSpace, IndexFixture.renamingSpace(IndexFixture.standard(), IndexFixture.otherSpace, to: "")),
		]
		for (spaces, index) in kept {
			try sandbox.writeIndex(index)
			let remover = try sandbox.installer(["NATIVE_AERIALS_SPACES": spaces])
			#expect(Self.refuses { try remover.removeDownload(of: .video(evening.assetID)) } && sandbox.exists(evening), "spaces: \(spaces)")
		}
		try sandbox.writeIndex(IndexFixture.standard())
		#expect(try sandbox.installer().removeDownload(of: .video(evening.assetID)) == [evening.assetID])
		#expect(!sandbox.exists(evening))
	}

	@Test func keepsEveryVideoOfASavedCombinedItem() throws {
		let sandbox = try Sandbox(index: IndexFixture.everywhere(Self.tahoe.subcategoryID), videos: Self.allVideos)
		#expect(Self.refuses { try sandbox.installer().removeDownload(of: .video(Self.tahoe.morning.assetID)) } && sandbox.exists(Self.tahoe.morning))
	}

	@Test func keepsDownloadsWhileAnAerialShuffleIsSaved() throws {
		let sandbox = try Sandbox(videos: Self.allVideos)
		let remover = try sandbox.installer()
		#expect(remover.sourceCatalog()?.categoryIDs == CatalogFixture().catalog.categoryIDs)
		let shuffles = [
			WallpaperIndexTests.shuffled(assetID: "shuffle-all-aerials"),
			WallpaperIndexTests.shuffled(assetID: CatalogFixture.landscapeCategoryID),
			WallpaperIndexTests.shuffled(assetID: Self.gg.day.assetID, shuffle: ["frequency": "continuously"]),
		]
		for shuffle in shuffles {
			try sandbox.writeIndex(shuffle.root)
			var summary = ""
			do {
				_ = try remover.removeDownload(of: .video(Self.tahoe.morning.assetID))
			} catch {
				summary = InstallerError(describing: error).summary
			}
			#expect(summary.contains("shuffle") && sandbox.exists(Self.tahoe.morning), "\(summary)")
		}
	}

	@Test func dryRunNeverDeletesOutsideItsFolder() throws {
		let sandbox = try Sandbox()
		let outside = sandbox.outside.appending(path: "videos", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
		for video in Self.allVideos {
			try Data("x".utf8).write(to: outside.appending(path: "\(video.assetID).mov"))
		}
		let remover = try sandbox.installer(["NATIVE_AERIALS_VIDEOS": outside.path])
		let file = outside.appending(path: "\(Self.gg.day.assetID).mov")
		#expect(try remover.removeDownload(of: .video(Self.gg.day.assetID)) == [Self.gg.day.assetID])
		#expect(sandbox.exists(file))
		#expect(sandbox.rawActions == ["remove-download \(file.path)"])
	}

	@Test func revivesAutomaticOnlyForTheSameSet() throws {
		let sandbox = try Sandbox(index: IndexFixture.repainting(IndexFixture.standard(), where: { $0.first == "SystemDefault" }, with: IndexFixture.choice("OTHER-AERIAL")), videos: Self.allVideos)
		let slot = ["SystemDefault", "Linked", "Content", "Choices", "0"]
		let store = try sandbox.installer().store
		#expect(try store.stage(restoring: [], reviving: [ChoiceSlot(path: slot, automatic: Self.gg.subcategoryID, video: "ANOTHER-AERIAL")]) == nil)
		#expect(try store.stage(restoring: [], reviving: [ChoiceSlot(path: slot, automatic: Self.gg.subcategoryID, video: "OTHER-AERIAL")])?.revived.count == 1)
	}
}
