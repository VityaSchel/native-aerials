import SwiftUI

extension AppModel {
	static let feedRestartDelay: TimeInterval = 5
	static let feedRestartLimit: TimeInterval = 300

	func watchDownloads() {
		guard downloadFeed == nil, !isQuitting, let engine else {
			return
		}
		downloadFeed = Task {
			var delay = Self.feedRestartDelay
			while !Task.isCancelled {
				let started = Date.now
				for await event in engine.downloadEvents() {
					receive(event)
				}
				if Date.now.timeIntervalSince(started) > Self.feedRestartLimit {
					delay = Self.feedRestartDelay
				}
				try? await Task.sleep(for: .seconds(delay))
				delay = min(delay * 2, Self.feedRestartLimit)
			}
		}
	}

	func stopWatchingDownloads() {
		downloadFeed?.cancel()
		downloadFeed = nil
		stallTimer?.cancel()
		stallTimer = nil
		stallDeadline = nil
		publishDownloads([])
	}

	func receive(_ event: DownloadEvent) {
		if case .selectionChanged(let selection) = event {
			if selection != state.liveSelection {
				state.liveSelection = selection
			}
			return
		}
		var failed: String?
		updateDownloads { failed = $0.record(event) }
		if let failed, let video = AerialSet.video(withAssetID: failed) {
			state.flash([failed])
			AccessibilityNotification.Announcement("Couldn’t download \(video.name)").post()
		}
		reconcile()
	}

	func updateDownloads(_ change: (inout DownloadTracker) -> Void) {
		var downloads = state.downloads
		change(&downloads)
		if downloads != state.downloads {
			state.downloads = downloads
		}
		armStallTimer()
		publishDownloads(downloads.inFlightIDs)
	}

	private func publishDownloads(_ assetIDs: Set<String>) {
		let isDue = publishedAt.map { Date.now.timeIntervalSince($0) >= DownloadActivity.refreshInterval } ?? true
		guard assetIDs != publishedDownloads || !assetIDs.isEmpty && isDue else {
			return
		}
		publishedDownloads = assetIDs
		publishedAt = .now
		engine?.recordDownloads(assetIDs)
	}

	private func armStallTimer() {
		guard let deadline = state.downloads.deadline else {
			stallTimer?.cancel()
			stallTimer = nil
			stallDeadline = nil
			return
		}
		guard stallDeadline != deadline else {
			return
		}
		stallTimer?.cancel()
		stallDeadline = deadline
		stallTimer = Task {
			try? await Task.sleep(for: .seconds(max(deadline.timeIntervalSinceNow, 0)))
			guard !Task.isCancelled else {
				return
			}
			stallTimer = nil
			stallDeadline = nil
			updateDownloads { _ = $0.expireStalled() }
			reconcile()
		}
	}
}
