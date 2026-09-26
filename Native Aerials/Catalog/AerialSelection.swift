import Foundation

nonisolated struct AerialSelection: Equatable, Sendable {
	static let logPrefix = "Selected aerial ids did change: "

	var ids: Set<String> = []
	var includesCategories = false

	var protectedAssetIDs: Set<String> {
		includesCategories ? AerialSet.allIDs : AerialSet.addingVideos(ofSetsIn: ids)
	}
}

nonisolated extension AerialSelection {
	init?(logMessage message: String) {
		guard message.hasPrefix(Self.logPrefix), let arrow = message.range(of: " -> ", options: .backwards) else {
			return nil
		}
		let current = message[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
		let fields = current.matches(of: #/(\w+): \[([^\]]*)\]/#)
		guard current.hasPrefix("<"), current.hasSuffix(">"), !fields.isEmpty || current == "<>" else {
			return nil
		}
		for field in fields {
			let ids = field.output.2.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
			switch field.output.1 {
			case "assetIDs", "subcategoryIDs":
				self.ids.formUnion(ids)
			default:
				includesCategories = includesCategories || !ids.isEmpty
			}
		}
	}
}
