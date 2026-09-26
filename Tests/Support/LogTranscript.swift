import Foundation

nonisolated enum LogTranscript {
	static let start = Date(timeIntervalSince1970: 1_790_000_000)

	static var entries: [(offset: TimeInterval, category: String, message: String)] {
		let gg = AerialSet.goldenGate
		let tahoe = AerialSet.tahoe
		let choice = { (video: AerialVideo) in "<ChoiceDescriptor provider=com.apple.wallpaper.choice.aerials, configuration=\(ChoiceCode.of(video.assetID))>" }
		return [
			(0.0, "coordinator", "User settings update intent requires download(s): [\(choice(gg.day))]"),
			(0.2, "aerial-assets", "Begin asset download for '\(choice(gg.day))': '\(gg.day.assetID)'"),
			(0.4, "download", "Downloading (0%): \(choice(gg.day))"),
			(3.0, "download", "Downloading (12%): \(choice(gg.day))"),
			(4.0, "coordinator", "User settings update intent will cancel downloads for: [\(choice(gg.day))]"),
			(4.0, "coordinator", "User settings update intent requires download(s): [\(choice(tahoe.evening))]"),
			(4.1, "download", "Cancel Download: \(choice(gg.day))"),
			(4.2, "aerial-assets", "Completing download of: assetID(\(gg.day.assetID)) failed with error: NSURLErrorDomain (-999) <private>"),
			(4.3, "download", "Complete Download: \(choice(gg.day))"),
			(4.4, "aerial-assets", "Begin asset download for '\(choice(tahoe.evening))': '\(tahoe.evening.assetID)'"),
			(4.5, "download", "Downloading (0%): \(choice(tahoe.evening))"),
			(9.0, "coordinator", "User settings update intent requires download(s): [\(choice(gg.night))]"),
			(9.2, "download", "Downloading (0%): \(choice(gg.night))"),
			(10.0, "coordinator", "User settings update intent will cancel downloads for: [\(choice(gg.night))]"),
			(10.1, "download", "Cancel Download: \(choice(gg.night))"),
			(12.0, "download", "Downloading (48%): \(choice(tahoe.evening))"),
			(20.0, "aerial-assets", "Completed downloading representative asset '\(tahoe.evening.assetID)"),
			(20.1, "download", "Complete Download: \(choice(tahoe.evening))"),
			(21.0, "aerial-assets", "Selected aerial ids did change: <assetIDs: [\(gg.day.assetID)]> -> <assetIDs: [\(tahoe.evening.assetID)]>"),
			(22.0, "aerial-assets", "Selected aerial ids did change: <> -> <subcategoryIDs: [\(tahoe.subcategoryID)], assetIDs: [\(tahoe.evening.assetID)]>"),
		]
	}

	static var ndjsonLines: [(date: Date, line: Data)] {
		entries.map { offset, category, message in
			let object: [String: Any] = ["eventMessage": message, "subsystem": "com.apple.wallpaper", "category": category, "processID": 1]
			return (start.addingTimeInterval(offset), (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
		}
	}
}
