import Foundation
import Testing

struct LaunchStateTests {
	static let gg = AerialSet.goldenGate
	static let tahoe = AerialSet.tahoe

	static func resting(_ rows: [SetRow]) -> [SetRow] {
		rows.map { row in
			var row = row
			row.animatesMerge = false
			return row
		}
	}

	@Test func animatesOnlyTheSwitch() async throws {
		let sandbox = try Sandbox(videos: AerialSet.all.flatMap(\.videos))
		let engine = try sandbox.engine()
		_ = try engine.turnOn()
		_ = try engine.select(.automatic(Self.gg.subcategoryID))
		#expect(engine.snapshot().selectedAssetID == Self.gg.subcategoryID)
		let window = WindowHarness(sandbox)
		try await window.start()
		defer { window.stop() }
		let model = window.model
		let launched = window.state.rows
		#expect(launched.allSatisfy(\.isMerged) && launched.first?.isSelected == true)
		#expect(launched.allSatisfy { !$0.animatesMerge })

		model.setEnabled(false)
		#expect(window.state.rows.allSatisfy { $0.animatesMerge })
		#expect(await window.settled { window.state.snapshot?.isOn == false })
		model.setEnabled(true)
		#expect(window.state.rows.allSatisfy { $0.animatesMerge })
		#expect(await window.settled { window.state.switchIntent == nil && window.state.rows.allSatisfy(\.isMerged) })
		#expect(Self.resting(window.state.rows) == Self.resting(launched))

		model.removeDownload(.video(Self.tahoe.night.assetID))
		#expect(await window.settled { window.row(Self.tahoe)?.isMerged == false })
		#expect(window.state.rows.allSatisfy { !$0.animatesMerge })
		sandbox.place([Self.tahoe.night])
		#expect(await window.settled { window.row(Self.tahoe)?.isMerged == true })
		#expect(window.state.rows.allSatisfy { !$0.animatesMerge })
	}
}
