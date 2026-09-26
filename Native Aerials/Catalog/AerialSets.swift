import Foundation

nonisolated struct SunPosition: Sendable {
	let altitude: Double
	let azimuth: Double
}

nonisolated enum SunRole: Int, CaseIterable, Sendable {
	case morning
	case day
	case evening
	case night

	static let replacementOrder: [SunRole] = [.day, .morning, .evening, .night]

	var position: SunPosition {
		switch self {
		case .morning: SunPosition(altitude: 10.593, azimuth: 90)
		case .day: SunPosition(altitude: 10.607, azimuth: 179.997)
		case .evening: SunPosition(altitude: SunRole.morning.position.altitude, azimuth: 180)
		case .night: SunPosition(altitude: -10.793, azimuth: 180)
		}
	}
}

nonisolated struct AerialVideo: Sendable {
	let role: SunRole
	let name: String
	let caption: String
	let assetID: String
	let shotID: String

	var position: SunPosition { role.position }
}

nonisolated struct AerialSet: Sendable, Hashable {
	struct Shot: Sendable {
		let caption: String
		let assetID: String
		let shotID: String

		init(_ caption: String, assetID: String, shotID: String) {
			self.caption = caption
			self.assetID = assetID
			self.shotID = shotID
		}
	}

	let slug: String
	let displayName: String
	let subcategoryID: String
	let videos: [AerialVideo]

	init(slug: String, displayName: String, subcategoryID: String, morning: Shot, day: Shot, evening: Shot, night: Shot) {
		self.slug = slug
		self.displayName = displayName
		self.subcategoryID = subcategoryID
		videos = zip(SunRole.allCases, [morning, day, evening, night]).map { role, shot in
			AerialVideo(role: role, name: "\(displayName) \(shot.caption)", caption: shot.caption, assetID: shot.assetID, shotID: shot.shotID)
		}
	}

	var replacementCandidates: [AerialVideo] { SunRole.replacementOrder.map(video) }
	var shotIDs: [String] { videos.map(\.shotID) }
	var assetIDs: [String] { videos.map(\.assetID) }
	var combinedName: String { "\(displayName) (combined, Automatic)" }

	func video(_ role: SunRole) -> AerialVideo {
		videos[role.rawValue]
	}

	func position(forShotID shotID: String) -> SunPosition? {
		videos.first { $0.shotID == shotID }?.position
	}

	static func == (lhs: AerialSet, rhs: AerialSet) -> Bool {
		lhs.subcategoryID == rhs.subcategoryID
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(subcategoryID)
	}

	static let all = [
		AerialSet(
			slug: "golden-gate",
			displayName: "Golden Gate",
			subcategoryID: "67512508-D33E-4CBC-8A9E-BE55CEE35C4C",
			morning: Shot("Sunset", assetID: "4207734D-74FE-4F92-B5E1-6EC8DEE24A15", shotID: "GG_A_SUNSET"),
			day: Shot("Day", assetID: "6511D2B5-E185-4886-9505-B4004E920D27", shotID: "GG_A_DAY"),
			evening: Shot("Evening", assetID: "3FD9FD5C-6DC5-4362-9932-4087C942F1C5", shotID: "GG_A_EVENING"),
			night: Shot("Night", assetID: "86E89C23-C39B-44C8-A985-E56EEA6456FE", shotID: "GG_A_NIGHT")
		),
		AerialSet(
			slug: "tahoe",
			displayName: "Tahoe",
			subcategoryID: "0DC99DD8-3386-4D1E-8878-C43E97EB710A",
			morning: Shot("Morning", assetID: "B2FC91ED-6891-4DEB-85A1-268B2B4160B6", shotID: "TA_L_001"),
			day: Shot("Day", assetID: "4C108785-A7BA-422E-9C79-B0129F1D5550", shotID: "TA_L_002"),
			evening: Shot("Evening", assetID: "52ACB9B8-75FC-4516-BC60-4550CFF3B661", shotID: "TA_D_001"),
			night: Shot("Night", assetID: "CF6347E2-4F81-4410-8892-4830991B6C5A", shotID: "TA_D_002")
		),
	]

	static let systemDefaultAssetID = "4207734D-74FE-4F92-B5E1-6EC8DEE24A15"
	static let allIDs = Set(all.flatMap(\.assetIDs) + all.map(\.subcategoryID))

	static func addingVideos(ofSetsIn ids: Set<String>) -> Set<String> {
		ids.union(all.filter { ids.contains($0.subcategoryID) }.flatMap(\.assetIDs))
	}

	static func set(forSubcategoryID id: String) -> AerialSet? {
		all.first { $0.subcategoryID == id }
	}

	static func set(containingAssetID id: String) -> AerialSet? {
		all.first { $0.assetIDs.contains(id) }
	}

	static func video(withAssetID id: String) -> AerialVideo? {
		all.lazy.flatMap(\.videos).first { $0.assetID == id }
	}

	static func displayName(forAssetID id: String) -> String {
		if let set = set(forSubcategoryID: id) {
			return set.combinedName
		}
		return video(withAssetID: id)?.name ?? id
	}
}

nonisolated enum AerialChoice: Hashable, Sendable, CustomStringConvertible {
	case video(String)
	case automatic(String)

	init?(identifier: String) {
		if AerialSet.set(forSubcategoryID: identifier) != nil {
			self = .automatic(identifier)
		} else if AerialSet.video(withAssetID: identifier) != nil {
			self = .video(identifier)
		} else {
			return nil
		}
	}

	var assetID: String {
		switch self {
		case .video(let id), .automatic(let id): id
		}
	}

	var set: AerialSet? {
		switch self {
		case .video(let id): AerialSet.set(containingAssetID: id)
		case .automatic(let id): AerialSet.set(forSubcategoryID: id)
		}
	}

	var description: String { AerialSet.displayName(forAssetID: assetID) }
}
