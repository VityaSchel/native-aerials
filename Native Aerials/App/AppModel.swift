import AppKit
import Observation
import SwiftUI

@Observable
final class AppModel {
	static let syncDelay: TimeInterval = 2

	var state = PanelState()
	let thumbnails = ThumbnailStore()
	let settingsHint = SettingsHint()
	@ObservationIgnored var engine: Engine?
	@ObservationIgnored var pendingChoice: AerialChoice?
	@ObservationIgnored var failedSyncVideos: Set<String>?
	@ObservationIgnored var removedByUser: Set<String> = []
	@ObservationIgnored var downloadFeed: Task<Void, Never>?
	@ObservationIgnored var stallTimer: Task<Void, Never>?
	@ObservationIgnored var stallDeadline: Date?
	@ObservationIgnored var publishedDownloads: Set<String>?
	@ObservationIgnored var publishedAt: Date?
	@ObservationIgnored var isQuitting = false
	@ObservationIgnored private var videosChangedAt: Date?
	@ObservationIgnored private var idleActions: [() -> Void] = []

	var isWorking: Bool { state.isWorking }

	func start(using makeEngine: () throws -> Engine = Engine.current) async {
		guard engine == nil else {
			return
		}
		do {
			engine = try makeEngine()
		} catch {
			state.message = Footnote(text: InstallerError(describing: error).summary, tone: .error)
			return
		}
		watchDownloads()
		await loadFirstSnapshot()
		state.isWorking = true
		switch await perform({ try $0.upgradeOwnArtifacts() }) {
		case .success(let report):
			state.message = PanelState.message(after: report)
		case .failure(let error):
			state.message = PanelState.message(for: error)
		}
		finishWork()
		state.isReady = true
		reconcile()
		await watchChanges()
	}

	func quitWhenIdle(_ action: @escaping () -> Void) {
		isQuitting = true
		guard state.isWorking else {
			action()
			return
		}
		idleActions.append(action)
	}

	func reconcile() {
		guard state.isReady, !state.isWorking, !isQuitting, state.snapshot != nil else {
			return
		}
		if let choice = pendingChoice {
			pendingChoice = nil
			launchSelect(choice)
		} else if mayFollowVideos && (state.needsUnmerge || state.needsMerge && !state.hasDownloadsInFlight) {
			videosChangedAt = nil
			launchSync()
		}
	}

	func launch(_ operation: @escaping () async -> Void) {
		state.isWorking = true
		Task {
			await operation()
			finishWork()
			reconcile()
		}
	}

	func perform(_ work: @escaping @Sendable (Engine) throws -> EngineReport) async -> Result<EngineReport, InstallerError> {
		guard let engine else {
			return .failure(InstallerError("Native Aerials isn’t ready yet."))
		}
		let activity = ProcessInfo.processInfo.beginActivity(
			options: [.userInitiated, .suddenTerminationDisabled, .automaticTerminationDisabled],
			reason: "Updating wallpaper settings"
		)
		defer { ProcessInfo.processInfo.endActivity(activity) }
		do {
			let report = try await engine.run(work)
			if let snapshot = report.snapshot {
				apply(snapshot)
			} else {
				await reload()
			}
			return .success(report)
		} catch {
			await reload()
			return .failure(InstallerError(describing: error))
		}
	}

	private var mayFollowVideos: Bool {
		guard let changed = videosChangedAt, Date.now.timeIntervalSince(changed) >= Self.syncDelay else {
			return false
		}
		return failedSyncVideos != state.onDiskAssetIDs
	}

	private func finishWork() {
		state.isWorking = false
		let actions = idleActions
		idleActions = []
		actions.forEach { $0() }
	}

	private func loadFirstSnapshot() async {
		guard let engine, let first = try? await engine.run({ $0.snapshot() }) else {
			return
		}
		await thumbnails.update(Self.thumbnailSources(of: first))
		var transaction = Transaction()
		transaction.disablesAnimations = true
		withTransaction(transaction) {
			apply(first)
		}
	}

	func watchLoginItems() async {
		while !Task.isCancelled {
			try? await Task.sleep(for: .seconds(2))
			guard !NSApp.isActive, let engine, let known = state.snapshot?.agent, known != .notInstalled,
				let current = try? await engine.run({ $0.agentState() }), current != known
			else {
				continue
			}
			await reload()
		}
	}

	func reload() async {
		guard let engine, let fresh = try? await engine.run({ $0.snapshot() }) else {
			return
		}
		apply(fresh)
	}

	private func apply(_ snapshot: WallpaperSnapshot) {
		guard snapshot != state.snapshot else {
			return
		}
		if state.switchIntent == nil {
			state.animatesMerge = false
		}
		state.snapshot = snapshot
		removedByUser.subtract(snapshot.onDiskAssetIDs)
		updateDownloads { $0.settle(with: snapshot) }
		Task {
			await thumbnails.update(Self.thumbnailSources(of: snapshot))
		}
	}

	private func watchChanges() async {
		guard let engine else {
			return
		}
		for await change in engine.changes() {
			await reload()
			if change.contains(.thumbnails), let snapshot = state.snapshot {
				await thumbnails.update(Self.thumbnailSources(of: snapshot), reloadingAll: true)
			}
			if change.contains(.videos) {
				videosChangedAt = .now
				Task {
					try? await Task.sleep(for: .seconds(Self.syncDelay))
					reconcile()
				}
			}
			reconcile()
		}
	}

	private static func thumbnailSources(of snapshot: WallpaperSnapshot) -> [String: URL] {
		var sources: [String: URL] = [:]
		for variant in snapshot.sets.flatMap(\.variants) {
			sources[variant.assetID] = variant.thumbnail
		}
		return sources
	}
}
