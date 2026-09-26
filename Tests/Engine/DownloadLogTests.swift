import Foundation
import Testing

nonisolated struct DownloadLogTests {
	static let gg = AerialSet.goldenGate
	static let tahoe = AerialSet.tahoe

	static func choice(_ code: String) -> String {
		"<ChoiceDescriptor provider=com.apple.wallpaper.choice.aerials, configuration=\(code)>"
	}

	static func code(_ video: AerialVideo) -> String {
		ChoiceCode.of(video.assetID)
	}

	@Test func replaysTranscript() {
		var parser = DownloadLogParser()
		var tracker = DownloadTracker()
		var events: [DownloadEvent] = []
		var flashes: [String] = []
		var peak = 0
		for (date, line) in LogTranscript.ndjsonLines {
			for event in parser.events(inNDJSONLine: line) {
				events.append(event)
				if let failed = tracker.record(event, now: date) {
					flashes.append(failed)
				}
				peak = max(peak, tracker.inFlightIDs.count)
			}
		}
		let day = Self.gg.day.assetID
		let codes = events.compactMap { event -> String? in
			guard case .update(let code, _) = event else {
				return nil
			}
			return code
		}
		#expect(events.first == .update(assetID: day, .requested))
		#expect(events.contains(.update(assetID: day, .started(assetID: day))) && events.contains(.update(assetID: day, .progress(0))))
		#expect(events.contains(.update(assetID: day, .cancelling)) && events.contains(.update(assetID: day, .failed(code: -999))) && events.contains(.update(assetID: day, .ended)))
		#expect(events.contains(.update(assetID: Self.tahoe.evening.assetID, .completed)))
		#expect(!codes.isEmpty && codes.allSatisfy { ChoiceCode.known[$0].flatMap(AerialSet.video(withAssetID:)) != nil })
		#expect(!events.contains { if case .update(_, .failed(let code)) = $0 { code != DownloadUpdate.cancelledCode } else { false } })
		#expect(events.filter { if case .selectionChanged = $0 { true } else { false } }.count == 2)
		#expect(tracker.inFlightIDs.isEmpty && peak >= 1)
		#expect(flashes.isEmpty)
	}

	@Test func parsesDownloadLines() {
		var lines = DownloadLogParser()
		let morning = Self.tahoe.morning
		let morningChoice = Self.choice(Self.code(morning))
		#expect(lines.events(in: "Downloading (37.5%): \(Self.choice("ABCDEF12"))") == [.update(configuration: "ABCDEF12", .progress(37))])
		#expect(lines.events(in: "User settings update intent requires download(s): [\(morningChoice), \(Self.choice(Self.code(Self.gg.day)))]") == [.update(assetID: morning.assetID, .requested), .update(assetID: Self.gg.day.assetID, .requested)])
		#expect(lines.events(in: "User settings update intent will cancel downloads for: [\(morningChoice)]") == [.update(assetID: morning.assetID, .cancelling)])
		#expect(lines.events(in: "Pause Download (12.0%): \(morningChoice))") == [.update(assetID: morning.assetID, .paused(12))])
		#expect(lines.events(in: "Resume Download (12.0%): \(morningChoice))") == [.update(assetID: morning.assetID, .progress(12))])
		#expect(lines.events(in: "Download already in progress for '\(morningChoice)', resumed the download") == [.update(assetID: morning.assetID, .requested)])
		#expect(lines.events(in: "Registering for cache delete") == [.extensionRestarted])
		#expect(lines.events(in: "Resume called on completed choice: \(morningChoice))").isEmpty)
		#expect(lines.events(in: "Completing download of: <private> successfully").isEmpty)
		let combinedCode = ChoiceCode.of(Self.tahoe.subcategoryID)
		_ = lines.events(in: "Begin asset download for '\(Self.choice(combinedCode))': '\(Self.tahoe.night.assetID)'")
		#expect(lines.events(in: "Completed downloading representative asset '\(Self.tahoe.night.assetID)") == [.update(configuration: combinedCode, .completed)])
		var fresh = DownloadLogParser()
		let failure = #"{"eventMessage":"Completing download of: assetID(\#(Self.tahoe.night.assetID)) failed with error: NSURLErrorDomain (-1009) <private>","processID":1}"#
		#expect(fresh.events(inNDJSONLine: Data(failure.utf8)) == [.update(assetID: Self.tahoe.night.assetID, .failed(code: -1009))])
		#expect(lines.events(inNDJSONLine: Data("Filtering the log data".utf8)).isEmpty)
	}

	@Test func parsesSelectionChanges() {
		var lines = DownloadLogParser()
		let day = Self.tahoe.day.assetID
		let night = Self.gg.night.assetID
		let prefix = AerialSelection.logPrefix
		#expect(lines.events(in: "\(prefix)<> -> <assetIDs: [\(day)]>") == [.selectionChanged(AerialSelection(ids: [day]))])
		#expect(lines.events(in: "\(prefix)<assetIDs: [\(day)]> -> <subcategoryIDs: [\(Self.tahoe.subcategoryID)], assetIDs: [\(day),\(night)]>") == [.selectionChanged(AerialSelection(ids: [Self.tahoe.subcategoryID, day, night]))])
		#expect(lines.events(in: "\(prefix)<assetIDs: [\(day)]> -> <>") == [.selectionChanged(AerialSelection())])
		#expect(lines.events(in: "\(prefix)<> -> <categoryIDs: [\(CatalogFixture.landscapeCategoryID)]>") == [.selectionChanged(AerialSelection(includesCategories: true))])
		#expect(lines.events(in: "\(prefix)<private>").isEmpty && lines.events(in: "\(prefix)<> -> <private>").isEmpty)
		#expect(AerialSelection(ids: [Self.tahoe.subcategoryID, Self.gg.day.assetID]).protectedAssetIDs == Set(Self.tahoe.assetIDs + [Self.tahoe.subcategoryID, Self.gg.day.assetID]))
		#expect(AerialSelection(includesCategories: true).protectedAssetIDs == AerialSet.allIDs)
		var tracker = DownloadTracker()
		_ = tracker.record(.update(assetID: Self.gg.day.assetID, .progress(10)))
		let before = tracker
		#expect(tracker.record(.selectionChanged(AerialSelection(ids: [Self.gg.day.assetID]))) == nil && tracker == before)
	}
}
