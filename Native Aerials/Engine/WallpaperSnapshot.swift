import Foundation
import ServiceManagement

nonisolated enum Availability: Equatable, Sendable {
	case available
	case unsupported(String)
	case appleDoesThis
	case blocked(String)
}

nonisolated enum DownloadState: String, Sendable {
	case onDisk = "on-disk"
	case missing
}

nonisolated enum AgentState: String, Sendable {
	case notInstalled = "not-installed"
	case installed
	case needsApproval = "needs-approval"
}

nonisolated struct VariantSnapshot: Identifiable, Equatable, Sendable {
	let assetID: String
	let caption: String
	let name: String
	let thumbnail: URL?
	let download: DownloadState
	let isSelected: Bool

	var id: String { assetID }
}

nonisolated struct SetSnapshot: Identifiable, Equatable, Sendable {
	let subcategoryID: String
	let name: String
	let thumbnail: URL?
	let variants: [VariantSnapshot]
	let readiness: SetReadiness
	let isMerged: Bool
	let isMergedByApple: Bool
	let isSelected: Bool

	var id: String { subcategoryID }
	var missingAssetIDs: [String] { variants.filter { $0.download != .onDisk }.map(\.assetID) }
	var isComplete: Bool { missingAssetIDs.isEmpty }
}

nonisolated struct WallpaperSnapshot: Equatable, Sendable {
	var isOn: Bool
	var needsRepair: Bool
	var availability: Availability
	var sets: [SetSnapshot]
	var desktopChoice: AerialChoice?
	var selectedAssetID: String?
	var savedAssetIDs: Set<String>
	var shufflesAerials: Bool
	var agent: AgentState
	var needsMoveToApplications: Bool
	var automaticTimeZone: Bool?
	var dryRunDirectory: String?

	var onDiskAssetIDs: Set<String> { Set(sets.flatMap(\.variants).filter { $0.download == .onDisk }.map(\.assetID)) }
	var mergedSetIDs: Set<String> { Set(sets.filter(\.isMerged).map(\.subcategoryID)) }

	private static func onScreenAssetID(saved: String?, locations: Locations) -> String? {
		guard let saved, AerialSet.video(withAssetID: saved) != nil, !locations.isDownloaded(assetID: saved) else {
			return saved
		}
		let fallback = AerialSet.systemDefaultAssetID
		return locations.isDownloaded(assetID: fallback) ? fallback : nil
	}

	init(_ installer: Installer) {
		let installation = installer.installation()
		let plan = installer.mergePlan()
		let index = try? installer.store.readIndex()
		let desktopChoiceID = index?.inUse(spaces: installer.locations.desktopSpaceIDs, includingRecent: false).currentDesktopAssetID
		desktopChoice = desktopChoiceID.flatMap(AerialChoice.init(identifier:))
		let selected = Self.onScreenAssetID(saved: desktopChoiceID, locations: installer.locations)
		let merged = installation == .enabled ? installer.installedCatalog()?.combinedSets ?? [] : AerialSet.all.filter(plan.sourceCombines)
		isOn = installation == .enabled
		needsRepair = installation == .partial
		availability = Self.availability(installer, plan: plan, installation: installation)
		selectedAssetID = selected
		let inUse = index?.inUse(spaces: installer.locations.liveSpaceIDs, includingRecent: true)
		savedAssetIDs = inUse?.choiceAssetIDs ?? []
		shufflesAerials = inUse?.shufflesAerials(categoryIDs: plan.source?.categoryIDs ?? []) ?? false
		sets = plan.listedSets.map { set in
			let variants = set.videos.map { video in
				let onDisk = installer.locations.isDownloaded(assetID: video.assetID)
				return VariantSnapshot(
					assetID: video.assetID,
					caption: video.caption,
					name: video.name,
					thumbnail: installer.locations.thumbnail(forID: video.assetID),
					download: onDisk ? .onDisk : .missing,
					isSelected: selected == video.assetID
				)
			}
			return SetSnapshot(
				subcategoryID: set.subcategoryID,
				name: set.displayName,
				thumbnail: installer.locations.thumbnail(forID: set.subcategoryID),
				variants: variants,
				readiness: plan.readiness[set] ?? .unexpectedLayout,
				isMerged: merged.contains(set),
				isMergedByApple: plan.sourceCombines(set) && plan.readiness[set] == .appleProvides,
				isSelected: selected == set.subcategoryID
			)
		}
		agent = Self.agentState(installer)
		needsMoveToApplications = installer.needsMoveToApplications
		automaticTimeZone = SystemInfo.automaticTimeZone
		dryRunDirectory = installer.locations.dryRun?.directory.path
	}

	private static func availability(_ installer: Installer, plan: MergePlan, installation: Installation) -> Availability {
		do {
			try installer.preflight()
		} catch {
			return .unsupported(InstallerError(describing: error).summary)
		}
		if plan.appleProvidesAll && installation != .enabled {
			return .appleDoesThis
		}
		if case .foreign = installation {
			do {
				try installer.checkOverrideIsOurs()
			} catch {
				return .blocked(InstallerError(describing: error).summary)
			}
		}
		if plan.source == nil {
			return .blocked(InstallerError.unexpectedCatalogSummary)
		}
		return .available
	}

	static func agentState(_ installer: Installer) -> AgentState {
		guard installer.isAgentInstalled else {
			return .notInstalled
		}
		guard installer.locations.dryRun == nil else {
			return .installed
		}
		return SMAppService.statusForLegacyPlist(at: installer.agentFile) == .requiresApproval ? .needsApproval : .installed
	}
}
