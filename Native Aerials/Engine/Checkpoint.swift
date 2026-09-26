import Foundation

nonisolated struct Checkpoint {
	private let catalog: Data?
	private let state: Data?
	private let hadCustomDirectory: Bool
	private let override: Any?
	private let forceLocal: Any?

	init(_ installer: Installer) {
		let locations = installer.locations
		catalog = try? Data(contentsOf: locations.catalogFile)
		state = try? Data(contentsOf: locations.stateFile)
		hadCustomDirectory = FileManager.default.fileExists(atPath: locations.customDirectory.path)
		override = installer.preferences.rawValue(forKey: AerialPreferences.overrideKey)
		forceLocal = installer.preferences.rawValue(forKey: AerialPreferences.forceLocalKey)
	}

	func restore(_ installer: Installer) {
		let locations = installer.locations
		let preferences = installer.preferences
		installer.log.note("rolling back to the state before this change")
		try? preferences.restore(override, forKey: AerialPreferences.overrideKey)
		try? preferences.restore(forceLocal, forKey: AerialPreferences.forceLocalKey)
		guard hadCustomDirectory else {
			try? FileManager.default.removeItem(at: locations.customDirectory)
			return
		}
		Self.put(catalog, at: locations.catalogFile)
		Self.put(state, at: locations.stateFile)
	}

	private static func put(_ data: Data?, at file: URL) {
		guard let data else {
			try? FileManager.default.removeItem(at: file)
			return
		}
		if (try? Data(contentsOf: file)) != data {
			try? data.write(to: file, options: .atomic)
		}
	}
}
