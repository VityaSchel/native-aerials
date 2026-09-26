import Foundation

nonisolated enum ReplacementChoice: Equatable, CustomStringConvertible {
	case aerial(String)
	case systemDefault

	var description: String {
		switch self {
		case .aerial(let id): AerialSet.displayName(forAssetID: id)
		case .systemDefault: "the default wallpaper"
		}
	}
}

nonisolated struct StagedChoices {
	let file: URL
	let replacements: [(from: String, to: ReplacementChoice)]
	let converted: [ChoiceSlot]
	let revived: [ChoiceSlot]
	let selection: AerialChoice?
	let painted: Int
}

nonisolated struct WallpaperStore {
	let locations: Locations
	var listedAssetIDs: () -> [String] = { [] }

	var hasIndex: Bool {
		FileManager.default.fileExists(atPath: locations.indexSource.path)
	}

	func readIndex() throws -> WallpaperIndex {
		let url = locations.indexSource
		do {
			return try WallpaperIndex(data: Data(contentsOf: url))
		} catch {
			throw InstallerError("cannot read \(url.path)", summary: "Couldn’t read the saved wallpaper choice.")
		}
	}

	func stage(restoring subcategoryIDs: [String], selecting selection: AerialChoice? = nil, reviving slots: [ChoiceSlot] = []) throws -> StagedChoices? {
		guard hasIndex, !subcategoryIDs.isEmpty || selection != nil || !slots.isEmpty else {
			return nil
		}
		var index = try readIndex()
		let desktops = index.inUse(spaces: locations.desktopSpaceIDs, includingRecent: false)
		let isOnDesktop = { (path: [String]) in desktops.choiceAssetID(at: path) != nil }
		let setID = { (id: String) in AerialSet.set(containingAssetID: id)?.subcategoryID ?? id }
		let saved = index.choiceAssetIDs
		let replacements = subcategoryIDs.filter(saved.contains).map { (from: $0, to: replacement(forSubcategoryID: $0)) }
		let mapping = Dictionary(uniqueKeysWithValues: replacements.map { ($0.from, $0.to) })
		let revivals = Dictionary(slots.filter { isOnDesktop($0.path) }.map { ($0.path, $0) }) { first, _ in first }
		var converted: [ChoiceSlot] = []
		var revived: [ChoiceSlot] = []
		index.root = WallpaperIndex.mapDictionaries(in: index.root) { choice, path in
			guard let id = WallpaperIndex.assetID(ofChoice: choice) else {
				return choice
			}
			var choice = choice
			if let slot = revivals[path], setID(id) == setID(slot.video) {
				revived.append(slot)
				choice["Configuration"] = WallpaperIndex.configuration(for: slot.automatic) ?? choice["Configuration"]
				return choice
			}
			switch mapping[id] {
			case .aerial(let video)?:
				if isOnDesktop(path) {
					converted.append(ChoiceSlot(path: path, automatic: id, video: video))
				}
				choice["Configuration"] = WallpaperIndex.configuration(for: video) ?? choice["Configuration"]
				return choice
			case .systemDefault?:
				return WallpaperIndex.defaultChoice
			case nil:
				return choice
			}
		} as? [String: Any] ?? index.root
		var painted = 0
		if let selection {
			guard index.hasExpectedLayout else {
				throw InstallerError(
					"\(locations.indexSource.path) has a layout this version doesn't know; not changing the wallpaper",
					summary: InstallerError.selectionSummary
				)
			}
			painted = index.paint(selection, at: .now)
		}
		guard !replacements.isEmpty || !revived.isEmpty || painted > 0 else {
			return nil
		}
		let file = locations.stagedIndexFile
		try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
		try index.data().write(to: file, options: .atomic)
		return StagedChoices(file: file, replacements: replacements, converted: converted, revived: revived, selection: selection, painted: painted)
	}

	func commit(_ staged: StagedChoices) throws {
		locations.dryRun?.record("replace \(locations.realIndexFile.path)")
		guard rename(staged.file.path, locations.indexFile.path) == 0 else {
			throw InstallerError("could not replace \(locations.indexFile.path): \(String(cString: strerror(errno)))", summary: InstallerError.saveSummary)
		}
	}

	func discard(_ staged: StagedChoices?) {
		guard let staged else {
			return
		}
		try? FileManager.default.removeItem(at: staged.file)
	}

	func replacement(forSubcategoryID id: String) -> ReplacementChoice {
		let set = AerialSet.set(forSubcategoryID: id)
		let ours = (set.map { [$0] } ?? []) + AerialSet.all.filter { $0 != set }
		let candidates = ours.flatMap(\.replacementCandidates).map(\.assetID)
		if let downloaded = candidates.first(where: locations.isDownloaded) ?? listedAssetIDs().first(where: locations.isDownloaded) {
			return .aerial(downloaded)
		}
		return .systemDefault
	}
}
