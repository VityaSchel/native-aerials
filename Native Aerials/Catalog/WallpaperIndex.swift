import Foundation

nonisolated struct WallpaperIndex {
	static let aerialsProvider = "com.apple.wallpaper.choice.aerials"
	static let nullValue = "$null"
	private static let knownRootKeys: Set<String> = ["AllSpacesAndDisplays", "SystemDefault", "Displays", "Spaces"]
	private static let recentUseWindow: TimeInterval = 10 * 60
	static var defaultChoice: [String: Any] { ["Provider": "default", "Configuration": Data(), "Files": [Any]()] }

	var root: [String: Any]

	func data() throws -> Data {
		try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
	}

	var hasExpectedLayout: Bool {
		Set(root.keys).isSubset(of: Self.knownRootKeys) && !desktopPartsMostSpecificFirst().isEmpty
	}

	var currentDesktopAssetID: String? {
		if let all = root["AllSpacesAndDisplays"] as? [String: Any], let key = Self.desktopKey(of: all), let part = all[key] as? [String: Any] {
			return Self.assetID(ofPart: part)
		}
		let latest = desktopPartsMostSpecificFirst().max { Self.lastUse($0) < Self.lastUse($1) }
		return latest.flatMap(Self.assetID(ofPart:))
	}

	var choiceAssetIDs: Set<String> {
		Set(dictionaries().compactMap(Self.assetID(ofChoice:)))
	}

	func choiceAssetID(at path: [String]) -> String? {
		let node = path.reduce(Optional<Any>(root)) { node, key in
			if let dictionary = node as? [String: Any] {
				return dictionary[key]
			}
			return (node as? [Any]).flatMap { array in Int(key).flatMap { array.indices.contains($0) ? array[$0] : nil } }
		}
		return (node as? [String: Any]).flatMap(Self.assetID(ofChoice:))
	}

	func inUse(spaces: Set<String>?, includingRecent: Bool, now: Date = .now) -> WallpaperIndex {
		guard let spaces, let entries = root["Spaces"] as? [String: Any] else {
			return self
		}
		let recent = now.addingTimeInterval(-Self.recentUseWindow)
		var live = root
		live["Spaces"] = entries.filter { $0.key.isEmpty || spaces.contains($0.key) || includingRecent && Self.wasUsed($0.value, since: recent) }
		return WallpaperIndex(root: live)
	}

	private static func wasUsed(_ node: Any, since date: Date) -> Bool {
		if let dictionary = node as? [String: Any] {
			return (dictionary["LastUse"] as? Date).map { $0 > date } == true || dictionary.values.contains { wasUsed($0, since: date) }
		}
		return (node as? [Any])?.contains { wasUsed($0, since: date) } ?? false
	}

	func shufflesAerials(categoryIDs: Set<String> = []) -> Bool {
		dictionaries().contains { Self.shufflesAerials($0, categoryIDs: categoryIDs) }
	}

	private func dictionaries() -> [[String: Any]] {
		var found: [[String: Any]] = []
		_ = Self.mapDictionaries(in: root) { dictionary, _ in
			found.append(dictionary)
			return dictionary
		}
		return found
	}

	static func mapDictionaries(in node: Any, at path: [String] = [], _ transform: ([String: Any], [String]) -> [String: Any]) -> Any {
		switch node {
		case let dictionary as [String: Any]:
			var dictionary = transform(dictionary, path)
			for (key, child) in dictionary where key != "Configuration" || !(child is Data) {
				dictionary[key] = mapDictionaries(in: child, at: path + [key], transform)
			}
			return dictionary
		case let array as [Any]:
			return array.enumerated().map { mapDictionaries(in: $1, at: path + [String($0)], transform) }
		default:
			return node
		}
	}

	func showsEverywhere(_ choice: AerialChoice) -> Bool {
		let parts = desktopPartsMostSpecificFirst()
		return !parts.isEmpty && parts.allSatisfy { Self.matches($0["Content"] as? [String: Any], choice) }
	}

	private func desktopPartsMostSpecificFirst() -> [[String: Any]] {
		var parts: [(depth: Int, part: [String: Any])] = []
		_ = Self.mapDictionaries(in: root) { node, path in
			if Self.isSlot(path), let key = Self.desktopKey(of: node), let part = node[key] as? [String: Any] {
				parts.append((path.count, part))
			}
			return node
		}
		return parts.sorted { $0.depth > $1.depth }.map(\.part)
	}

	mutating func paint(_ choice: AerialChoice, at date: Date) -> Int {
		guard let configuration = Self.configuration(for: choice.assetID) else {
			return 0
		}
		let painter = Painter(choice: choice, configuration: configuration, date: date)
		var painted = 0
		root = Self.mapDictionaries(in: root) { node, path in
			guard Self.isSlot(path) else {
				return node
			}
			var node = node
			painted += painter.paint(&node)
			return node
		} as? [String: Any] ?? root
		return painted
	}

	private static func isSlot(_ path: [String]) -> Bool {
		switch path.count {
		case 1: path[0] == "AllSpacesAndDisplays" || path[0] == "SystemDefault"
		case 2: path[0] == "Displays"
		case 3: path[0] == "Spaces" && path[2] == "Default"
		case 4: path[0] == "Spaces" && path[2] == "Displays"
		default: false
		}
	}

	private static func lastUse(_ part: [String: Any]) -> Date {
		part["LastUse"] as? Date ?? .distantPast
	}

	fileprivate static func desktopKey(of node: [String: Any]) -> String? {
		switch node["Type"] as? String {
		case "linked": "Linked"
		case "individual", "desktop": "Desktop"
		default: nil
		}
	}

	static func configuration(for assetID: String) -> Data? {
		try? PropertyListSerialization.data(fromPropertyList: ["assetID": assetID], format: .binary, options: 0)
	}

	static func assetID(ofChoice choice: [String: Any]) -> String? {
		guard choice["Provider"] as? String == aerialsProvider,
			let configuration = choice["Configuration"] as? Data, !configuration.isEmpty,
			let inner = try? PropertyListSerialization.propertyList(from: configuration, format: nil) as? [String: Any]
		else {
			return nil
		}
		return inner["assetID"] as? String
	}

	private static func shufflesAerials(_ node: [String: Any], categoryIDs: Set<String>) -> Bool {
		if node["Provider"] as? String == aerialsProvider {
			guard let id = assetID(ofChoice: node) else {
				return true
			}
			return UUID(uuidString: id) == nil || categoryIDs.contains(id)
		}
		guard let choices = node["Choices"] as? [[String: Any]], choices.contains(where: { $0["Provider"] as? String == aerialsProvider }),
			let shuffle = node["Shuffle"]
		else {
			return false
		}
		return shuffle as? String != nullValue
	}

	private static func assetID(ofPart part: [String: Any]) -> String? {
		((part["Content"] as? [String: Any])?["Choices"] as? [[String: Any]])?.first.flatMap(assetID(ofChoice:))
	}

	fileprivate static func matches(_ content: [String: Any]?, _ choice: AerialChoice) -> Bool {
		guard let content, let choices = content["Choices"] as? [[String: Any]], choices.count == 1,
			assetID(ofChoice: choices[0]) == choice.assetID
		else {
			return false
		}
		if case .automatic = choice, let options = content["EncodedOptionValues"] as? Data, withoutVariant(options) != nil {
			return false
		}
		return true
	}

	fileprivate static func withoutVariant(_ options: Data) -> Data? {
		guard var decoded = try? PropertyListSerialization.propertyList(from: options, format: nil) as? [String: Any],
			var values = decoded["values"] as? [String: Any], values["aerialVariant"] != nil
		else {
			return nil
		}
		values["aerialVariant"] = nil
		decoded["values"] = values
		return try? PropertyListSerialization.data(fromPropertyList: decoded, format: .binary, options: 0)
	}
}

nonisolated extension WallpaperIndex {
	init(data: Data) throws {
		guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
			throw CocoaError(.propertyListReadCorrupt)
		}
		self.root = root
	}
}

private nonisolated struct Painter {
	let choice: AerialChoice
	let configuration: Data
	let date: Date

	func paint(_ node: inout [String: Any]) -> Int {
		guard let key = WallpaperIndex.desktopKey(of: node), var part = node[key] as? [String: Any] else {
			return 0
		}
		let content = part["Content"] as? [String: Any]
		guard !WallpaperIndex.matches(content, choice) else {
			return 0
		}
		part["Content"] = painted(content ?? [:])
		part["LastSet"] = date
		node[key] = part
		return 1
	}

	private func painted(_ content: [String: Any]) -> [String: Any] {
		var content = content
		content["Choices"] = [["Provider": WallpaperIndex.aerialsProvider, "Configuration": configuration, "Files": [Any]()]]
		content["Shuffle"] = WallpaperIndex.nullValue
		if case .automatic = choice, let options = content["EncodedOptionValues"] as? Data, let stripped = WallpaperIndex.withoutVariant(options) {
			content["EncodedOptionValues"] = stripped
		}
		return content
	}
}
