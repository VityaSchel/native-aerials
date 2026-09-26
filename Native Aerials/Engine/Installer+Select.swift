import Foundation

nonisolated struct SelectOutcome: Sendable, Equatable {
	var changed: Bool
	var downloadFollows: Bool
}

nonisolated extension Installer {
	func select(_ choice: AerialChoice) throws -> SelectOutcome {
		try checkSelectable(choice)
		try ensureNoDownloadInFlight()
		guard store.hasIndex else {
			throw InstallerError("no saved wallpaper settings at \(locations.indexSource.path)", summary: InstallerError.selectionSummary)
		}
		let downloadFollows = !isOnDisk(choice)
		let staged = try stageChoices(restoring: [], selecting: choice)
		forgetAutomatic()
		guard let staged else {
			log.note("\(choice) is already the wallpaper everywhere; nothing changed")
			return SelectOutcome(changed: false, downloadFollows: downloadFollows)
		}
		try commitRestarting(staged)
		logReplacements(staged)
		guard verifyChoices(restoring: [], selecting: choice) else {
			throw InstallerError("WallpaperAgent did not take \(choice)", summary: InstallerError.selectionSummary)
		}
		if downloadFollows {
			log.note("macOS downloads the rest of \(choice) in the background")
		}
		return SelectOutcome(changed: true, downloadFollows: downloadFollows)
	}

	func isOnDisk(_ choice: AerialChoice) -> Bool {
		switch choice {
		case .video(let id): locations.isDownloaded(assetID: id)
		case .automatic: choice.set.map { missingVideos(of: $0).isEmpty } ?? false
		}
	}

	private func checkSelectable(_ choice: AerialChoice) throws {
		switch choice {
		case .video(let id):
			guard let video = AerialSet.video(withAssetID: id) else {
				throw InstallerError("\(id) is not an aerial video Native Aerials knows", summary: InstallerError.selectionSummary)
			}
			guard locations.isDownloaded(assetID: id) else {
				throw InstallerError(
					"\(video.name) is not downloaded, and macOS only downloads an aerial that is picked in System Settings > Wallpaper; nothing was changed",
					summary: "\(video.name) isn’t downloaded yet. Download it in Wallpaper settings first."
				)
			}
		case .automatic(let id):
			guard let set = AerialSet.set(forSubcategoryID: id) else {
				throw InstallerError("\(id) is not an aerial set Native Aerials knows", summary: InstallerError.selectionSummary)
			}
			guard activeCatalog()?.combines(subcategoryID: id) == true else {
				throw InstallerError(
					"\(set.displayName) is not combined right now, so it has no Automatic item",
					summary: "\(set.displayName) isn’t combined right now. Turn Native Aerials on first."
				)
			}
		}
	}

	func activeCatalog() -> AerialCatalog? {
		installation() == .enabled ? installedCatalog() : sourceCatalog()
	}
}
