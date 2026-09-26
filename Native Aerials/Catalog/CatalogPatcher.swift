import Foundation

nonisolated struct PatchedCatalog {
	let catalog: AerialCatalog
	let data: Data
	let sets: [AerialSet]
	let changes: [String]
}

nonisolated enum CatalogPatcher {
	static func patch(_ source: AerialCatalog, sets: [AerialSet]) throws -> PatchedCatalog {
		let data = try JSONTree.serialize(patchedRoot(of: source.root, sets: sets))
		guard let reparsed = try? JSONTree.parse(data) as? [String: Any] else {
			throw InstallerError("built catalog is not valid JSON for macOS's parser", summary: InstallerError.unexpectedCatalogSummary)
		}
		let catalog = AerialCatalog(url: source.url, root: reparsed)
		let changes = CatalogDelta.lines(from: source.root, to: catalog.root)
		let unexpected = changes.filter { !CatalogDelta.isExpected($0, in: catalog, sets: sets) }
		guard unexpected.isEmpty else {
			throw InstallerError(
				(unexpected.map(\.description) + ["built catalog differs from Apple's outside the solar fields; refusing to install"])
					.joined(separator: "\n"),
				summary: InstallerError.unexpectedCatalogSummary
			)
		}
		return PatchedCatalog(catalog: catalog, data: data, sets: sets, changes: changes.map(\.description))
	}

	private static func patchedRoot(of root: [String: Any], sets: [AerialSet]) throws -> [String: Any] {
		var root = root
		let subcategoryIDs = Set(sets.map(\.subcategoryID))
		root["categories"] = (root["categories"] as? [Any] ?? []).map { patchedCategory($0, subcategoryIDs: subcategoryIDs) }
		root["assets"] = try (root["assets"] as? [Any] ?? []).map { try patchedAsset($0, sets: sets) }
		return root
	}

	private static func patchedCategory(_ element: Any, subcategoryIDs: Set<String>) -> Any {
		guard var category = element as? [String: Any], let list = category["subcategories"] as? [Any] else {
			return element
		}
		category["subcategories"] = list.map { element -> Any in
			guard var subcategory = element as? [String: Any],
				let id = subcategory["id"] as? String,
				subcategoryIDs.contains(id)
			else {
				return element
			}
			subcategory["combineVariants"] = true
			return subcategory
		}
		return category
	}

	private static func patchedAsset(_ element: Any, sets: [AerialSet]) throws -> Any {
		guard var asset = element as? [String: Any], let shotID = asset["shotID"] as? String else {
			return element
		}
		for set in sets {
			guard let position = set.position(forShotID: shotID), AerialCatalog.belongs(asset, to: set.subcategoryID) else {
				continue
			}
			var variant: [String: Any]
			switch asset["variant"] {
			case nil, is NSNull: variant = [:]
			case let existing as [String: Any]: variant = existing
			default: throw InstallerError("unexpected variant for \(shotID) in the aerial catalog", summary: InstallerError.unexpectedCatalogSummary)
			}
			variant["solar"] = ["altitude": position.altitude, "azimuth": position.azimuth]
			asset["variant"] = variant
		}
		return asset
	}
}
