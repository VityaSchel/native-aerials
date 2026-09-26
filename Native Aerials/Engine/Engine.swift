import AppKit
import ServiceManagement

nonisolated enum SettingsPane: Sendable {
	case wallpaper
	case loginItems
	case dateTime
}

nonisolated struct EngineReport: Sendable {
	var missingAssetIDs: [String] = []
	var removedAssetIDs: [String] = []
	var notices: [String] = []
	var snapshot: WallpaperSnapshot?
}

nonisolated struct Engine: Sendable {
	private static let queue = DispatchQueue(label: "dev.hloth.native-aerials.engine", qos: .userInitiated)

	let locations: Locations

	static func current() throws -> Engine {
		guard !SystemInfo.isRoot else {
			throw InstallerError("Run Native Aerials as your own user: wallpaper settings are per user.")
		}
		return Engine(locations: Locations(dryRun: try DryRun.environmentPath.map(DryRun.prepare)))
	}

	func run<T: Sendable>(_ work: @escaping @Sendable (Engine) throws -> T) async throws -> T {
		try await withCheckedThrowingContinuation { continuation in
			Self.queue.async {
				continuation.resume(with: Result(catching: { try work(self) }))
			}
		}
	}

	func snapshot() -> WallpaperSnapshot {
		WallpaperSnapshot(installer(Log(echoes: false)))
	}

	func agentState() -> AgentState {
		WallpaperSnapshot.agentState(installer(Log(echoes: false)))
	}

	func changes() -> AsyncStream<SystemChange> {
		SystemWatcher.changes(for: locations)
	}

	func downloadEvents() -> AsyncStream<DownloadEvent> {
		DownloadMonitor.events()
	}

	func turnOn() throws -> EngineReport {
		try perform { installer in
			let outcome = try installer.enable(opensSettings: false)
			return EngineReport(missingAssetIDs: outcome.missingAssetIDs)
		}
	}

	func turnOff() throws -> EngineReport {
		try perform { installer in
			try installer.disable(remembering: true)
			installer.removeAgent()
			return EngineReport()
		}
	}

	func sync() throws -> EngineReport {
		try perform { installer in
			let outcome = try installer.sync()
			if outcome.result == .turnedOff {
				installer.removeAgent()
			}
			return EngineReport(missingAssetIDs: outcome.missingAssetIDs)
		}
	}

	func select(_ choice: AerialChoice) throws -> EngineReport {
		try perform { installer in
			_ = try installer.select(choice)
			return EngineReport()
		}
	}

	func removeDownload(of choice: AerialChoice, keeping pinned: Set<String>) throws -> EngineReport {
		try perform { installer in
			EngineReport(removedAssetIDs: try installer.removeDownload(of: choice, keeping: pinned))
		}
	}

	func recordDownloads(_ assetIDs: Set<String>) {
		DownloadActivity.record(assetIDs, to: locations.downloadActivityFile)
	}

	func upgradeOwnArtifacts() throws -> EngineReport {
		guard installer(Log(echoes: false)).hasArtifactsToUpgrade else {
			return EngineReport()
		}
		return try perform { installer in
			installer.upgradeOwnArtifacts()
			return EngineReport()
		}
	}

	@MainActor
	func open(_ pane: SettingsPane) {
		if let dryRun = locations.dryRun {
			dryRun.record("open \(pane)")
			return
		}
		switch pane {
		case .wallpaper: NSWorkspace.shared.open(Locations.settingsURL)
		case .dateTime: NSWorkspace.shared.open(Locations.dateTimeSettingsURL)
		case .loginItems: SMAppService.openSystemSettingsLoginItems()
		}
	}

	private func installer(_ log: Log) -> Installer {
		Installer(locations: locations, log: log)
	}

	private func perform(_ work: (Installer) throws -> EngineReport) throws -> EngineReport {
		let log = Log(echoes: false)
		let installer = installer(log)
		var report = try installer.locked {
			try work(installer)
		}
		report.notices = log.notices
		report.snapshot = WallpaperSnapshot(installer)
		return report
	}
}
