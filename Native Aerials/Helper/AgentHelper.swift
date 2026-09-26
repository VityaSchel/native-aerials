import Foundation

nonisolated struct AgentRecord: JSONFile, Equatable {
	var appPath: String
	var appBookmark: Data?
	var sourceDigest: String
	var appVersion: String?
	var loadedJobDigest: String?
}

nonisolated struct AgentHelper {
	static let executableName = "Native Aerials"
	static let signingIdentifier = AgentJob.label
	static let recordName = "agent.json"
	private static let installSummary = "The background helper couldn’t be installed. Try again."

	let directory: URL

	var executable: URL { directory.appending(path: Self.executableName) }
	private var recordFile: URL { directory.appending(path: Self.recordName) }
	var record: AgentRecord? { AgentRecord.load(from: recordFile) }
	private var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: executable.path) }

	func install(from source: URL, app: URL) throws {
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let digest = SystemInfo.sha256(of: source)
		let current = record
		let replaces = current?.sourceDigest != digest || !isInstalled
		if replaces {
			try place(source, at: executable)
		}
		if replaces || current?.appPath != app.path || current?.appVersion != SystemInfo.appVersion {
			let updated = AgentRecord(
				appPath: app.path,
				appBookmark: try? app.bookmarkData(),
				sourceDigest: digest,
				appVersion: SystemInfo.appVersion,
				loadedJobDigest: current?.loadedJobDigest
			)
			try updated.save(to: recordFile)
		}
	}

	func recordLoadedJob(_ digest: String) throws {
		guard var updated = record, updated.loadedJobDigest != digest else {
			return
		}
		updated.loadedJobDigest = digest
		try updated.save(to: recordFile)
	}

	func remove() {
		for file in [executable, recordFile] {
			try? FileManager.default.removeItem(at: file)
		}
		rmdir(directory.path)
	}

	private func place(_ source: URL, at target: URL) throws {
		let staging = directory.appending(path: ".\(target.lastPathComponent).new")
		try? FileManager.default.removeItem(at: staging)
		try Data(contentsOf: source).write(to: staging)
		try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging.path)
		let signing = Subprocess.run("/usr/bin/codesign", [
			"--force", "--sign", "-", "--preserve-metadata=flags,entitlements",
			"--identifier", Self.signingIdentifier, staging.path,
		])
		guard signing.status == 0 else {
			try? FileManager.default.removeItem(at: staging)
			throw InstallerError("could not sign \(target.path): codesign exited with \(signing.status)", summary: Self.installSummary)
		}
		guard rename(staging.path, target.path) == 0 else {
			try? FileManager.default.removeItem(at: staging)
			throw InstallerError("could not write \(target.path): \(String(cString: strerror(errno)))", summary: Self.installSummary)
		}
	}
}
