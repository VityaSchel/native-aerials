import Foundation

nonisolated enum TileStatus: Equatable, Sendable {
	case loading
	case ready
	case missing
	case downloading(percent: Int)

	var accessibilityValue: String {
		switch self {
		case .loading, .ready: ""
		case .missing: "Not downloaded"
		case .downloading(let percent): "Downloading, \(percent) percent"
		}
	}

	var accessibilityHint: String {
		switch self {
		case .loading: ""
		case .ready: "Sets it as your wallpaper"
		case .missing: "Opens Wallpaper settings to download it"
		case .downloading: "Opens Wallpaper settings"
		}
	}
}

nonisolated struct TileItem: Identifiable, Equatable, Sendable {
	let id: String
	let name: String
	let thumbnail: URL?
	let status: TileStatus
	let isSelected: Bool
	let flash: Int
	var canRemove = false
}

nonisolated struct SetRow: Identifiable, Equatable, Sendable {
	let id: String
	let name: String
	let tiles: [TileItem]
	let isMerged: Bool
	let isSelected: Bool
	var canRemove = false
	var animatesMerge = false
}

nonisolated struct Footnote: Equatable, Sendable {
	enum Tone: Sendable {
		case info
		case warning
		case error
	}

	let text: String
	var tone = Tone.info
	var action: SettingsPane?
}

nonisolated extension SettingsPane {
	var linkTitle: String {
		switch self {
		case .wallpaper: "Open Wallpaper Settings"
		case .loginItems: "Open Login Items"
		case .dateTime: "Open Date & Time"
		}
	}
}
