import Foundation

nonisolated struct AerialCatalog {
	let url: URL
	let root: [String: Any]

	var assets: [Any] {
		root["assets"] as? [Any] ?? []
	}

	var assetDictionaries: [[String: Any]] {
		assets.compactMap { $0 as? [String: Any] }
	}

	var hasAssets: Bool {
		switch root["assets"] {
		case let array as [Any]: !array.isEmpty
		case let dictionary as [String: Any]: !dictionary.isEmpty
		default: false
		}
	}

	var categoryIDs: Set<String> {
		Set((root["categories"] as? [Any] ?? []).compactMap { ($0 as? [String: Any])?["id"] as? String })
	}

	var subcategories: [[String: Any]] {
		(root["categories"] as? [Any] ?? []).flatMap { category -> [[String: Any]] in
			let list = (category as? [String: Any])?["subcategories"] as? [Any] ?? []
			return list.compactMap { $0 as? [String: Any] }
		}
	}

	func combines(subcategoryID: String) -> Bool {
		subcategories.contains { $0["id"] as? String == subcategoryID && JSONTree.isTrue($0["combineVariants"]) }
	}

	var combinedSets: [AerialSet] {
		AerialSet.all.filter { combines(subcategoryID: $0.subcategoryID) }
	}

	func shipsSolarData(for set: AerialSet) -> Bool {
		combines(subcategoryID: set.subcategoryID) && set.shotIDs.allSatisfy { shotID in
			assetDictionaries.contains { asset in
				asset["shotID"] as? String == shotID && !JSONTree.isNull(Self.solar(of: asset))
			}
		}
	}

	func mentions(_ set: AerialSet) -> Bool {
		subcategories.contains { $0["id"] as? String == set.subcategoryID }
			|| assetDictionaries.contains { Self.belongs($0, to: set.subcategoryID) || set.assetIDs.contains($0["id"] as? String ?? "") }
	}

	static func solar(of asset: [String: Any]) -> Any? {
		(asset["variant"] as? [String: Any])?["solar"]
	}

	static func belongs(_ asset: [String: Any], to subcategoryID: String) -> Bool {
		(asset["subcategories"] as? [Any] ?? []).contains { $0 as? String == subcategoryID }
	}
}

nonisolated extension AerialCatalog {
	init(contentsOf url: URL) throws {
		let data = try Data(contentsOf: url)
		guard let root = try JSONTree.parse(data) as? [String: Any] else {
			throw InstallerError("\(url.path) is not an aerial catalog")
		}
		self.init(url: url, root: root)
	}

	static func loadIfValid(_ url: URL) -> AerialCatalog? {
		try? AerialCatalog(contentsOf: url)
	}

	var hasExpectedStructure: Bool {
		root["categories"] is [Any] && root["assets"] is [Any]
	}

	func hasExpectedLayout(of set: AerialSet) -> Bool {
		guard subcategories.filter({ $0["id"] as? String == set.subcategoryID }).count == 1 else {
			return false
		}
		let entries = indexedEntries(in: set)
		guard set.shotIDs.allSatisfy({ shotID in entries.filter { $0.shotID == shotID }.count == 1 }),
			let morning = entries.first(where: { $0.shotID == set.video(.morning).shotID }),
			let evening = entries.first(where: { $0.shotID == set.video(.evening).shotID })
		else {
			return false
		}
		return morning.index < evening.index && JSONTree.isLess(morning.preferredOrder, evening.preferredOrder)
	}

	private func indexedEntries(in set: AerialSet) -> [(index: Int, shotID: String, preferredOrder: Any?)] {
		assets.enumerated().compactMap { index, element in
			guard let asset = element as? [String: Any],
				let shotID = asset["shotID"] as? String,
				Self.belongs(asset, to: set.subcategoryID)
			else {
				return nil
			}
			return (index, shotID, asset["preferredOrder"])
		}
	}
}
