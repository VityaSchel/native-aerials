import Foundation
import Testing

nonisolated struct LockTests {
	static func isHeld(_ file: URL) -> Bool {
		let descriptor = open(file.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
		defer { close(descriptor) }
		return flock(descriptor, LOCK_EX | LOCK_NB) != 0
	}

	static func modified(_ file: URL) -> Date? {
		try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
	}

	@Test func waitsForAnotherProcessAndRecoversWhenItDies() async throws {
		let sandbox = try Sandbox(videos: AerialSet.all.flatMap(\.videos))
		_ = try sandbox.app
		let lock = sandbox.paths.lockFile
		let holder = Process()
		holder.executableURL = URL(filePath: "/usr/bin/lockf")
		holder.arguments = ["-k", lock.path, "/bin/sleep", "30"]
		try holder.run()
		var crashed = false
		func crash() {
			guard !crashed else {
				return
			}
			crashed = true
			let children = Subprocess.run("/usr/bin/pgrep", ["-P", String(holder.processIdentifier)]).output.split(separator: "\n").compactMap { Int32($0) }
			kill(holder.processIdentifier, SIGKILL)
			children.forEach { kill($0, SIGKILL) }
		}
		defer { crash() }
		try #require(await eventually(within: 5) { Self.isHeld(lock) })
		let busy = try await sandbox.run(["enable"], environment: ["NATIVE_AERIALS_LOCK_TIMEOUT": "1"])
		#expect(busy.status == 1 && busy.error.contains("busy for 1 s"))
		#expect(sandbox.installedCatalog == nil && sandbox.rawActions.isEmpty)
		let agent = try await sandbox.run(["--agent", "--handed-off"], environment: ["NATIVE_AERIALS_LOCK_TIMEOUT": "1"])
		#expect(agent.status == 0 && sandbox.rawActions.isEmpty)
		let prepared = Self.modified(sandbox.dryRun.actionsLog)
		async let waiting = sandbox.run(["enable"], environment: ["NATIVE_AERIALS_LOCK_TIMEOUT": "10"])
		#expect(await eventually { Self.modified(sandbox.dryRun.actionsLog) != prepared })
		try await Task.sleep(for: .seconds(1))
		crash()
		let result = try await waiting
		#expect(result.status == 0 && sandbox.installedCatalog != nil)
	}
}
