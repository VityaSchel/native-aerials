import Foundation
import Testing

@Suite(.enabled(if: !SystemInfo.isRoot, "permissions don't apply to root"))
nonisolated struct RollbackTests {
	static func withReadOnlyPreferences<T>(_ sandbox: Sandbox, _ body: () async throws -> T) async throws -> T {
		let folder = sandbox.paths.preferencesFile.deletingLastPathComponent().path
		try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder)
		defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder) }
		return try await body()
	}

	@Test func undoesAFreshInstall() async throws {
		let sandbox = try Sandbox(videos: AerialSet.all.flatMap(\.videos))
		_ = try sandbox.app
		let preferences = sandbox.digest(sandbox.paths.preferencesFile)
		let result = try await Self.withReadOnlyPreferences(sandbox) { try await sandbox.run("enable") }
		#expect(result.status == 1 && result.lines.contains("rolling back to the state before this change"))
		#expect(!sandbox.exists(sandbox.paths.customDirectory) && !sandbox.exists(sandbox.paths.launchAgents))
		#expect(!sandbox.rawActions.contains { $0.contains("killall") })
		#expect(sandbox.digest(sandbox.paths.preferencesFile) == preferences)
	}

	@Test func restoresAPartialInstall() async throws {
		let sandbox = try Sandbox(videos: AerialSet.tahoe.videos)
		_ = try sandbox.app
		let old = try CatalogPatcher.patch(CatalogFixture().catalog, sets: AerialSet.all)
		try FileManager.default.createDirectory(at: sandbox.paths.customDirectory, withIntermediateDirectories: true)
		try old.data.write(to: sandbox.paths.catalogFile)
		let catalog = sandbox.digest(sandbox.paths.catalogFile)
		let index = sandbox.digest(sandbox.paths.indexFile)
		let result = try await Self.withReadOnlyPreferences(sandbox) { try await sandbox.run("enable") }
		#expect(result.status == 1)
		#expect(sandbox.digest(sandbox.paths.catalogFile) == catalog && !sandbox.exists(sandbox.paths.stateFile))
		#expect(sandbox.digest(sandbox.paths.indexFile) == index && !sandbox.rawActions.contains { $0.contains("killall") })
		#expect(sandbox.contents(of: sandbox.paths.indexFile.deletingLastPathComponent()) == ["Index.plist"])
	}
}
