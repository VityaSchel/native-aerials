import AppKit
import SwiftUI

extension AppModel {
	static let minimumSwitchTime: TimeInterval = 0.5

	func setEnabled(_ isOn: Bool) {
		guard state.canToggle, isOn != state.switchIsOn else {
			return
		}
		pendingChoice = nil
		state.chosenID = nil
		state.message = nil
		state.switchIntent = isOn
		state.animatesMerge = true
		let started = Date.now
		launch {
			switch await self.perform({ try isOn ? $0.turnOn() : $0.turnOff() }) {
			case .success(let report):
				self.state.flash(report.missingAssetIDs)
				self.state.message = PanelState.message(after: report)
			case .failure(let error):
				self.state.flash(error.missingAssetIDs)
				self.state.message = PanelState.message(for: error)
				if !error.missingAssetIDs.isEmpty {
					AccessibilityNotification.Announcement(error.summary).post()
				}
				let remaining = Self.minimumSwitchTime - Date.now.timeIntervalSince(started)
				if remaining > 0 {
					try? await Task.sleep(for: .seconds(remaining))
				}
			}
			withAnimation(.spring(duration: 0.45)) {
				self.state.switchIntent = nil
			}
		}
	}

	func choose(_ tile: TileItem) {
		guard state.tilesAreInteractive, state.rows.first(where: { $0.tiles.contains { $0.id == tile.id } })?.isMerged == false else {
			return
		}
		switch tile.status {
		case .ready:
			select(.video(tile.id))
		case .missing:
			state.flash([tile.id])
			open(.wallpaper)
			hintDownload(of: tile)
		case .downloading:
			open(.wallpaper)
		case .loading:
			break
		}
	}

	func chooseMerged(_ row: SetRow) {
		guard state.tilesAreInteractive, row.isMerged else {
			return
		}
		select(.automatic(row.id))
	}

	func removeDownload(_ choice: AerialChoice) {
		guard state.tilesAreInteractive, !state.isWorking else {
			return
		}
		state.message = nil
		let pinned = state.protectedAssetIDs
		launch {
			switch await self.perform({ try $0.removeDownload(of: choice, keeping: pinned) }) {
			case .success(let report):
				self.removedByUser.formUnion(report.removedAssetIDs)
				self.state.message = PanelState.message(after: report)
			case .failure(let error):
				self.state.message = PanelState.message(for: error)
			}
		}
	}

	func open(_ pane: SettingsPane) {
		engine?.open(pane)
	}

	func launchSelect(_ choice: AerialChoice) {
		launch {
			let result = await self.perform { try $0.select(choice) }
			self.state.chosenID = self.pendingChoice?.assetID
			switch result {
			case .success(let report):
				self.state.message = PanelState.message(after: report)
			case .failure(let error):
				self.state.message = PanelState.message(for: error, action: .wallpaper)
			}
		}
	}

	func launchSync() {
		let mergedBefore = state.snapshot?.mergedSetIDs ?? []
		let onDisk = state.onDiskAssetIDs
		launch {
			switch await self.perform({ try $0.sync() }) {
			case .success(let report):
				self.failedSyncVideos = nil
				let after = report.snapshot ?? self.state.snapshot
				let unmerged = mergedBefore.subtracting(after?.mergedSetIDs ?? [])
				let missing = (after?.sets ?? []).filter { unmerged.contains($0.subcategoryID) }.flatMap(\.missingAssetIDs)
				self.state.flash(missing.filter { !self.removedByUser.contains($0) })
				self.state.message = PanelState.message(after: report)
			case .failure(let error):
				self.failedSyncVideos = onDisk
				self.state.message = PanelState.message(for: error)
			}
		}
	}

	private func hintDownload(of tile: TileItem) {
		let text = "Download “\(tile.name)” first"
		if let dryRun = engine?.locations.dryRun {
			dryRun.record("hint \(text)")
			return
		}
		settingsHint.show(text, thumbnail: tile.thumbnail.flatMap(NSImage.init(contentsOf:))) { [weak self] in
			self?.state.rows.lazy.flatMap(\.tiles).first { $0.id == tile.id }?.status == .missing
		}
	}

	private func select(_ choice: AerialChoice) {
		state.message = nil
		state.chosenID = choice.assetID
		pendingChoice = choice
		reconcile()
	}
}
