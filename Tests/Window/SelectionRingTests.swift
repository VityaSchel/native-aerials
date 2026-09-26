import Foundation
import Testing

struct SelectionRingTests {
	static let gg = AerialSet.goldenGate
	static let tahoe = AerialSet.tahoe

	@Test func ringFollowsTheSavedChoice() async throws {
		let sandbox = try Sandbox(videos: AerialSet.all.flatMap(\.videos))
		let window = WindowHarness(sandbox)
		try await window.start()
		defer { window.stop() }
		let model = window.model
		let otherSpace = ["Spaces", IndexFixture.otherSpace, "Default", "Linked", "Content", "Choices", "0"]
		let saved = { try WallpaperIndex(root: sandbox.indexRoot) }

		model.setEnabled(true)
		#expect(await window.settled { window.state.switchIsOn && window.row(Self.gg)?.isMerged == true && window.row(Self.tahoe)?.isMerged == true })
		model.chooseMerged(try #require(window.row(Self.gg)))
		#expect(await window.settled { window.row(Self.gg)?.isSelected == true })
		model.setEnabled(false)
		#expect(await window.settled { !window.state.switchIsOn && window.selected == Self.gg.day.assetID })
		model.setEnabled(true)
		#expect(await window.settled { window.state.switchIsOn && window.selected == Self.gg.subcategoryID && window.ringed == [Self.gg.displayName] })

		model.setEnabled(false)
		#expect(await window.settled { !window.state.switchIsOn })
		try sandbox.repaint(dead: false, with: IndexFixture.photo)
		#expect(await window.settled { window.selected == nil && window.ringed.isEmpty })
		model.setEnabled(true)
		#expect(await window.settled { window.state.switchIsOn && window.row(Self.gg)?.isMerged == true && window.selected == nil && window.ringed.isEmpty })
		#expect(try sandbox.liveDesktops == .init(IndexFixture.liveCount, [IndexFixture.none]))
		#expect(try saved().choiceAssetID(at: otherSpace) == Self.gg.day.assetID)

		model.chooseMerged(try #require(window.row(Self.gg)))
		#expect(await window.settled { window.row(Self.gg)?.isSelected == true })
		model.setEnabled(false)
		#expect(await window.settled { !window.state.switchIsOn && window.selected == Self.gg.day.assetID })
		try sandbox.repaint(dead: false, with: IndexFixture.choice(Self.tahoe.night.assetID))
		model.setEnabled(true)
		#expect(await window.settled {
			window.state.switchIsOn && window.row(Self.tahoe)?.isMerged == true && window.selected == Self.tahoe.night.assetID
				&& window.row(Self.gg)?.isSelected == false && window.row(Self.tahoe)?.isSelected == false
		})
		#expect(try sandbox.liveDesktops == .init(IndexFixture.liveCount, [Self.tahoe.night.assetID]))
		#expect(try saved().choiceAssetID(at: otherSpace) == Self.gg.day.assetID)

		try sandbox.repaint(dead: true, with: IndexFixture.choice(Self.gg.subcategoryID), lastUse: .now.addingTimeInterval(-30))
		#expect(await window.settled {
			window.state.snapshot?.savedAssetIDs.contains(Self.gg.subcategoryID) == true && window.selected == Self.tahoe.night.assetID && window.ringed.isEmpty
		})
	}
}
