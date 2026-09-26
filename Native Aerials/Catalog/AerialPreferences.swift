import Foundation

nonisolated struct AerialPreferences {
	static let domain = "com.apple.wallpaper.aerial"
	static let overrideKey = "AerialManifestLocalPathOverride"
	static let forceLocalKey = "AerialManifestForceLocal"

	let dryRun: DryRun?

	func text(forKey key: String) -> String? {
		text(of: rawValue(forKey: key))
	}

	private func text(of value: Any?) -> String? {
		switch value {
		case nil:
			nil
		case let string as String:
			string.isEmpty ? nil : string
		case let number as NSNumber where JSONTree.isBoolean(number):
			number.boolValue ? "1" : "0"
		case let number as NSNumber:
			number.stringValue
		case let other?:
			"\(other)"
		}
	}

	var overridePath: String? { text(forKey: Self.overrideKey) }
	var forceLocal: String? { text(forKey: Self.forceLocalKey) }

	func set(_ value: String, forKey key: String) throws {
		try write(value as NSString, forKey: key, description: value)
	}

	func set(_ value: Bool, forKey key: String) throws {
		try write(value as NSNumber, forKey: key, description: value ? "true" : "false")
	}

	func removeValue(forKey key: String) throws {
		dryRun?.record("delete \(Self.domain) \(key)")
		if let dryRun {
			try updateFile(of: dryRun) { $0.removeValue(forKey: key) }
			return
		}
		CFPreferencesSetAppValue(key as CFString, nil, Self.domain as CFString)
		CFPreferencesAppSynchronize(Self.domain as CFString)
		guard rawValue(forKey: key) == nil else {
			throw InstallerError("could not remove \(key) from \(Self.domain)", summary: "Couldn’t remove the aerial wallpaper setting. Try again.")
		}
	}

	func restore(_ value: Any?, forKey key: String) throws {
		guard let value = value as? NSObject else {
			if rawValue(forKey: key) != nil {
				try removeValue(forKey: key)
			}
			return
		}
		guard (rawValue(forKey: key) as? NSObject)?.isEqual(value) != true else {
			return
		}
		try write(value, forKey: key, description: text(of: value) ?? "")
	}

	func rawValue(forKey key: String) -> Any? {
		if let dryRun {
			return (try? contents(of: dryRun))?[key]
		}
		CFPreferencesAppSynchronize(Self.domain as CFString)
		return CFPreferencesCopyAppValue(key as CFString, Self.domain as CFString)
	}

	private func write(_ value: NSObject, forKey key: String, description: String) throws {
		dryRun?.record("set \(Self.domain) \(key) \(description)")
		if let dryRun {
			try updateFile(of: dryRun) { $0[key] = value }
			return
		}
		CFPreferencesSetAppValue(key as CFString, value, Self.domain as CFString)
		CFPreferencesAppSynchronize(Self.domain as CFString)
		guard let stored = rawValue(forKey: key) as? NSObject, stored.isEqual(value) else {
			throw InstallerError("could not write \(key) to \(Self.domain)", summary: "Couldn’t save the aerial wallpaper setting. Try again.")
		}
	}

	private func contents(of dryRun: DryRun) throws -> [String: Any] {
		let file = dryRun.preferencesFile
		if !FileManager.default.fileExists(atPath: file.path) {
			try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
			let exported = CFPreferencesCopyMultiple(nil, Self.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
			try save(exported as? [String: Any] ?? [:], to: file)
		}
		let data = try Data(contentsOf: file)
		return try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
	}

	private func updateFile(of dryRun: DryRun, _ change: (inout [String: Any]) -> Void) throws {
		var contents = try contents(of: dryRun)
		change(&contents)
		try save(contents, to: dryRun.preferencesFile)
	}

	private func save(_ contents: [String: Any], to file: URL) throws {
		let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
		try data.write(to: file, options: .atomic)
	}
}
