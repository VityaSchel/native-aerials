import CryptoKit
import Foundation

nonisolated enum SystemInfo {
	private static let spacesDomain = "com.apple.spaces"
	private static let desktopSpaceType = 0

	private static let systemVersion: [String: String] = {
		let url = URL(filePath: "/System/Library/CoreServices/SystemVersion.plist")
		let data = (try? Data(contentsOf: url)) ?? Data()
		let contents = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] ?? [:]
		return contents.compactMapValues { $0 as? String }
	}()

	static let missingHook: String? = {
		let hooks = [AerialPreferences.overrideKey, AerialPreferences.forceLocalKey, "combineVariants", "solar"]
		guard let binary = try? Data(contentsOf: Locations.extensionBinary, options: .mappedIfSafe) else {
			return hooks.first
		}
		return hooks.first { binary.range(of: Data($0.utf8)) == nil }
	}()

	static var buildVersion: String {
		systemVersion["ProductBuildVersion"] ?? "unknown"
	}

	static var isRoot: Bool { getuid() == 0 }

	static let appVersion: String = {
		if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
			return version
		}
		let record = URL(filePath: executablePath).deletingLastPathComponent().appending(path: AgentHelper.recordName)
		return AgentRecord.load(from: record)?.appVersion ?? "0"
	}()

	static var executablePath: String {
		let path = Bundle.main.executablePath ?? CommandLine.arguments[0]
		return resolvedPath(path) ?? path
	}

	static var userTemporaryDirectory: URL {
		var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
		let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
		guard length > 1, length <= buffer.count else {
			return FileManager.default.temporaryDirectory
		}
		let path = String(decoding: buffer[..<(length - 1)].map { UInt8(bitPattern: $0) }, as: UTF8.self)
		return URL(filePath: path, directoryHint: .isDirectory)
	}

	static func resolvedPath(_ path: String) -> String? {
		guard let resolved = realpath(path, nil) else {
			return nil
		}
		defer { free(resolved) }
		return String(cString: resolved)
	}

	static func applicationFolders(home: URL) -> [String] {
		let home = resolvedPath(home.path) ?? home.path
		return home.hasPrefix("/Volumes/") ? ["/Applications"] : ["/Applications", "\(home)/Applications"]
	}

	static func isAllowedLocation(_ path: String, applicationFolders: [String]?) -> Bool {
		!isInTrash(path) && applicationFolders?.contains { path.hasPrefix("\($0)/") } != false
	}

	static func isInTrash(_ path: String) -> Bool {
		URL(filePath: path).standardizedFileURL.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
	}

	static func spaceIDs(desktopsOnly: Bool) -> Set<String>? {
		CFPreferencesAppSynchronize(spacesDomain as CFString)
		return CFPreferencesCopyAppValue("SpacesDisplayConfiguration" as CFString, spacesDomain as CFString).flatMap { spaceIDs(in: $0, desktopsOnly: desktopsOnly) }
	}

	static func spaceIDs(in configuration: Any, desktopsOnly: Bool) -> Set<String>? {
		var ids: Set<String> = []
		func collect(_ node: Any) {
			if let dictionary = node as? [String: Any] {
				if let id = dictionary["uuid"] as? String, !desktopsOnly || (dictionary["type"] as? Int ?? desktopSpaceType) == desktopSpaceType {
					ids.insert(id)
				}
				dictionary.values.forEach(collect)
			} else if let array = node as? [Any] {
				array.forEach(collect)
			}
		}
		collect(configuration)
		return ids.isEmpty ? nil : ids
	}

	static var automaticTimeZone: Bool? {
		let url = URL(filePath: "/Library/Preferences/com.apple.timezone.auto.plist")
		guard let data = try? Data(contentsOf: url),
			let contents = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
			let active = contents["Active"] as? NSNumber
		else {
			return nil
		}
		return active.boolValue
	}

	static func sha256(of url: URL) -> String {
		guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
			return "none"
		}
		return sha256(of: data)
	}

	static func sha256(of data: Data) -> String {
		SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
	}
}
