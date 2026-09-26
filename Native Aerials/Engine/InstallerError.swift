import Foundation

nonisolated struct InstallerError: LocalizedError, Sendable, Equatable {
	static let unexpectedCatalogSummary = "Apple’s aerial catalog changed in a way this version doesn’t expect. Check for a newer Native Aerials."
	static let selectionSummary = "Couldn’t set the wallpaper."
	static let saveSummary = "Couldn’t save the wallpaper settings. Try again."

	let message: String
	let summary: String
	let missingAssetIDs: [String]

	init(_ message: String, summary: String? = nil, missingAssetIDs: [String] = []) {
		self.message = message
		self.summary = summary ?? message.sentenceCased
		self.missingAssetIDs = missingAssetIDs
	}

	init(describing error: any Error) {
		self = error as? InstallerError ?? InstallerError(error.localizedDescription)
	}

	static func unexpectedCatalog(_ url: URL, _ detail: String = "the entries of the sets it combines are not where this version expects them") -> InstallerError {
		InstallerError("unexpected aerial catalog (\(url.path)): \(detail). Check for a newer Native Aerials.", summary: unexpectedCatalogSummary)
	}

	var errorDescription: String? { message }
}

nonisolated extension String {
	var sentenceCased: String {
		prefix(1).uppercased() + dropFirst()
	}
}
