import Foundation

nonisolated struct EnableOutcome: Sendable {
	var changed = false
	var missingAssetIDs: [String] = []
}

nonisolated extension Installer {
	func enable(opensSettings: Bool = true) throws -> EnableOutcome {
		guard !needsMoveToApplications else {
			let folders = locations.applicationFolders?.joined(separator: " or ") ?? "the Applications folder"
			throw InstallerError("Native Aerials runs from \(executablePath); it turns on only from \(folders), so move it there and open it again. Nothing was changed.", summary: Self.moveNotice)
		}
		try preflight()
		try checkOverrideIsOurs()
		try ensureNoDownloadInFlight()
		let plan = mergePlan()
		if try stepsAside(for: plan) {
			removeAgent()
			forgetAutomatic()
			return EnableOutcome()
		}
		guard let source = plan.source, !plan.readySets.isEmpty else {
			throw nothingToMerge(plan)
		}
		let patched = try CatalogPatcher.patch(source, sets: plan.readySets)
		var outcome = EnableOutcome(missingAssetIDs: plan.missingAssetIDs)
		outcome.changed = try apply(patched, plan: plan, reviving: automaticRecord?.slots ?? [], restartsWhenStateIsStale: false)
		forgetAutomatic()
		installAgentReporting()
		log.note("")
		log.note("Combined: \(patched.sets.map(\.slug).joined(separator: " "))")
		for set in plan.appleSets {
			log.note("Apple already combines \(set.displayName) itself")
		}
		reportVideos(of: plan.listedSets)
		log.note("")
		if !outcome.changed {
			log.note("Already enabled; nothing changed.")
		}
		log.note("In System Settings > Wallpaper, each combined set is one item now (\(patched.sets.map(\.displayName).joined(separator: ", "))). Pick one and leave its menu on Automatic.")
		if outcome.changed && opensSettings {
			processes.openWallpaperSettings()
		}
		return outcome
	}

	func apply(_ patched: PatchedCatalog, plan: MergePlan, selecting choice: AerialChoice? = nil, reviving slots: [ChoiceSlot] = [], restartsWhenStateIsStale: Bool) throws -> Bool {
		let wasCurrent = recordsCurrentSystem
		let merged = installation() == .enabled ? installedCatalog()?.combinedSets ?? [] : []
		if let changed = merged.first(where: { plan.readiness[$0] == .unexpectedLayout }) {
			throw InstallerError.unexpectedCatalog(plan.sourceURL, "\(changed.displayName) is no longer where this version expects it")
		}
		let unmerging = merged.filter { !patched.sets.contains($0) && !plan.sourceCombines($0) }
		let restoring = unmerging.map(\.subcategoryID)
		let reviving = slots.filter { patched.catalog.combines(subcategoryID: $0.automatic) }
		let staged = try stageChoices(restoring: restoring, selecting: choice, reviving: reviving)
		let checkpoint = Checkpoint(self)
		var changed = false
		do {
			if !installedCatalogMatches(patched) {
				log.note("changes against \(plan.sourceURL.path):")
				patched.changes.forEach { log.note("  \($0)") }
				try writeCatalog(patched.data)
				log.note("wrote \(locations.catalogFile.path) (\(patched.data.count) bytes, patched copy of \(plan.sourceURL.path))")
				changed = true
			}
			try writeState(patched, sourceURL: plan.sourceURL)
			let preferences = preferences
			if preferences.overridePath != locations.catalogTarget {
				try preferences.set(locations.catalogTarget, forKey: AerialPreferences.overrideKey)
				changed = true
			}
			if preferences.forceLocal != "1" {
				try preferences.set(true, forKey: AerialPreferences.forceLocalKey)
				changed = true
			}
			if changed || staged != nil || (restartsWhenStateIsStale && !wasCurrent) {
				try commitRestarting(staged)
			}
		} catch {
			store.discard(staged)
			checkpoint.restore(self)
			throw error
		}
		for set in unmerging {
			log.note("split \(set.displayName): \(plan.readiness[set] == .notInCatalog ? "Apple's catalog no longer lists it" : "not every video is on disk")")
		}
		logReplacements(staged)
		if let staged {
			verifyChoices(restoring: restoring, selecting: choice, reviving: staged.revived)
		}
		return changed || staged != nil
	}

	func stepsAside(for plan: MergePlan) throws -> Bool {
		guard plan.appleProvidesAll else {
			return false
		}
		log.note("Apple's catalog now has its own solar data for: \(plan.appleSets.map(\.slug).sorted().joined(separator: " ")). Removing Native Aerials.")
		try disable()
		return true
	}

	func nothingToMerge(_ plan: MergePlan) -> InstallerError {
		let missing = plan.missingAssetIDs
		guard !missing.isEmpty else {
			if plan.hasUnexpectedLayout {
				return InstallerError.unexpectedCatalog(plan.sourceURL)
			}
			return InstallerError("no set can be combined; nothing was changed")
		}
		let names = missing.map { AerialSet.displayName(forAssetID: $0) }.joined(separator: ", ")
		return InstallerError(
			"no set has all four videos on disk (missing: \(names)); nothing was changed. Download the missing videos first: pick each one in Native Aerials or System Settings > Wallpaper.",
			summary: "Download every video of a set first",
			missingAssetIDs: missing
		)
	}

	func stageChoices(restoring subcategoryIDs: [String], selecting choice: AerialChoice?, reviving slots: [ChoiceSlot] = []) throws -> StagedChoices? {
		do {
			return try store.stage(restoring: subcategoryIDs, selecting: choice, reviving: slots)
		} catch let error as InstallerError where choice != nil {
			throw error
		} catch _ where subcategoryIDs.isEmpty && choice == nil {
			return nil
		} catch {
			throw InstallerError(
				"could not prepare the saved wallpaper choice (\(locations.indexSource.path)); nothing was changed. Pick a single video in System Settings > Wallpaper, then try again.",
				summary: "Couldn’t read the saved wallpaper choice, so nothing was changed. Pick a single video in Wallpaper settings, then try again."
			)
		}
	}

	func logReplacements(_ staged: StagedChoices?) {
		for replacement in staged?.replacements ?? [] {
			log.note("saved wallpaper choice: \(AerialSet.displayName(forAssetID: replacement.from)) -> \(replacement.to)")
		}
		var revived = Set<[String]>()
		for slot in staged?.revived ?? [] where revived.insert([slot.video, slot.automatic]).inserted {
			log.note("saved wallpaper choice: \(AerialSet.displayName(forAssetID: slot.video)) -> \(AerialSet.displayName(forAssetID: slot.automatic)) again, as before turning off")
		}
		if let selection = staged?.selection, let painted = staged?.painted, painted > 0 {
			log.note("wallpaper: \(selection) on \(painted) desktop\(painted == 1 ? "" : "s")")
		}
	}
}
