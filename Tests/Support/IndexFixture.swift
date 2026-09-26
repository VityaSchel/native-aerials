import Foundation

nonisolated enum IndexFixture {
	enum Layout {
		case linked
		case idle
	}

	struct Space {
		var id: String
		var assetID: String?
		var lastUse: Date
	}

	struct Desktops: Equatable, CustomStringConvertible {
		let count: Int
		let assetIDs: Set<String>

		init(_ count: Int, _ assetIDs: Set<String>) {
			self.count = count
			self.assetIDs = assetIDs
		}

		var description: String { "\(count) \(assetIDs.sorted())" }
	}

	static let none = "none"
	static let liveSpace = "LIVE-SPACE"
	static let otherSpace = "OTHER-SPACE"
	static let display = "DISPLAY-1"
	static let lastUse = Date(timeIntervalSince1970: 1_780_000_000)
	static let otherLastUse = lastUse.addingTimeInterval(-5 * 3600)

	static var standardSpaces: [Space] {
		let tahoe = AerialSet.tahoe
		return [
			Space(id: liveSpace, assetID: tahoe.day.assetID, lastUse: lastUse),
			Space(id: otherSpace, assetID: tahoe.evening.assetID, lastUse: otherLastUse),
		] + [nil, nil, tahoe.day.assetID, tahoe.day.assetID].enumerated().map { offset, assetID in
			Space(id: "DEAD-\(offset + 1)", assetID: assetID, lastUse: lastUse.addingTimeInterval(-Double(offset + 6) * 3600))
		}
	}

	static var desktopCount: Int { desktops(of: standard()).count }
	static var liveCount: Int { desktops(of: standard()) { !isDead($0, live: [liveSpace]) }.count }
	static var deadCount: Int { desktopCount - liveCount }

	static func standard(
		system: String? = AerialSet.tahoe.day.assetID,
		spaces: [Space] = standardSpaces,
		layout: Layout = .linked,
		variantOption: Bool = false
	) -> [String: Any] {
		let node = { (assetID: String?, lastUse: Date) in
			Self.node(part(assetID, lastUse: lastUse, variantOption: variantOption), layout: layout)
		}
		let displayNode = node(system, lastUse)
		return [
			"AllSpacesAndDisplays": layout == .idle ? ["Type": "idle", "Idle": idlePart] : WallpaperIndex.nullValue,
			"SystemDefault": displayNode,
			"Displays": [display: displayNode],
			"Spaces": Dictionary(uniqueKeysWithValues: spaces.map { space in
				(space.id, ["Default": node(space.assetID, space.lastUse), "Displays": [display: node(space.assetID, space.lastUse)]])
			}),
		]
	}

	static var combined: [String: Any] {
		standard(system: AerialSet.goldenGate.subcategoryID, spaces: standardSpaces.map { space in
			Space(id: space.id, assetID: space.id == otherSpace ? AerialSet.tahoe.subcategoryID : space.assetID, lastUse: space.lastUse)
		})
	}

	static func everywhere(_ assetID: String?) -> [String: Any] {
		standard(system: assetID, spaces: standardSpaces.map { Space(id: $0.id, assetID: assetID, lastUse: $0.lastUse) })
	}

	static func choice(_ assetID: String?) -> [String: Any] {
		guard let assetID, let configuration = WallpaperIndex.configuration(for: assetID) else {
			return WallpaperIndex.defaultChoice
		}
		return ["Provider": WallpaperIndex.aerialsProvider, "Configuration": configuration, "Files": [Any]()]
	}

	static let photo: [String: Any] = [
		"Provider": "com.apple.wallpaper.choice.image",
		"Configuration": plist(["type": "imageFile", "url": ["relative": "file:///System/Library/Desktop%20Pictures/Example.heic"]]),
		"Files": [Any](),
	]

	static func plist(_ value: Any) -> Data {
		(try? PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)) ?? Data()
	}

	private static func part(_ assetID: String?, lastUse: Date, variantOption: Bool) -> [String: Any] {
		var values: [String: Any] = ["placement": ["picker": ["_0": ["id": "Crop"]]]]
		if variantOption {
			values["aerialVariant"] = ["picker": ["_0": ["id": "light"]]]
		}
		return [
			"Content": ["Choices": [choice(assetID)], "EncodedOptionValues": plist(["values": values]), "Shuffle": WallpaperIndex.nullValue],
			"LastSet": lastUse.addingTimeInterval(-86400),
			"LastUse": lastUse,
		]
	}

	private static var idlePart: [String: Any] {
		["Content": ["Choices": [photo], "Shuffle": WallpaperIndex.nullValue], "LastSet": lastUse, "LastUse": lastUse]
	}

	private static func node(_ part: [String: Any], layout: Layout) -> [String: Any] {
		switch layout {
		case .linked: ["Type": "linked", "Linked": part]
		case .idle: ["Type": "individual", "Desktop": part, "Idle": idlePart]
		}
	}

	static func nodes(of root: [String: Any]) -> [(path: [String], node: Any?)] {
		var nodes: [(path: [String], node: Any?)] = [(["AllSpacesAndDisplays"], root["AllSpacesAndDisplays"]), (["SystemDefault"], root["SystemDefault"])]
		for (key, node) in (root["Displays"] as? [String: Any] ?? [:]).sorted(by: { $0.key < $1.key }) {
			nodes.append((["Displays", key], node))
		}
		for (key, space) in (root["Spaces"] as? [String: Any] ?? [:]).sorted(by: { $0.key < $1.key }) {
			let space = space as? [String: Any] ?? [:]
			nodes.append((["Spaces", key, "Default"], space["Default"]))
			for (display, node) in (space["Displays"] as? [String: Any] ?? [:]).sorted(by: { $0.key < $1.key }) {
				nodes.append((["Spaces", key, "Displays", display], node))
			}
		}
		return nodes
	}

	static func desktopParts(of root: [String: Any]) -> [(path: [String], part: [String: Any])] {
		nodes(of: root).compactMap { path, node in
			guard let node = node as? [String: Any], let key = desktopKey(node["Type"]), let part = node[key] as? [String: Any] else {
				return nil
			}
			return (path + [key], part)
		}
	}

	static func assetID(ofPart part: [String: Any]) -> String? {
		guard let choices = (part["Content"] as? [String: Any])?["Choices"] as? [[String: Any]], choices.count == 1 else {
			return nil
		}
		return WallpaperIndex.assetID(ofChoice: choices[0])
	}

	static func isDead(_ path: [String], live: Set<String>) -> Bool {
		path.count > 1 && path[0] == "Spaces" && !path[1].isEmpty && !live.contains(path[1])
	}

	static func desktops(of root: [String: Any], where include: ([String]) -> Bool = { _ in true }) -> Desktops {
		let parts = desktopParts(of: root).filter { include($0.path) }
		return Desktops(parts.count, Set(parts.map { assetID(ofPart: $0.part) ?? none }))
	}

	static func repainting(_ root: [String: Any], where include: ([String]) -> Bool, with choice: [String: Any], lastUse: Date? = nil) -> [String: Any] {
		desktopParts(of: root).filter { include($0.path) }.reduce(root) { root, part in
			updating(root, at: part.path) { part in
				var content = part["Content"] as? [String: Any] ?? [:]
				content["Choices"] = [choice]
				part["Content"] = content
				if let lastUse {
					part["LastUse"] = lastUse
				}
			}
		}
	}

	static func replacingChoices(_ root: [String: Any], of assetID: String, with replacement: String) -> [String: Any] {
		WallpaperIndex.mapDictionaries(in: root) { node, _ in
			guard WallpaperIndex.assetID(ofChoice: node) == assetID else {
				return node
			}
			var node = node
			node["Configuration"] = WallpaperIndex.configuration(for: replacement)
			return node
		} as? [String: Any] ?? root
	}

	static func renamingSpace(_ root: [String: Any], _ id: String, to newID: String) -> [String: Any] {
		var root = root
		var spaces = root["Spaces"] as? [String: Any] ?? [:]
		spaces[newID] = spaces.removeValue(forKey: id)
		root["Spaces"] = spaces
		return root
	}

	static func updating(_ root: [String: Any], at path: [String], _ change: (inout [String: Any]) -> Void) -> [String: Any] {
		var node = root
		guard let key = path.first else {
			change(&node)
			return node
		}
		if let child = node[key] as? [String: Any] {
			node[key] = updating(child, at: Array(path.dropFirst()), change)
		}
		return node
	}

	static func skeleton(of root: [String: Any]) -> [String] {
		nodes(of: root).map { path, node in
			guard let node = node as? [String: Any] else {
				return "\(path) \(node.map { "\($0)" } ?? "nil")"
			}
			let idle = node["Idle"].map { " Idle=\(JSONTree.text(normalized($0)))" } ?? ""
			return "\(path) Type=\(node["Type"] ?? "-") keys=\(node.keys.sorted())\(idle)"
		}
	}

	static func variantCount(of root: [String: Any]) -> Int {
		desktopParts(of: root).filter { _, part in
			guard let options = (part["Content"] as? [String: Any])?["EncodedOptionValues"] as? Data,
				let decoded = try? PropertyListSerialization.propertyList(from: options, format: nil) as? [String: Any]
			else {
				return false
			}
			return (decoded["values"] as? [String: Any])?["aerialVariant"] != nil
		}.count
	}

	private static func desktopKey(_ type: Any?) -> String? {
		switch type as? String {
		case "linked": "Linked"
		case "individual", "desktop": "Desktop"
		default: nil
		}
	}

	private static func normalized(_ value: Any) -> Any {
		switch value {
		case let dictionary as [String: Any]: dictionary.mapValues(normalized)
		case let array as [Any]: array.map(normalized)
		case let data as Data: (try? PropertyListSerialization.propertyList(from: data, format: nil)).map { ["plist": normalized($0)] } ?? data.base64EncodedString()
		case is Date: "DATE"
		default: value
		}
	}
}
