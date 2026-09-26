import Foundation

nonisolated extension PanelState {
	var footnote: Footnote? {
		if let message {
			return message
		}
		guard let snapshot else {
			return nil
		}
		let isOn = snapshot.isOn
		switch snapshot.availability {
		case .unsupported(let reason) where !isOn, .blocked(let reason) where !isOn:
			return Footnote(text: reason, tone: .warning)
		case .appleDoesThis where !isOn:
			return Footnote(text: "macOS now combines these videos itself. Pick a combined one to use Automatic.")
		default:
			break
		}
		if snapshot.needsRepair && !isOn {
			return Footnote(text: "Native Aerials is only partly set up. Turn it off to clean up.", tone: .warning)
		}
		if !isOn && snapshot.sets.contains(where: { $0.readiness == .unexpectedLayout }) {
			return Footnote(text: InstallerError.unexpectedCatalogSummary, tone: .warning)
		}
		if isOn && snapshot.agent == .needsApproval {
			return Footnote(text: "Allow Native Aerials in Login Items so it stays in sync.", tone: .warning, action: .loginItems)
		}
		if snapshot.needsMoveToApplications {
			return Footnote(text: Installer.moveNotice, tone: .warning)
		}
		if isOn && snapshot.automaticTimeZone == false {
			return Footnote(text: "Turn on “Set time zone automatically” so the sun times match where you are.", action: .dateTime)
		}
		if let directory = snapshot.dryRunDirectory {
			return Footnote(text: "Dry run: changes go to \(directory).")
		}
		return nil
	}

	static func message(after report: EngineReport) -> Footnote? {
		report.notices.last.map { Footnote(text: $0, tone: .warning) }
	}

	static func message(for error: InstallerError, action: SettingsPane? = nil) -> Footnote? {
		guard error.missingAssetIDs.isEmpty else {
			return nil
		}
		return Footnote(text: error.summary, tone: .error, action: action)
	}
}
