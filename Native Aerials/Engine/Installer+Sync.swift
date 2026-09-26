import Foundation

nonisolated enum SyncResult: String, Sendable {
	case notOn = "not-on"
	case unavailable
	case unchanged
	case deferred
	case updated
	case turnedOff = "turned-off"
}

nonisolated struct SyncOutcome: Sendable {
	var result: SyncResult
	var missingAssetIDs: [String] = []
}

nonisolated extension Installer {
	func sync(selecting choice: AerialChoice? = nil) throws -> SyncOutcome {
		guard installation() == .enabled else {
			return SyncOutcome(result: .notOn)
		}
		guard (try? preflight()) != nil else {
			return SyncOutcome(result: .unavailable)
		}
		let plan = mergePlan()
		guard let source = plan.source else {
			throw InstallerError("could not read \(plan.sourceURL.path)", summary: InstallerError.unexpectedCatalogSummary)
		}
		if let recorded = InstallState.load(from: locations.stateFile)?.source, recorded != source.url.path, source.url.path == locations.bundledCatalog.path {
			log.note("\(recorded) can't be read right now; syncing once Apple finishes writing it")
			return SyncOutcome(result: .deferred)
		}
		if isDownloadInFlight() {
			log.note("a video is downloading; syncing after it finishes so the download isn't interrupted")
			return SyncOutcome(result: .deferred, missingAssetIDs: plan.missingAssetIDs)
		}
		if try stepsAside(for: plan) {
			return SyncOutcome(result: .turnedOff)
		}
		var outcome = SyncOutcome(result: .unchanged, missingAssetIDs: plan.missingAssetIDs)
		let selection = choice.flatMap { choice -> AerialChoice? in
			guard case .automatic(let id) = choice else {
				return choice
			}
			return plan.readySets.contains { $0.subcategoryID == id } ? choice : nil
		}
		if selection == nil && isRecorded(plan) {
			return outcome
		}
		do {
			guard try apply(CatalogPatcher.patch(source, sets: plan.readySets), plan: plan, selecting: selection, restartsWhenStateIsStale: true) else {
				return outcome
			}
		} catch let error as InstallerError where error.summary == InstallerError.unexpectedCatalogSummary {
			log.warn("\(error.message) Turning Native Aerials off.")
			try disable()
			return SyncOutcome(result: .turnedOff)
		}
		outcome.result = .updated
		return outcome
	}

	var recordsCurrentSystem: Bool {
		let state = InstallState.load(from: locations.stateFile)
		return state?.osBuild == SystemInfo.buildVersion && state?.bundledDigest == SystemInfo.sha256(of: locations.bundledCatalog)
	}

	func isDownloadInFlight() -> Bool {
		!DownloadActivity.inFlightIDs(at: locations.downloadActivityFile).isEmpty
	}

	func ensureNoDownloadInFlight() throws {
		let ids = DownloadActivity.inFlightIDs(at: locations.downloadActivityFile)
		guard !ids.isEmpty else {
			return
		}
		let name = ids.lazy.compactMap { AerialSet.video(withAssetID: $0)?.name }.first
		let what = name.map { "“\($0)”" } ?? "the wallpaper"
		throw InstallerError(
			"\(name ?? "a wallpaper") is downloading; restarting the wallpaper service now would leave System Settings stuck on that download, so nothing was changed",
			summary: "Wait for \(what) to finish downloading."
		)
	}

	private func isRecorded(_ plan: MergePlan) -> Bool {
		InstallState.load(from: locations.stateFile) == InstallState.current(source: plan.sourceURL, bundled: locations.bundledCatalog, catalog: locations.catalogFile, sets: plan.readySets)
	}
}
