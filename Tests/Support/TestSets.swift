import Foundation

nonisolated extension AerialSet {
	static let goldenGate = all.first { $0.slug == "golden-gate" }!
	static let tahoe = all.first { $0.slug == "tahoe" }!

	var morning: AerialVideo { video(.morning) }
	var day: AerialVideo { video(.day) }
	var evening: AerialVideo { video(.evening) }
	var night: AerialVideo { video(.night) }
}

nonisolated extension DownloadEvent {
	static func update(assetID: String, _ update: DownloadUpdate) -> DownloadEvent {
		.update(configuration: ChoiceCode.of(assetID), update)
	}
}
