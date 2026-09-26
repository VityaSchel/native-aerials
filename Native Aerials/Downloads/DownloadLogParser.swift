import Foundation

nonisolated enum DownloadUpdate: Equatable, Sendable {
	case requested
	case started(assetID: String)
	case progress(Int)
	case paused(Int)
	case cancelling
	case failed(code: Int)
	case completed
	case ended

	static let cancelledCode = -999
}

nonisolated enum DownloadEvent: Equatable, Sendable {
	case update(configuration: String, DownloadUpdate)
	case extensionRestarted
	case selectionChanged(AerialSelection)
}

nonisolated enum ChoiceCode {
	static let known = Dictionary(AerialSet.allIDs.map { (of($0), $0) }) { first, _ in first }

	static func of(_ assetID: String) -> String {
		let configuration = WallpaperIndex.configuration(for: assetID) ?? Data(assetID.utf8)
		return SystemInfo.sha256(of: configuration).suffix(8).uppercased()
	}
}

nonisolated struct DownloadLogParser {
	private var learnedCodes: [String: String] = [:]
	private let configuration = #/provider=com\.apple\.wallpaper\.choice\.aerials, configuration=([0-9A-F]{8})>/#
	private let assetID = #/[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/#
	private let percent = #/^[A-Za-z ]+\((\d+)(?:\.\d+)?%\)/#
	private let errorCode = #/ \((-?\d+)\)/#

	mutating func events(in message: String) -> [DownloadEvent] {
		if message.hasPrefix("Registering for cache delete") {
			return [.extensionRestarted]
		}
		if message.hasPrefix(AerialSelection.logPrefix) {
			return AerialSelection(logMessage: message).map { [.selectionChanged($0)] } ?? []
		}
		if message.hasPrefix("User settings update intent requires download(s)") {
			return codes(in: message).map { .update(configuration: $0, .requested) }
		}
		if message.hasPrefix("User settings update intent will cancel downloads for") {
			return codes(in: message).map { .update(configuration: $0, .cancelling) }
		}
		if message.hasPrefix("Begin asset download for "), let code = codes(in: message).first, let id = message.firstMatch(of: assetID).map({ String($0.output) }) {
			learnedCodes[id] = code
			return [.update(configuration: code, .started(assetID: id))]
		}
		if message.hasPrefix("Completing download of: assetID(") || message.hasPrefix("Error downloading representative asset ") {
			guard let code = assetCode(in: message), let failure = message.firstMatch(of: errorCode).flatMap({ Int($0.output.1) }) else {
				return []
			}
			return [.update(configuration: code, .failed(code: failure))]
		}
		if message.hasPrefix("Completed downloading representative asset "), let code = assetCode(in: message) {
			return [.update(configuration: code, .completed)]
		}
		guard let code = codes(in: message).first, let update = choiceUpdate(in: message) else {
			return []
		}
		return [.update(configuration: code, update)]
	}

	mutating func events(inNDJSONLine line: Data) -> [DownloadEvent] {
		guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
			let message = object["eventMessage"] as? String
		else {
			return []
		}
		return events(in: message)
	}

	private func choiceUpdate(in message: String) -> DownloadUpdate? {
		if message.hasPrefix("Downloading (") || message.hasPrefix("Resume Download (") {
			return progress(in: message).map(DownloadUpdate.progress)
		}
		if message.hasPrefix("Pause Download (") {
			return progress(in: message).map(DownloadUpdate.paused)
		}
		if message.hasPrefix("Resume called on non-tracked choice") || message.hasPrefix("Download already in progress for ") {
			return .requested
		}
		if message.hasPrefix("Cancel Download: ") {
			return .cancelling
		}
		if message.hasPrefix("Complete Download: ") {
			return .ended
		}
		return nil
	}

	private func codes(in message: String) -> [String] {
		message.matches(of: configuration).map { String($0.output.1) }
	}

	private func assetCode(in message: String) -> String? {
		message.firstMatch(of: assetID).map { match in
			let id = String(match.output)
			return learnedCodes[id] ?? ChoiceCode.of(id)
		}
	}

	private func progress(in message: String) -> Int? {
		message.firstMatch(of: percent).flatMap { Int($0.output.1) }
	}
}
