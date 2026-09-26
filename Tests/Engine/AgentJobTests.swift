import Foundation
import Testing

nonisolated struct AgentJobTests {
	@Test func describesTheBackgroundJob() throws {
		let sandbox = try Sandbox()
		let installer = try sandbox.installer()
		let app = sandbox.apps.appending(path: "Native Aerials.app", directoryHint: .isDirectory)
		let job = installer.agentJob(watching: app)
		let plist = try #require(try PropertyListSerialization.propertyList(from: job.contents(), format: nil) as? [String: Any])
		#expect(job.file == sandbox.agentFile)
		#expect(plist["Label"] as? String == AgentJob.label)
		#expect(plist["ProgramArguments"] as? [String] == [sandbox.helper.path, AgentJob.argument])
		#expect(plist["RunAtLoad"] as? Bool == true)
		#expect(plist["WatchPaths"] as? [String] == [app.path, sandbox.videos.path, installer.locations.manifestDirectory.path])
		#expect(plist["ThrottleInterval"] as? Int == 5)
		#expect(plist["ProcessType"] as? String == "Background")
		#expect(plist["LowPriorityIO"] as? Bool == true)
		#expect(plist["AbandonProcessGroup"] as? Bool == true)
		#expect(plist["AssociatedBundleIdentifiers"] as? [String] == [AgentJob.bundleIdentifier])
		#expect(plist["KeepAlive"] == nil)
		#expect(try job.digest() == SystemInfo.sha256(of: job.contents()))
		#expect(try job.write() && !job.write())
	}
}
