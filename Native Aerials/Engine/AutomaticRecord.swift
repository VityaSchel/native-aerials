import Foundation

nonisolated struct ChoiceSlot: Codable, Hashable, Sendable {
	let path: [String]
	let automatic: String
	let video: String
}

nonisolated struct AutomaticRecord: JSONFile {
	var slots: [ChoiceSlot]
}

nonisolated extension Installer {
	var automaticRecord: AutomaticRecord? {
		AutomaticRecord.load(from: locations.automaticRecordFile)
	}

	func rememberAutomatic(_ slots: [ChoiceSlot]) {
		guard !slots.isEmpty else {
			return
		}
		do {
			try FileManager.default.createDirectory(at: locations.supportDirectory, withIntermediateDirectories: true)
			try AutomaticRecord(slots: slots).save(to: locations.automaticRecordFile)
		} catch {
			log.warn("could not remember which desktops showed Automatic (\(locations.automaticRecordFile.path)): \(error.localizedDescription)")
		}
	}

	func forgetAutomatic() {
		try? FileManager.default.removeItem(at: locations.automaticRecordFile)
		rmdir(locations.supportDirectory.path)
	}
}
