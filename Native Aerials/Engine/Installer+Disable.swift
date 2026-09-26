import Foundation

nonisolated extension Installer {
	func disable(remembering: Bool = false) throws {
		try ensureNoDownloadInFlight()
		let preferences = preferences
		var ours = true
		var restoring: [String] = []
		if let override = preferences.overridePath, override != locations.catalogTarget {
			log.warn("\(AerialPreferences.overrideKey) points at \(override), which Native Aerials did not write; leaving both keys and the saved wallpaper choice alone")
			ours = false
		} else {
			let source = sourceCatalog()
			restoring = AerialSet.all.map(\.subcategoryID).filter { source?.combines(subcategoryID: $0) != true }
		}
		let staged = try stageChoices(restoring: restoring, selecting: nil)
		logReplacements(staged)
		var undone = false
		do {
			if ours {
				for key in [AerialPreferences.overrideKey, AerialPreferences.forceLocalKey] where preferences.text(forKey: key) != nil {
					try preferences.removeValue(forKey: key)
					undone = true
				}
			}
			if try removeCustomDirectory() {
				undone = true
			}
		} catch {
			store.discard(staged)
			throw error
		}
		guard undone || staged != nil else {
			log.note("Native Aerials is not installed; nothing to do")
			return
		}
		try commitRestarting(staged)
		if remembering {
			rememberAutomatic(staged?.converted ?? [])
		}
		if staged != nil {
			verifyChoices(restoring: restoring, selecting: nil)
		}
		log.note("Disabled. macOS is back on Apple's own aerial catalog.")
	}

	@discardableResult
	func verifyChoices(restoring subcategoryIDs: [String], selecting choice: AerialChoice?, reviving slots: [ChoiceSlot] = []) -> Bool {
		guard locations.dryRun == nil else {
			return choicesSettled(restoring: subcategoryIDs, selecting: choice, reviving: slots)
		}
		processes.pause(seconds: 1)
		if choicesSettled(restoring: subcategoryIDs, selecting: choice, reviving: slots) {
			return true
		}
		log.note("WallpaperAgent wrote the old choice back; rewriting it once more")
		do {
			if let staged = try store.stage(restoring: subcategoryIDs, selecting: choice, reviving: slots) {
				try commitRestarting(staged)
				processes.pause(seconds: 1)
			}
			if choicesSettled(restoring: subcategoryIDs, selecting: choice, reviving: slots) {
				return true
			}
		} catch {}
		if choice != nil {
			log.warn("WallpaperAgent did not take the new wallpaper; pick it in System Settings > Wallpaper")
		} else if !subcategoryIDs.isEmpty {
			log.warn(
				"the saved wallpaper choice still points at a combined item; open System Settings > Wallpaper and pick a video on every desktop",
				notice: "Wallpaper settings didn’t switch to a single video. Pick a video in Wallpaper settings on every desktop."
			)
		} else {
			log.warn(
				"WallpaperAgent kept the single video instead of Automatic; pick the combined item in System Settings > Wallpaper",
				notice: "Wallpaper settings kept a single video. Pick the combined item in Wallpaper settings to use Automatic."
			)
		}
		return false
	}

	func commitRestarting(_ staged: StagedChoices?) throws {
		do {
			try processes.restart {
				if let staged {
					try store.commit(staged)
				}
			}
		} catch {
			store.discard(staged)
			throw error
		}
	}

	private func choicesSettled(restoring subcategoryIDs: [String], selecting choice: AerialChoice?, reviving slots: [ChoiceSlot]) -> Bool {
		guard let index = try? store.readIndex() else {
			return false
		}
		let saved = index.choiceAssetIDs
		let restored = !subcategoryIDs.contains(where: saved.contains) && slots.allSatisfy { index.choiceAssetID(at: $0.path) == $0.automatic }
		guard let choice else {
			return restored
		}
		return restored && index.showsEverywhere(choice)
	}

	private func removeCustomDirectory() throws -> Bool {
		var isDirectory: ObjCBool = false
		guard FileManager.default.fileExists(atPath: locations.customDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
			return false
		}
		let command = "remove \(locations.realCustomDirectory.path)"
		if let dryRun = locations.dryRun {
			log.note("[dry-run] would \(command)")
			dryRun.record(command)
		} else {
			log.note(command)
		}
		try FileManager.default.removeItem(at: locations.customDirectory)
		return true
	}
}
