import Foundation
import Testing

nonisolated struct SelectTests {
	static let gg = AerialSet.goldenGate
	static let tahoe = AerialSet.tahoe
	static let allVideos = AerialSet.all.flatMap(\.videos)

	@Test func paintsEveryDesktop() async throws {
		let sandbox = try Sandbox(videos: Self.allVideos)
		let skeleton = IndexFixture.skeleton(of: try sandbox.indexRoot)
		#expect(try await sandbox.run("select", Self.tahoe.day.assetID).lines.contains("select: changed"))
		#expect(try sandbox.desktops == .init(IndexFixture.desktopCount, [Self.tahoe.day.assetID]))
		#expect(try await sandbox.run("select", Self.tahoe.day.assetID).lines.contains("select: unchanged") && sandbox.rawActions.isEmpty)
		try await sandbox.run("select", Self.tahoe.night.assetID)
		#expect(try sandbox.desktops == .init(IndexFixture.desktopCount, [Self.tahoe.night.assetID]))
		#expect(sandbox.actions == ["replace", "restart"])
		let data = try Data(contentsOf: sandbox.paths.indexFile)
		#expect(data.starts(with: Data("bplist".utf8)))
		let root = try WallpaperIndex(data: data).root
		#expect(IndexFixture.skeleton(of: root) == skeleton)
		#expect(IndexFixture.desktopParts(of: root).allSatisfy { ($0.part["Content"] as? [String: Any])?["Shuffle"] as? String == WallpaperIndex.nullValue })
		let choice = try #require((((root["SystemDefault"] as? [String: Any])?["Linked"] as? [String: Any])?["Content"] as? [String: Any])?["Choices"] as? [[String: Any]]).first
		let configuration = try #require(choice?["Configuration"] as? Data)
		#expect(choice?["Provider"] as? String == WallpaperIndex.aerialsProvider && (choice?["Files"] as? [Any])?.isEmpty == true)
		#expect(configuration.starts(with: Data("bplist".utf8)))
		#expect(try PropertyListSerialization.propertyList(from: configuration, format: nil) as? [String: String] == ["assetID": Self.tahoe.night.assetID])
		#expect(sandbox.contents(of: sandbox.paths.indexFile.deletingLastPathComponent()) == ["Index.plist"])
	}

	@Test func keepsIdleParts() async throws {
		let sandbox = try Sandbox(index: IndexFixture.standard(layout: .idle), videos: Self.allVideos)
		let skeleton = IndexFixture.skeleton(of: try sandbox.indexRoot)
		#expect(try await sandbox.run("select", Self.tahoe.night.assetID).status == 0)
		#expect(IndexFixture.skeleton(of: try sandbox.indexRoot) == skeleton)
		#expect(try sandbox.desktops == .init(IndexFixture.desktopCount, [Self.tahoe.night.assetID]))
	}

	@Test func replacesTheDefaultProvider() async throws {
		let sandbox = try Sandbox(index: IndexFixture.everywhere(nil), videos: Self.allVideos)
		#expect(try await sandbox.run("select", Self.gg.day.assetID).status == 0)
		#expect(try sandbox.desktops == .init(IndexFixture.desktopCount, [Self.gg.day.assetID]))
	}

	@Test func refusesAutomaticWhileOff() async throws {
		let sandbox = try Sandbox(videos: Self.allVideos)
		let index = sandbox.digest(sandbox.paths.indexFile)
		let result = try await sandbox.run("select", Self.tahoe.subcategoryID)
		#expect(result.status == 1 && result.error.contains("is not combined right now"))
		#expect(sandbox.rawActions.isEmpty && sandbox.digest(sandbox.paths.indexFile) == index)
	}

	@Test func picksAutomaticWithoutTheVariantOption() async throws {
		let sandbox = try Sandbox(index: IndexFixture.standard(variantOption: true), videos: Self.allVideos)
		try await sandbox.run("enable")
		#expect(IndexFixture.variantCount(of: try sandbox.indexRoot) == IndexFixture.desktopCount)
		try await sandbox.run("select", Self.tahoe.subcategoryID)
		#expect(try sandbox.desktops == .init(IndexFixture.desktopCount, [Self.tahoe.subcategoryID]))
		#expect(IndexFixture.variantCount(of: try sandbox.indexRoot) == 0)
		let snapshot = try sandbox.snapshot()
		let set = snapshot.sets.first { $0.subcategoryID == Self.tahoe.subcategoryID }
		#expect(snapshot.desktopChoice == .automatic(Self.tahoe.subcategoryID))
		#expect(set?.isMerged == true && set?.isMergedByApple == false && set?.isSelected == true)
	}

	@Test func refusesAMissingVideo() async throws {
		let sandbox = try Sandbox(videos: Self.tahoe.videos + [Self.gg.day])
		let index = sandbox.digest(sandbox.paths.indexFile)
		for _ in 0..<2 {
			let result = try await sandbox.run("select", Self.gg.night.assetID)
			#expect(result.status == 1 && result.error.contains("only downloads an aerial that is picked in System Settings > Wallpaper"))
			#expect(sandbox.rawActions.isEmpty && sandbox.digest(sandbox.paths.indexFile) == index)
		}
		let variants = Dictionary(uniqueKeysWithValues: try sandbox.snapshot().sets.flatMap(\.variants).map { ($0.assetID, $0) })
		#expect(variants[Self.gg.night.assetID]?.download == .missing && variants[Self.gg.night.assetID]?.isSelected == false)
		#expect(variants[Self.gg.morning.assetID]?.download == .missing && variants[Self.gg.morning.assetID]?.isSelected == false)
		sandbox.place([Self.gg.night])
		#expect(try await sandbox.run("select", Self.gg.night.assetID).status == 0)
		sandbox.remove([Self.gg.night])
		let snapshot = try sandbox.snapshot()
		let night = snapshot.sets.flatMap(\.variants).first { $0.assetID == Self.gg.night.assetID }
		#expect(night?.download == .missing && night?.isSelected == false && snapshot.selectedAssetID == nil)
	}

	@Test func refusesAnUnknownIndexLayout() async throws {
		var root = IndexFixture.standard()
		root["FutureKey"] = ["x": 1]
		let sandbox = try Sandbox(index: root, videos: Self.allVideos)
		let index = sandbox.digest(sandbox.paths.indexFile)
		let result = try await sandbox.run("select", Self.tahoe.day.assetID)
		#expect(result.status == 1 && result.error.contains("layout this version doesn't know"))
		#expect(sandbox.rawActions.isEmpty && sandbox.digest(sandbox.paths.indexFile) == index)
		#expect(try await sandbox.run("select", "00000000-0000-0000-0000-000000000000").status == 2)
	}
}
