import Foundation
import Testing

nonisolated struct HelperTests {
	@Test func upgradesTheHelperFromTheApp() async throws {
		let sandbox = try Sandbox(videos: AerialSet.all.flatMap(\.videos))
		let executable = Sandbox.executable(of: try sandbox.app)
		try await sandbox.run("enable")
		#expect(try await sandbox.tool("/usr/bin/codesign", "-v", "--strict", sandbox.helper.path).status == 0)
		#expect(try await sandbox.tool("/usr/bin/codesign", "-dv", sandbox.helper.path).error.contains("Identifier=\(AgentHelper.signingIdentifier)\n"))
		#expect(getxattr(sandbox.helper.path, "com.apple.quarantine", nil, 0, 0, 0) < 0)
		let version = try #require(Bundle(url: try sandbox.app)?.infoDictionary?["CFBundleShortVersionString"] as? String)
		#expect(try await sandbox.run(["--version"], executable: sandbox.helper).output == "Native Aerials \(version)\n")
		#expect(try await sandbox.run(["--version"]).output == "Native Aerials \(version)\n")

		try await sandbox.run("upgrade")
		#expect(sandbox.rawActions.isEmpty)
		var record = try #require(sandbox.agentRecord)
		record.sourceDigest = "old"
		try record.save(to: sandbox.agentRecordFile)
		let before = try FileManager.default.attributesOfItem(atPath: sandbox.helper.path)[.systemFileNumber] as? Int
		try await sandbox.run("upgrade")
		#expect(sandbox.agentRecord?.sourceDigest == sandbox.digest(executable))
		#expect(try FileManager.default.attributesOfItem(atPath: sandbox.helper.path)[.systemFileNumber] as? Int != before)
		#expect(sandbox.rawActions.isEmpty)

		let moved = sandbox.directory.appending(path: "Moved/Native Aerials.app", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
		try FileManager.default.moveItem(at: try sandbox.app, to: moved)
		try await sandbox.run(["upgrade"], executable: Sandbox.executable(of: moved))
		#expect(sandbox.actions == ["bootout \(AgentJob.label)", "bootstrap \(AgentJob.label)"])
		#expect((sandbox.agentPlist?["WatchPaths"] as? [String])?.first == moved.path)
	}

	@Test func leavesNothingBehindWhileOff() async throws {
		let sandbox = try Sandbox(videos: AerialSet.all.flatMap(\.videos))
		try await sandbox.run("upgrade")
		#expect(!sandbox.exists(sandbox.paths.supportDirectory) && !sandbox.exists(sandbox.paths.launchAgents) && sandbox.rawActions.isEmpty)
		try await sandbox.run("status")
		#expect(!sandbox.exists(sandbox.paths.supportDirectory) && !sandbox.exists(sandbox.paths.launchAgents) && !sandbox.exists(sandbox.paths.wallpaperRoot.appending(path: "aerials")))
		#expect(sandbox.rawActions.isEmpty && !sandbox.exists(sandbox.paths.lockFile))
	}
}
