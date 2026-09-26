import Foundation
import Testing

nonisolated struct DownloadTrackerTests {
	static let gg = AerialSet.goldenGate
	static let tahoe = AerialSet.tahoe
	static let start = Date(timeIntervalSince1970: 0)

	static func variant(_ video: AerialVideo, onDisk: Bool = false) -> VariantSnapshot {
		VariantSnapshot(assetID: video.assetID, caption: video.caption, name: video.name, thumbnail: nil, download: onDisk ? .onDisk : .missing, isSelected: false)
	}

	static var downloading: DownloadTracker {
		var tracker = DownloadTracker()
		_ = tracker.record(.update(assetID: gg.day.assetID, .requested), now: start)
		_ = tracker.record(.update(assetID: gg.day.assetID, .progress(10)), now: start.addingTimeInterval(30))
		return tracker
	}

	@Test func showsProgressUntilTheVideoLands() throws {
		let day = Self.variant(Self.gg.day)
		var tracker = DownloadTracker()
		#expect(tracker.status(of: day) == .missing && tracker.deadline == nil)
		_ = tracker.record(.update(assetID: Self.gg.day.assetID, .requested), now: Self.start)
		#expect(tracker.status(of: day) == .downloading(percent: 0) && tracker.inFlightIDs == [Self.gg.day.assetID])
		#expect(Self.downloading.status(of: day) == .downloading(percent: 10))
		var done = Self.downloading
		_ = done.record(.update(assetID: Self.gg.day.assetID, .completed))
		_ = done.record(.update(assetID: Self.gg.day.assetID, .ended))
		#expect(done.status(of: day) == .downloading(percent: 100) && done.inFlightIDs.isEmpty)
		done.settle(with: try Sandbox(videos: [Self.gg.day]).snapshot())
		#expect(done.entries.isEmpty && done.status(of: Self.variant(Self.gg.day, onDisk: true)) == .ready)
	}

	static func after(_ update: DownloadUpdate, of video: AerialVideo = gg.day) -> (tracker: DownloadTracker, failed: String?) {
		var tracker = downloading
		let failed = tracker.record(.update(assetID: video.assetID, update))
		return (tracker, failed)
	}

	@Test func dropsDownloadsThatStopOrFail() {
		let day = Self.variant(Self.gg.day)
		var stalled = Self.downloading
		let early = stalled.expireStalled(now: Self.start.addingTimeInterval(30 + DownloadTracker.stallLimit - 1))
		let late = stalled.expireStalled(now: Self.start.addingTimeInterval(30 + DownloadTracker.stallLimit))
		#expect(!early && late && stalled.status(of: day) == .missing)
		let cancelled = Self.after(.cancelling)
		#expect(cancelled.failed == nil && cancelled.tracker.status(of: day) == .missing && cancelled.tracker.inFlightIDs.isEmpty)
		let failed = Self.after(.failed(code: -1009))
		#expect(failed.failed == Self.gg.day.assetID && failed.tracker.status(of: day) == .missing)
		let cancelledLate = Self.after(.failed(code: DownloadUpdate.cancelledCode))
		#expect(cancelledLate.failed == nil && cancelledLate.tracker.status(of: day) == .missing)
		let abandoned = Self.after(.ended)
		#expect(abandoned.failed == nil && abandoned.tracker.status(of: day) == .missing)
		let paused = Self.after(.paused(33))
		#expect(paused.tracker.status(of: day) == .downloading(percent: 33) && paused.tracker.inFlightIDs == [Self.gg.day.assetID])
		var restarted = Self.after(.completed, of: Self.tahoe.day).tracker
		_ = restarted.record(.extensionRestarted)
		#expect(restarted.status(of: day) == .missing && restarted.status(of: Self.variant(Self.tahoe.day)) == .downloading(percent: 100))
	}

	@Test func mapsCombinedAndUnknownDownloads() {
		let combined = ChoiceCode.of(Self.tahoe.subcategoryID)
		var merged = DownloadTracker()
		_ = merged.record(.update(configuration: combined, .requested))
		_ = merged.record(.update(configuration: combined, .started(assetID: Self.tahoe.night.assetID)))
		_ = merged.record(.update(configuration: combined, .progress(64)))
		#expect(merged.status(of: Self.variant(Self.tahoe.night)) == .downloading(percent: 64))
		var other = DownloadTracker()
		_ = other.record(.update(configuration: "ABCDEF12", .progress(5)))
		#expect(other.inFlightIDs == ["ABCDEF12"])
	}

	@Test func sharesInFlightDownloadsThroughAMarker() throws {
		let sandbox = try Sandbox()
		let marker = sandbox.paths.downloadActivityFile
		DownloadActivity.record([Self.gg.day.assetID, "ABCDEF12"], to: marker)
		#expect(DownloadActivity.inFlightIDs(at: marker) == [Self.gg.day.assetID, "ABCDEF12"])
		#expect(DownloadActivity.inFlightIDs(at: marker, now: .now.addingTimeInterval(DownloadActivity.freshness + 1)).isEmpty)
		DownloadActivity.record([], to: marker)
		#expect(!sandbox.exists(marker) && DownloadActivity.inFlightIDs(at: marker).isEmpty)
	}
}
