import AppKit
import Foundation
import Testing

final class WindowHarness {
	let sandbox: Sandbox
	let model = AppModel()
	private var started: Task<Void, Never>?

	var state: PanelState { model.state }
	var selected: String? { state.snapshot?.selectedAssetID }
	var marker: Set<String> { DownloadActivity.inFlightIDs(at: sandbox.paths.downloadActivityFile) }
	var removals: [String] { sandbox.rawActions.filter { $0.hasPrefix("remove-download ") } }

	var ringed: [String] {
		state.rows.flatMap { row in row.isMerged ? (row.isSelected ? [row.name] : []) : row.tiles.filter(\.isSelected).map(\.name) }
	}

	var installedFootnote: String? {
		var state = state
		state.snapshot?.needsMoveToApplications = false
		state.snapshot?.automaticTimeZone = nil
		state.snapshot?.dryRunDirectory = nil
		let text = state.footnote?.text
		return text == Installer.moveNotice ? nil : text
	}

	init(_ sandbox: Sandbox) {
		self.sandbox = sandbox
	}

	func start(watchingDownloads: Bool = false) async throws {
		_ = NSApplication.shared
		if !watchingDownloads {
			model.downloadFeed = Task {}
		}
		let engine = try sandbox.engine()
		started = Task { await model.start(using: { engine }) }
		try #require(await until { self.state.isReady && self.state.snapshot != nil })
	}

	func stop() {
		model.stopWatchingDownloads()
		started?.cancel()
	}

	func until(_ seconds: TimeInterval = 20, _ condition: () -> Bool) async -> Bool {
		await eventually(within: seconds, condition)
	}

	func settled(_ condition: () -> Bool) async -> Bool {
		await until { self.state.isReady && !self.state.isWorking && condition() }
	}

	func row(_ set: AerialSet) -> SetRow? {
		state.rows.first { $0.id == set.subcategoryID }
	}

	func tile(_ video: AerialVideo) -> TileItem? {
		state.rows.flatMap(\.tiles).first { $0.id == video.assetID }
	}

	func status(_ video: AerialVideo) -> TileStatus? {
		tile(video)?.status
	}

	func flashes(_ video: AerialVideo) -> Int {
		state.flashes[video.assetID] ?? 0
	}

	func send(_ video: AerialVideo, _ updates: DownloadUpdate...) {
		for update in updates {
			model.receive(.update(assetID: video.assetID, update))
		}
	}

	func hint(_ video: AerialVideo) -> [String] {
		["open wallpaper", "hint Download “\(video.name)” first"]
	}
}
