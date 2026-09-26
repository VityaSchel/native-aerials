import Foundation

nonisolated protocol JSONFile: Codable {}

nonisolated extension JSONFile {
	static func load(from url: URL) -> Self? {
		(try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
	}

	func save(to url: URL) throws {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		try encoder.encode(self).write(to: url, options: .atomic)
	}
}

nonisolated struct InstallState: JSONFile, Equatable {
	var appVersion: String
	var osBuild: String
	var source: String
	var sourceDigest: String
	var bundledDigest: String
	var catalogDigest: String
	var mergedSets: [String]

	static func current(source: URL, bundled: URL, catalog: URL, sets: [AerialSet]) -> InstallState {
		InstallState(
			appVersion: SystemInfo.appVersion,
			osBuild: SystemInfo.buildVersion,
			source: source.path,
			sourceDigest: SystemInfo.sha256(of: source),
			bundledDigest: SystemInfo.sha256(of: bundled),
			catalogDigest: SystemInfo.sha256(of: catalog),
			mergedSets: sets.map(\.slug)
		)
	}
}
