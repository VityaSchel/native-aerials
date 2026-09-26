import Foundation
import Testing

nonisolated struct PanelStateTests {
	static let gg = AerialSet.goldenGate
	static let tahoe = AerialSet.tahoe

	static func offered(_ state: PanelState) -> Set<String> {
		Set(state.rows.flatMap(\.tiles).filter(\.canRemove).map(\.id))
	}

	@Test func offersOnlyUnusedDownloadsForRemoval() throws {
		let sandbox = try Sandbox(videos: AerialSet.all.flatMap(\.videos))
		var state = PanelState()
		state.snapshot = try sandbox.snapshot()
		state.snapshot?.savedAssetIDs = []
		state.snapshot?.selectedAssetID = nil
		state.snapshot?.shufflesAerials = false
		state.isReady = true
		let shown = Set(AerialSet.all.flatMap(\.assetIDs))
		#expect(Self.offered(state) == shown.subtracting([AerialSet.systemDefaultAssetID]))
		state.liveSelection = AerialSelection(ids: [Self.tahoe.subcategoryID, Self.gg.night.assetID])
		#expect(Self.offered(state) == shown.subtracting([AerialSet.systemDefaultAssetID, Self.gg.night.assetID] + Self.tahoe.assetIDs))
		state.liveSelection = AerialSelection(includesCategories: true)
		#expect(Self.offered(state).isEmpty && !state.rows.contains(where: \.canRemove))
		state.liveSelection = AerialSelection()
		state.snapshot?.shufflesAerials = true
		#expect(Self.offered(state).isEmpty && !state.rows.contains(where: \.canRemove) && state.protectedAssetIDs == AerialSet.allIDs)
	}

	@Test func withholdsTheRemoveOfferForVideosOtherSpacesUse() throws {
		let sandbox = try Sandbox(videos: AerialSet.all.flatMap(\.videos))
		for (spaces, offered) in [(IndexFixture.liveSpace, true), ("\(IndexFixture.liveSpace),\(IndexFixture.otherSpace)", false), ("", false)] {
			var state = PanelState()
			state.snapshot = try sandbox.snapshot(["NATIVE_AERIALS_SPACES": spaces])
			state.isReady = true
			#expect(Self.offered(state).contains(Self.tahoe.evening.assetID) == offered, "spaces: \(spaces)")
		}
	}

	@Test func warnsAfterAnUnexpectedCatalogSwitchesOff() throws {
		let sandbox = try Sandbox(videos: AerialSet.all.flatMap(\.videos))
		_ = try sandbox.engine().turnOn()
		let reordered = ["NATIVE_AERIALS_MANIFEST": try sandbox.write(CatalogFixture().reorderedAssets(.tahoe), named: "reordered").path]
		let report = try sandbox.engine(reordered).sync()
		var window = PanelState()
		window.message = PanelState.message(after: report)
		window.snapshot = report.snapshot
		#expect(report.snapshot?.isOn == false)
		#expect(window.footnote == Footnote(text: InstallerError.unexpectedCatalogSummary, tone: .warning))
		var relaunched = PanelState()
		relaunched.snapshot = try sandbox.engine(reordered).snapshot()
		#expect(relaunched.footnote == Footnote(text: InstallerError.unexpectedCatalogSummary, tone: .warning))
	}

	@Test func asksToMoveToApplicationsBeforeTurningOn() throws {
		let sandbox = try Sandbox(videos: AerialSet.all.flatMap(\.videos))
		let elsewhere = ["NATIVE_AERIALS_APPLICATIONS": sandbox.apps.path]
		var state = PanelState()
		state.snapshot = try sandbox.snapshot(elsewhere)
		#expect(state.snapshot?.isOn == false && state.footnote == Footnote(text: Installer.moveNotice, tone: .warning))
		let engine = try sandbox.engine(elsewhere)
		let error = #expect(throws: InstallerError.self) { try engine.turnOn() }
		#expect(error?.summary == Installer.moveNotice && sandbox.rawActions.isEmpty)
	}

	@Test func hintsTheFirstMissingVideoOfTheSetClosestToComplete() throws {
		let cases: [([AerialVideo], AerialVideo)] = [
			([], Self.gg.morning),
			([Self.tahoe.day, Self.gg.morning, Self.gg.day, Self.gg.night], Self.gg.evening),
			([Self.tahoe.morning, Self.tahoe.night, Self.gg.morning], Self.tahoe.day),
			([Self.tahoe.morning, Self.gg.day], Self.gg.morning),
			(Array(Self.tahoe.videos.dropLast() + Self.gg.videos.dropLast()), Self.gg.night),
		]
		for (videos, hinted) in cases {
			let sandbox = try Sandbox(videos: videos)
			var state = PanelState()
			state.snapshot = try sandbox.snapshot()
			let error = #expect(throws: InstallerError.self) { try sandbox.engine().turnOn() }
			#expect(state.firstMissingTile(closestToComplete: error?.missingAssetIDs ?? [])?.id == hinted.assetID, "\(videos.map(\.name))")
		}
	}

	@Test func listsOnlySetsInTheCatalog() throws {
		let sandbox = try Sandbox(catalog: CatalogFixture().without(.goldenGate), videos: AerialSet.all.flatMap(\.videos))
		var state = PanelState()
		state.snapshot = try sandbox.snapshot()
		state.isReady = true
		#expect(state.rows.map(\.id) == [Self.tahoe.subcategoryID])
		#expect(state.rows.first?.tiles.count == 4)
		#expect(state.snapshot?.availability == .available)
		#expect(state.footnote == Footnote(text: "Dry run: changes go to \(sandbox.directory.path)."))
	}
}
