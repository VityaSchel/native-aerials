import Foundation

nonisolated enum DownloadActivity {
	static let refreshInterval: TimeInterval = 60
	static let freshness = DownloadTracker.stallLimit + refreshInterval

	static func record(_ ids: Set<String>, to file: URL) {
		guard !ids.isEmpty else {
			try? FileManager.default.removeItem(at: file)
			return
		}
		try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
		try? Data(ids.sorted().map { $0 + "\n" }.joined().utf8).write(to: file, options: .atomic)
	}

	static func inFlightIDs(at file: URL, now: Date = .now) -> Set<String> {
		guard let modified = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date,
			now.timeIntervalSince(modified) < freshness,
			let text = try? String(contentsOf: file, encoding: .utf8)
		else {
			return []
		}
		return Set(text.split(whereSeparator: \.isNewline).map(String.init))
	}
}
