import Foundation

nonisolated extension WallpaperSnapshot {
	var reportLines: [String] {
		var lines = [
			"on: \(isOn ? 1 : 0)",
			"needs-repair: \(needsRepair ? 1 : 0)",
			"availability: \(Self.describe(availability))",
			"selection: \(desktopChoice.map(Self.describe) ?? "none") \(selectedAssetID ?? "-")",
			"helper: \(agent.rawValue)",
		]
		for set in sets {
			lines.append("set \(set.subcategoryID) \(set.name.replacing(" ", with: "-")) merged=\(set.isMerged ? 1 : 0) apple=\(set.isMergedByApple ? 1 : 0) selected=\(set.isSelected ? 1 : 0) readiness=\(Self.describe(set.readiness)) thumbnail=\(set.thumbnail?.path ?? "none")")
			for variant in set.variants {
				lines.append("  variant \(variant.assetID) \(variant.caption) \(variant.download.rawValue) selected=\(variant.isSelected ? 1 : 0) thumbnail=\(variant.thumbnail?.path ?? "none")")
			}
		}
		return lines
	}

	private static func describe(_ availability: Availability) -> String {
		switch availability {
		case .available: "available"
		case .unsupported(let reason): "unsupported: \(reason)"
		case .appleDoesThis: "apple-does-this"
		case .blocked(let reason): "blocked: \(reason)"
		}
	}

	private static func describe(_ choice: AerialChoice) -> String {
		switch choice {
		case .video: "video"
		case .automatic: "automatic"
		}
	}

	private static func describe(_ readiness: SetReadiness) -> String {
		switch readiness {
		case .ready: "ready"
		case .missingVideos(let ids): "missing:\(ids.joined(separator: ","))"
		case .appleProvides: "apple"
		case .unexpectedLayout: "unexpected-layout"
		case .notInCatalog: "not-in-catalog"
		}
	}
}
