import Foundation
import Testing

nonisolated struct AerialSetTableTests {
	@Test func choiceCodesAreTheLogsConfigurationCodes() {
		let gg = AerialSet.goldenGate
		let tahoe = AerialSet.tahoe
		let expected = [
			tahoe.morning.assetID: "F920A3D7", tahoe.day.assetID: "54EB4A8C", tahoe.evening.assetID: "BF52B245", tahoe.night.assetID: "0203764D",
			gg.morning.assetID: "E08609E0", gg.day.assetID: "196CF637", gg.evening.assetID: "358EFEA9", gg.night.assetID: "F6B9C9F3",
			tahoe.subcategoryID: "11E9C37A", gg.subcategoryID: "D477A96C",
		]
		for (assetID, code) in expected {
			#expect(ChoiceCode.of(assetID) == code)
			#expect(ChoiceCode.known[code] == assetID)
		}
		#expect(ChoiceCode.known.count == AerialSet.all.count * 5)
		#expect(AerialSet.allIDs.allSatisfy { ChoiceCode.known[ChoiceCode.of($0)] == $0 })
	}

	@Test func tableIsConsistent() {
		let ids = AerialSet.all.map(\.subcategoryID) + AerialSet.all.flatMap(\.assetIDs)
		#expect(!AerialSet.all.isEmpty)
		for column in [ids, AerialSet.all.flatMap(\.shotIDs), AerialSet.all.map(\.slug), AerialSet.all.map(\.displayName)] {
			#expect(Set(column).count == column.count)
		}
		#expect(ids.allSatisfy { UUID(uuidString: $0)?.uuidString == $0 })
		#expect(AerialSet.all.allSatisfy { $0.videos.map(\.role) == SunRole.allCases })
		#expect(ChoiceCode.known.count == ids.count)
		#expect(AerialSet.set(containingAssetID: AerialSet.systemDefaultAssetID) != nil)
	}

	@Test func noSetLiteralsOutsideTable() throws {
		let sources = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "Native Aerials", directoryHint: .isDirectory)
		let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
		try #require(files.contains { $0.lastPathComponent == "AerialSets.swift" })
		let literals = AerialSet.all.flatMap { [$0.slug, $0.displayName, $0.subcategoryID] + $0.assetIDs + $0.shotIDs }
		for file in files where file.lastPathComponent != "AerialSets.swift" {
			let text = try String(contentsOf: file, encoding: .utf8)
			let found = literals.filter { text.range(of: $0) != nil }
			#expect(found.isEmpty, "\(file.lastPathComponent) names \(found); adding a set must only take a table edit")
		}
	}
}
