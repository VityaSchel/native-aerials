import Foundation

nonisolated enum PathComponent: Hashable, Comparable {
	case index(Int)
	case key(String)

	var text: String {
		switch self {
		case .index(let index): String(index)
		case .key(let key): key
		}
	}
}

nonisolated struct CatalogChange: CustomStringConvertible {
	let isAddition: Bool
	let path: [PathComponent]
	let value: Any

	var description: String {
		"\(isAddition ? "+" : "-") \(path.map(\.text).joined(separator: ".")) = \(JSONTree.text(value))"
	}
}

nonisolated enum CatalogDelta {
	static func lines(from source: [String: Any], to built: [String: Any]) -> [CatalogChange] {
		let before = leaves(of: source)
		let after = leaves(of: built)
		let added = after
			.filter { path, value in before[path].map { !JSONTree.equal($0, value) } ?? true }
			.map { CatalogChange(isAddition: true, path: $0.key, value: $0.value) }
		let removed = before
			.filter { after[$0.key] == nil }
			.map { CatalogChange(isAddition: false, path: $0.key, value: $0.value) }
		return added.sorted { $0.path.lexicographicallyPrecedes($1.path) }
			+ removed.sorted { $0.path.lexicographicallyPrecedes($1.path) }
	}

	static func isExpected(_ change: CatalogChange, in built: AerialCatalog, sets: [AerialSet]) -> Bool {
		let path = change.path
		guard let first = path.first, let last = path.last else {
			return false
		}
		if change.isAddition, first == .key("categories"), last == .key("combineVariants") {
			let parent = value(at: Array(path.dropLast()), in: built.root) as? [String: Any]
			return (parent?["id"] as? String).map(Set(sets.map(\.subcategoryID)).contains) ?? false
		}
		guard first == .key("assets"), path.count > 1, case .index(let index) = path[1], isShot(at: index, in: built, of: sets) else {
			return false
		}
		if change.isAddition {
			let tail = Array(path.suffix(3))
			return tail.count == 3 && tail[0] == .key("variant") && tail[1] == .key("solar")
				&& [.key("altitude"), .key("azimuth")].contains(tail[2])
		}
		return last == .key("variant") && change.value is NSNull
	}

	private static func isShot(at index: Int, in built: AerialCatalog, of sets: [AerialSet]) -> Bool {
		guard built.assets.indices.contains(index), let asset = built.assets[index] as? [String: Any],
			let shotID = asset["shotID"] as? String
		else {
			return false
		}
		return sets.contains { $0.shotIDs.contains(shotID) }
	}

	private static func value(at path: [PathComponent], in root: Any) -> Any? {
		path.reduce(Optional(root)) { node, component in
			switch component {
			case .key(let key): (node as? [String: Any])?[key]
			case .index(let index): (node as? [Any]).flatMap { $0.indices.contains(index) ? $0[index] : nil }
			}
		}
	}

	private static func leaves(of root: Any) -> [[PathComponent]: Any] {
		var result: [[PathComponent]: Any] = [:]
		func visit(_ node: Any, _ path: [PathComponent]) {
			switch node {
			case let dictionary as [String: Any] where !dictionary.isEmpty:
				for (key, child) in dictionary {
					visit(child, path + [.key(key)])
				}
			case let array as [Any] where !array.isEmpty:
				for (index, child) in array.enumerated() {
					visit(child, path + [.index(index)])
				}
			default:
				result[path] = node
			}
		}
		visit(root, [])
		return result
	}
}
