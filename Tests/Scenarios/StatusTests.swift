import Foundation
import Testing

nonisolated struct StatusTests {
	static let allVideos = AerialSet.all.flatMap(\.videos)

	@Test func reportsTheInstalledState() async throws {
		let sandbox = try Sandbox(videos: Self.allVideos)
		#expect(try await sandbox.run("status").lines.contains("helper: not-installed"))
		try await sandbox.run("enable")
		let lines = try await sandbox.run("status").lines
		#expect(lines.contains("on: 1"))
		#expect(lines.filter { $0.hasPrefix("set ") && $0.contains(" merged=1 ") && $0.contains(" readiness=ready ") }.count == AerialSet.all.count)
		#expect(lines.filter { $0.hasPrefix("  variant ") && $0.contains(" on-disk ") }.count == Self.allVideos.count)
	}

	@Test func rejectsUsageErrors() async throws {
		let sandbox = try Sandbox()
		let unknown = try await sandbox.run("frobnicate")
		#expect(unknown.status == 2 && unknown.error == "native-aerials: unknown command frobnicate\n")
		let extra = try await sandbox.run("status", "extra")
		#expect(extra.status == 2 && extra.error == "native-aerials: unexpected argument extra\n")
	}
}
