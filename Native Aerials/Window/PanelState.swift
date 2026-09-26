import Foundation

nonisolated struct PanelState: Equatable, Sendable {
	var snapshot: WallpaperSnapshot?
	var downloads = DownloadTracker()
	var liveSelection = AerialSelection()
	var flashes: [String: Int] = [:]
	var chosenID: String?
	var switchIntent: Bool?
	var animatesMerge = false
	var message: Footnote?
	var isWorking = false
	var isReady = false

	var switchIsOn: Bool {
		switchIntent ?? snapshot.map { $0.isOn || $0.needsRepair } ?? false
	}

	var canToggle: Bool {
		guard isReady, !isWorking, let snapshot else {
			return false
		}
		return snapshot.isOn || snapshot.needsRepair || snapshot.availability == .available
	}

	var isLoaded: Bool { snapshot != nil }

	var tilesAreInteractive: Bool { isReady && snapshot != nil }

	var selectedID: String? { chosenID ?? snapshot?.selectedAssetID }

	var hasDownloadsInFlight: Bool { !downloads.inFlightIDs.isEmpty }

	var protectedAssetIDs: Set<String> {
		guard snapshot?.shufflesAerials != true else {
			return AerialSet.allIDs
		}
		let saved = (snapshot?.savedAssetIDs ?? []).union([selectedID].compactMap { $0 })
		return AerialSet.addingVideos(ofSetsIn: saved).union(liveSelection.protectedAssetIDs)
	}

	var rows: [SetRow] {
		guard let snapshot else {
			return AerialSet.all.map(Self.placeholder)
		}
		let protected = protectedAssetIDs
		let mayRemove = tilesAreInteractive && !isWorking
		return snapshot.sets.map { set in
			let removable = set.variants.filter { $0.download == .onDisk && $0.assetID != AerialSet.systemDefaultAssetID }.map(\.assetID)
			return SetRow(
				id: set.subcategoryID,
				name: set.name,
				tiles: set.variants.map { variant in
					let status = downloads.status(of: variant)
					return TileItem(
						id: variant.assetID,
						name: variant.name,
						thumbnail: variant.thumbnail,
						status: status,
						isSelected: selectedID == variant.assetID,
						flash: flashes[variant.assetID] ?? 0,
						canRemove: mayRemove && status == .ready && removable.contains(variant.assetID) && !protected.contains(variant.assetID)
					)
				},
				isMerged: displaysMerged(set),
				isSelected: selectedID == set.subcategoryID,
				canRemove: mayRemove && !removable.isEmpty && !protected.contains(set.subcategoryID) && !removable.contains(where: protected.contains),
				animatesMerge: animatesMerge
			)
		}
	}

	var needsUnmerge: Bool {
		guard let snapshot, snapshot.isOn else {
			return false
		}
		return snapshot.sets.contains { $0.isMerged && !$0.isMergedByApple && !$0.isComplete }
	}

	var needsMerge: Bool {
		guard let snapshot, snapshot.isOn else {
			return false
		}
		return snapshot.sets.contains { $0.readiness == .ready && !$0.isMerged }
	}

	var onDiskAssetIDs: Set<String> { snapshot?.onDiskAssetIDs ?? [] }

	func firstMissingTile(closestToComplete missingAssetIDs: [String]) -> TileItem? {
		let missing = Set(missingAssetIDs)
		return rows.map { $0.tiles.filter { missing.contains($0.id) } }.filter { !$0.isEmpty }.min { $0.count < $1.count }?.first
	}

	func displaysMerged(_ set: SetSnapshot) -> Bool {
		switch switchIntent {
		case true?: set.isMerged || set.readiness == .ready
		case false?: set.isMergedByApple
		case nil: set.isMerged
		}
	}

	mutating func flash(_ assetIDs: [String]) {
		for id in assetIDs {
			flashes[id, default: 0] += 1
		}
	}

	private static func placeholder(_ set: AerialSet) -> SetRow {
		SetRow(
			id: set.subcategoryID,
			name: set.displayName,
			tiles: set.videos.map { video in
				TileItem(id: video.assetID, name: video.name, thumbnail: nil, status: .loading, isSelected: false, flash: 0)
			},
			isMerged: false,
			isSelected: false
		)
	}
}
