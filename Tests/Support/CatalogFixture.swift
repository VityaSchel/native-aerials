import Foundation

nonisolated struct CatalogFixture {
	static let landscapeCategoryID = "C0000000-0000-4000-8000-000000000001"
	static let dynamicSubcategoryID = "D0000000-0000-4000-8000-000000000001"
	static let fillerSubcategoryID = "F0000000-0000-4000-8000-000000000001"
	static let systemCatalog = Locations.extensionResources.appending(path: "entries.json")
	static let invalidJSON = Data(#"{"a":}"#.utf8)
	static let aurora = AerialSet(
		slug: "aurora",
		displayName: "Aurora",
		subcategoryID: "A0000000-0000-4000-8000-000000000001",
		morning: .init("Dawn", assetID: "A0000000-0000-4000-8000-000000000011", shotID: "AU_001"),
		day: .init("Day", assetID: "A0000000-0000-4000-8000-000000000012", shotID: "AU_002"),
		evening: .init("Dusk", assetID: "A0000000-0000-4000-8000-000000000013", shotID: "AU_003"),
		night: .init("Night", assetID: "A0000000-0000-4000-8000-000000000014", shotID: "AU_004")
	)

	var root: [String: Any]

	init(sets: [AerialSet] = AerialSet.all) {
		let dynamic = ["D0000000-0000-4000-8000-000000000011", "D0000000-0000-4000-8000-000000000012"]
		let filler = ["F0000000-0000-4000-8000-000000000011", "F0000000-0000-4000-8000-000000000012"]
		var assets = zip(dynamic, ["light", "dark"]).enumerated().map { offset, entry in
			var asset = Self.asset(id: entry.0, shotID: "DYN_\(entry.1.uppercased())", subcategory: Self.dynamicSubcategoryID, category: "dynamic", order: offset, name: "Dynamic")
			asset["variant"] = ["appearance": entry.1, "orientation": "landscape"]
			return asset
		}
		for (index, set) in sets.enumerated() {
			assets += SunRole.replacementOrder.map { role in
				let video = set.video(role)
				return Self.asset(id: video.assetID, shotID: video.shotID, subcategory: set.subcategoryID, category: Self.landscapeCategoryID, order: role.rawValue * 10 + index, name: video.name)
			}
		}
		assets += filler.enumerated().map { offset, id in
			Self.asset(id: id, shotID: "FILLER_\(offset)", subcategory: Self.fillerSubcategoryID, category: Self.landscapeCategoryID, order: 100 + offset, name: "Filler")
		}
		let subcategories = sets.enumerated().map { index, set in
			Self.subcategory(set.subcategoryID, name: set.slug, order: index, representative: set.day.assetID)
		} + [Self.subcategory(Self.fillerSubcategoryID, name: "filler", order: sets.count, representative: filler[0])]
		var combined = Self.subcategory(Self.dynamicSubcategoryID, name: "dynamic", order: -500, representative: dynamic[0])
		combined["combineVariants"] = true
		root = [
			"version": 1,
			"localizationVersion": "test-1",
			"initialAssetCount": 4,
			"categories": [
				Self.category("dynamic", order: 0, subcategories: [combined]),
				Self.category(Self.landscapeCategoryID, order: 1, subcategories: subcategories),
			],
			"assets": assets,
		]
	}

	var data: Data {
		(try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])) ?? Data()
	}

	var catalog: AerialCatalog {
		AerialCatalog(url: URL(filePath: "/fixture/entries.json"), root: root)
	}

	var assets: [[String: Any]] {
		root["assets"] as? [[String: Any]] ?? []
	}

	func reorderedAssets(_ set: AerialSet) -> CatalogFixture {
		var copy = self
		var assets = self.assets
		if let index = assets.firstIndex(where: { $0["shotID"] as? String == set.evening.shotID }) {
			assets.insert(assets.remove(at: index), at: 0)
		}
		copy.root["assets"] = assets
		return copy
	}

	func reorderedPreferredOrder(_ set: AerialSet) -> CatalogFixture {
		let morning = assets.first { $0["shotID"] as? String == set.morning.shotID }?["preferredOrder"] as? Int ?? 0
		return changingAssets(of: set, role: .evening) { $0["preferredOrder"] = morning - 1 }
	}

	func missingShot(_ set: AerialSet, _ role: SunRole) -> CatalogFixture {
		var copy = self
		copy.root["assets"] = assets.filter { $0["shotID"] as? String != set.video(role).shotID }
		return copy
	}

	func missingSubcategory(_ set: AerialSet) -> CatalogFixture {
		changingSubcategories { $0.filter { $0["id"] as? String != set.subcategoryID } }
	}

	func duplicateShot(_ set: AerialSet, _ role: SunRole) -> CatalogFixture {
		var copy = self
		guard var duplicate = assets.first(where: { $0["shotID"] as? String == set.video(role).shotID }) else {
			return copy
		}
		duplicate["id"] = "DUPLICATE"
		copy.root["assets"] = assets + [duplicate]
		return copy
	}

	func movedShot(_ set: AerialSet, _ role: SunRole) -> CatalogFixture {
		changingAssets(of: set, role: role) { $0["subcategories"] = [Self.fillerSubcategoryID] }
	}

	func shippingSolar(_ sets: [AerialSet]) -> CatalogFixture {
		sets.reduce(combining(sets)) { catalog, set in
			SunRole.allCases.reduce(catalog) { catalog, role in
				catalog.changingAssets(of: set, role: role) { $0["variant"] = ["solar": ["altitude": 5, "azimuth": 100]] }
			}
		}
	}

	func shippingPartialSolar(_ set: AerialSet) -> CatalogFixture {
		changingAssets(of: set, role: .day) { $0["variant"] = ["solar": ["altitude": 5, "azimuth": 100]] }
	}

	func combiningWithoutSolar(_ sets: [AerialSet]) -> CatalogFixture {
		sets.reduce(combining(sets)) { catalog, set in
			SunRole.allCases.reduce(catalog) { catalog, role in
				catalog.changingAssets(of: set, role: role) { $0["variant"] = ["appearance": role == .night || role == .evening ? "dark" : "light"] }
			}
		}
	}

	func addingAssetWithoutShotID() -> CatalogFixture {
		var copy = self
		copy.root["assets"] = assets + [["id": "NO-SHOT", "url-4K-SDR-240FPS": "https://example.invalid/no-shot.mov"]]
		return copy
	}

	func nullVariant(_ set: AerialSet, _ role: SunRole) -> CatalogFixture {
		changingAssets(of: set, role: role) { $0["variant"] = NSNull() }
	}

	func without(_ set: AerialSet) -> CatalogFixture {
		var copy = missingSubcategory(set)
		copy.root["assets"] = assets.filter { !AerialCatalog.belongs($0, to: set.subcategoryID) }
		return copy
	}

	static func entries(of set: AerialSet, in root: [String: Any]) -> [Any] {
		let catalog = AerialCatalog(url: URL(filePath: "/"), root: root)
		return [catalog.subcategories.filter { $0["id"] as? String == set.subcategoryID }, catalog.assetDictionaries.filter { AerialCatalog.belongs($0, to: set.subcategoryID) }]
	}

	private func combining(_ sets: [AerialSet]) -> CatalogFixture {
		let ids = Set(sets.map(\.subcategoryID))
		return changingSubcategories { list in
			list.map { subcategory in
				var subcategory = subcategory
				if ids.contains(subcategory["id"] as? String ?? "") {
					subcategory["combineVariants"] = true
				}
				return subcategory
			}
		}
	}

	private func changingAssets(of set: AerialSet, role: SunRole, _ change: (inout [String: Any]) -> Void) -> CatalogFixture {
		var copy = self
		copy.root["assets"] = assets.map { asset in
			guard asset["shotID"] as? String == set.video(role).shotID, AerialCatalog.belongs(asset, to: set.subcategoryID) else {
				return asset
			}
			var asset = asset
			change(&asset)
			return asset
		}
		return copy
	}

	private func changingSubcategories(_ change: ([[String: Any]]) -> [[String: Any]]) -> CatalogFixture {
		var copy = self
		copy.root["categories"] = (root["categories"] as? [[String: Any]] ?? []).map { category in
			var category = category
			category["subcategories"] = change(category["subcategories"] as? [[String: Any]] ?? [])
			return category
		}
		return copy
	}

	private static func asset(id: String, shotID: String, subcategory: String, category: String, order: Int, name: String) -> [String: Any] {
		[
			"accessibilityLabel": name,
			"categories": [category],
			"id": id,
			"includeInShuffle": true,
			"localizedNameKey": "\(shotID)_NAME",
			"pointsOfInterest": [String: Any](),
			"preferredOrder": order,
			"previewImage": "https://example.invalid/\(shotID).png",
			"shotID": shotID,
			"showInTopLevel": true,
			"subcategories": [subcategory],
			"url-4K-SDR-240FPS": "https://example.invalid/\(shotID).mov",
		]
	}

	private static func subcategory(_ id: String, name: String, order: Int, representative: String) -> [String: Any] {
		[
			"id": id,
			"localizedDescriptionKey": "AerialSubcategoryDescription-\(name)",
			"localizedNameKey": "AerialSubcategory-\(name)",
			"preferredOrder": order,
			"previewImage": "https://example.invalid/\(name).png",
			"representativeAssetID": representative,
		]
	}

	private static func category(_ id: String, order: Int, subcategories: [[String: Any]]) -> [String: Any] {
		[
			"id": id,
			"localizedDescriptionKey": "AerialCategoryDescription-\(order)",
			"localizedNameKey": "AerialCategory-\(order)",
			"preferredOrder": order,
			"previewImage": "https://example.invalid/category-\(order).png",
			"representativeAssetID": "",
			"subcategories": subcategories,
		]
	}
}

nonisolated enum LayoutChange: String, CaseIterable, Sendable {
	case reorderedAssets
	case reorderedPreferredOrder
	case missingNight
	case missingSubcategory
	case duplicateMorning
	case movedNight

	func apply(to catalog: CatalogFixture, _ set: AerialSet) -> CatalogFixture {
		switch self {
		case .reorderedAssets: catalog.reorderedAssets(set)
		case .reorderedPreferredOrder: catalog.reorderedPreferredOrder(set)
		case .missingNight: catalog.missingShot(set, .night)
		case .missingSubcategory: catalog.missingSubcategory(set)
		case .duplicateMorning: catalog.duplicateShot(set, .morning)
		case .movedNight: catalog.movedShot(set, .night)
		}
	}
}

nonisolated enum CatalogVariant: String, CaseIterable, Sendable {
	case assetWithoutShotID
	case nullVariant
	case appleCombinesWithoutSolar
	case appleShipsPartialSolar

	var catalog: CatalogFixture {
		switch self {
		case .assetWithoutShotID: CatalogFixture().addingAssetWithoutShotID()
		case .nullVariant: CatalogFixture().nullVariant(.tahoe, .morning)
		case .appleCombinesWithoutSolar: CatalogFixture().combiningWithoutSolar([.tahoe])
		case .appleShipsPartialSolar: CatalogFixture().shippingPartialSolar(.goldenGate)
		}
	}
}
