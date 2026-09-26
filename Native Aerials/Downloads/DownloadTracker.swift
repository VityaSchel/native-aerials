import Foundation

nonisolated struct DownloadEntry: Equatable, Sendable {
	enum Phase: Equatable, Sendable {
		case active
		case paused
		case completed
	}

	var assetID: String?
	var phase = Phase.active
	var percent = 0
	var lastEvent: Date

	var isInFlight: Bool { phase != .completed }
	var shownPercent: Int { phase == .completed ? 100 : percent }
}

nonisolated struct DownloadTracker: Equatable, Sendable {
	static let stallLimit: TimeInterval = 300

	private(set) var entries: [String: DownloadEntry] = [:]

	var inFlightIDs: Set<String> {
		Set(entries.filter { $0.value.isInFlight }.map { $0.value.assetID ?? $0.key })
	}

	var deadline: Date? {
		entries.values.map(\.lastEvent).min()?.addingTimeInterval(Self.stallLimit)
	}

	func entry(forAssetID assetID: String) -> DownloadEntry? {
		entries.values.filter { $0.assetID == assetID }.max { $0.shownPercent < $1.shownPercent }
	}

	func status(of variant: VariantSnapshot) -> TileStatus {
		guard variant.download != .onDisk else {
			return .ready
		}
		return entry(forAssetID: variant.assetID).map { .downloading(percent: $0.shownPercent) } ?? .missing
	}

	mutating func record(_ event: DownloadEvent, now: Date = .now) -> String? {
		switch event {
		case .update(let code, let update):
			return record(update, forCode: code, now: now)
		case .extensionRestarted:
			entries = entries.filter { !$0.value.isInFlight }
			return nil
		case .selectionChanged:
			return nil
		}
	}

	private mutating func record(_ update: DownloadUpdate, forCode code: String, now: Date) -> String? {
		let existing = entries[code]
		var entry = existing ?? DownloadEntry(assetID: ChoiceCode.known[code], lastEvent: now)
		entry.lastEvent = now
		switch update {
		case .requested:
			if entry.phase == .paused {
				entry.phase = .active
			}
		case .started(let assetID):
			entry.assetID = assetID
			entry.phase = .active
		case .progress(let percent):
			entry.phase = .active
			entry.percent = min(max(percent, 0), 100)
		case .paused(let percent):
			entry.phase = .paused
			entry.percent = min(max(percent, 0), 100)
		case .completed:
			entry.phase = .completed
		case .cancelling:
			entries[code] = nil
			return nil
		case .failed(let failure):
			entries[code] = nil
			return failure == DownloadUpdate.cancelledCode ? nil : existing?.assetID
		case .ended:
			entries[code] = existing?.phase == .completed ? entry : nil
			return nil
		}
		entries[code] = entry
		return nil
	}

	mutating func settle(with snapshot: WallpaperSnapshot) {
		let onDisk = snapshot.onDiskAssetIDs
		entries = entries.filter { _, entry in
			entry.isInFlight || !(entry.assetID.map(onDisk.contains) ?? false)
		}
	}

	mutating func expireStalled(now: Date = .now) -> Bool {
		let alive = entries.filter { now.timeIntervalSince($0.value.lastEvent) < Self.stallLimit }
		guard alive.count != entries.count else {
			return false
		}
		entries = alive
		return true
	}
}
