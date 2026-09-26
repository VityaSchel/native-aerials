import Foundation
import Testing

nonisolated struct WallpaperIndexTests {
	static let gg = AerialSet.goldenGate
	static let tahoe = AerialSet.tahoe
	static let live: Set<String> = [IndexFixture.liveSpace]
	static let later = IndexFixture.lastUse.addingTimeInterval(86400)

	@Test func paintsEveryDesktopOnce() throws {
		var index = WallpaperIndex(root: IndexFixture.standard())
		let night = AerialChoice.video(Self.tahoe.night.assetID)
		#expect(index.paint(night, at: .now) == IndexFixture.desktopCount)
		#expect(index.paint(night, at: .now) == 0)
		#expect(index.currentDesktopAssetID == Self.tahoe.night.assetID)
		#expect(index.showsEverywhere(night))
		#expect(index.root["AllSpacesAndDisplays"] as? String == WallpaperIndex.nullValue)
		#expect(index.hasExpectedLayout)
		index.root["Unknown"] = 1
		#expect(!index.hasExpectedLayout)
	}

	static func shuffled(assetID: String?, shuffle: Any? = nil) -> WallpaperIndex {
		let root = WallpaperIndex.mapDictionaries(in: IndexFixture.standard()) { node, _ in
			var node = node
			if node["Provider"] as? String == WallpaperIndex.aerialsProvider {
				node["Configuration"] = IndexFixture.plist(assetID.map { ["assetID": $0] } ?? ["kind": "shuffle"])
			}
			if let shuffle, node["Choices"] != nil {
				node["Shuffle"] = shuffle
			}
			return node
		}
		return WallpaperIndex(root: root as? [String: Any] ?? [:])
	}

	@Test func recognizesAerialShuffles() {
		let category = CatalogFixture.landscapeCategoryID
		let single = WallpaperIndex(root: IndexFixture.standard())
		#expect(!single.shufflesAerials(categoryIDs: [category]) && !single.choiceAssetIDs.isEmpty)
		#expect(Self.shuffled(assetID: "shuffle-all-aerials").shufflesAerials())
		#expect(Self.shuffled(assetID: "SHUFFLE_CATEGORY_PREFIX_\(category)").shufflesAerials())
		#expect(Self.shuffled(assetID: nil).shufflesAerials())
		#expect(Self.shuffled(assetID: category).shufflesAerials(categoryIDs: [category]))
		#expect(!Self.shuffled(assetID: category).shufflesAerials())
		#expect(Self.shuffled(assetID: Self.gg.day.assetID, shuffle: ["frequency": "continuously"]).shufflesAerials())
		#expect(!Self.shuffled(assetID: Self.gg.day.assetID, shuffle: WallpaperIndex.nullValue).shufflesAerials())
	}

	static var otherSpaceUsedLater: WallpaperIndex {
		let root = IndexFixture.standard()
		let edited = IndexFixture.desktopParts(of: root).filter { $0.path.starts(with: ["Spaces", IndexFixture.otherSpace]) }.reduce(root) { root, part in
			IndexFixture.updating(root, at: part.path) { $0["LastUse"] = IndexFixture.lastUse.addingTimeInterval(3600) }
		}
		return WallpaperIndex(root: edited)
	}

	@Test func currentDesktopIgnoresDeletedAndFullScreenSpaces() {
		let usedLater = Self.otherSpaceUsedLater
		#expect(usedLater.currentDesktopAssetID == Self.tahoe.evening.assetID)
		#expect(usedLater.inUse(spaces: Self.live, includingRecent: false, now: Self.later).currentDesktopAssetID == Self.tahoe.day.assetID)
		let minuteLater = IndexFixture.lastUse.addingTimeInterval(3660)
		#expect(usedLater.inUse(spaces: Self.live, includingRecent: true, now: minuteLater).choiceAssetIDs.contains(Self.tahoe.evening.assetID))
		#expect(usedLater.inUse(spaces: Self.live, includingRecent: false, now: minuteLater).currentDesktopAssetID == Self.tahoe.day.assetID)
	}

	@Test func mostSpecificSlotWinsALastUseTie() {
		let root = IndexFixture.standard()
		let showing = { (root: [String: Any], prefix: [String], id: String) in
			IndexFixture.repainting(root, where: { $0.starts(with: prefix) }, with: IndexFixture.choice(id))
		}
		let tieDefault = showing(root, ["SystemDefault"], Self.gg.day.assetID)
		let tieDisplay = showing(tieDefault, ["Spaces", IndexFixture.liveSpace, "Displays"], Self.tahoe.night.assetID)
		#expect(WallpaperIndex(root: tieDefault).currentDesktopAssetID == Self.tahoe.day.assetID)
		#expect(WallpaperIndex(root: tieDisplay).currentDesktopAssetID == Self.tahoe.night.assetID)
	}

	@Test func savedChoicesInUse() {
		let index = WallpaperIndex(root: IndexFixture.standard())
		let evening = Self.tahoe.evening.assetID
		#expect(index.inUse(spaces: Self.live.union([IndexFixture.otherSpace]), includingRecent: true, now: Self.later).choiceAssetIDs.contains(evening))
		#expect(!index.inUse(spaces: Self.live, includingRecent: true, now: Self.later).choiceAssetIDs.contains(evening))
		#expect(index.inUse(spaces: nil, includingRecent: true, now: Self.later).choiceAssetIDs == index.choiceAssetIDs)
		let firstDesktop = WallpaperIndex(root: IndexFixture.renamingSpace(IndexFixture.standard(), IndexFixture.otherSpace, to: ""))
		#expect(firstDesktop.inUse(spaces: Self.live, includingRecent: true, now: Self.later).choiceAssetIDs.contains(evening))
		#expect(index.inUse(spaces: Self.live, includingRecent: true, now: IndexFixture.otherLastUse.addingTimeInterval(60)).choiceAssetIDs.contains(evening))
	}
}
