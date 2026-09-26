import Foundation
import Testing

nonisolated struct AgentTests {
	static let gg = AerialSet.goldenGate
	static let tahoe = AerialSet.tahoe
	static let combinedIDs: Set<String> = Set(AerialSet.all.map(\.subcategoryID))
	static let foreignCatalog = "/nonexistent/other-tool/entries.json"

	static func installed() async throws -> Sandbox {
		let sandbox = try Sandbox(index: IndexFixture.combined, videos: AerialSet.all.flatMap(\.videos))
		#expect(try await sandbox.run("enable").status == 0)
		return sandbox
	}

	@discardableResult
	static func runHelper(_ sandbox: Sandbox, _ environment: [String: String] = [:]) async throws -> CommandResult {
		try await sandbox.run(["--agent"], executable: sandbox.helper, environment: environment)
	}

	static func checkingFrom(_ app: URL) -> String {
		"agent: checking from \(Sandbox.resolved(Sandbox.executable(of: app)))"
	}

	static func reloaded(_ sandbox: Sandbox) async -> Bool {
		await eventually { sandbox.agentRecord?.loadedJobDigest == sandbox.digest(sandbox.agentFile) }
	}

	static func move(_ from: URL, to target: URL) throws {
		try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
		try FileManager.default.moveItem(at: from, to: target)
	}

	static func keptEverything(_ sandbox: Sandbox) -> Bool {
		sandbox.installedCatalog != nil && sandbox.exists(sandbox.agentFile) && FileManager.default.isExecutableFile(atPath: sandbox.helper.path)
	}

	@Test func handsOffToTheApp() async throws {
		let sandbox = try await Self.installed()
		let app = try sandbox.app
		#expect(sandbox.agentRecord?.appPath == Sandbox.resolved(app))
		let result = try await Self.runHelper(sandbox)
		#expect(result.status == 0 && result.lines.contains(Self.checkingFrom(app)), "\(result.output)")
		#expect(sandbox.rawActions.isEmpty)
	}

	@Test func followsAMovedApp() async throws {
		let sandbox = try await Self.installed()
		let moved = sandbox.directory.appending(path: "Elsewhere/Native Aerials.app", directoryHint: .isDirectory)
		try Self.move(try sandbox.app, to: moved)
		let result = try await Self.runHelper(sandbox)
		#expect(result.lines.contains(Self.checkingFrom(moved)), "\(result.output)")
		#expect(sandbox.agentRecord?.appPath == moved.path && (sandbox.agentPlist?["WatchPaths"] as? [String])?.first == moved.path)
		#expect(!sandbox.rawActions.contains { $0.contains("killall") })
		#expect(await Self.reloaded(sandbox))
		#expect(sandbox.actions == ["bootout \(AgentJob.label)", "bootstrap \(AgentJob.label)"])
		try await sandbox.run(["upgrade"], executable: Sandbox.executable(of: moved))
		#expect(sandbox.rawActions.isEmpty)
		let again = try await Self.runHelper(sandbox)
		#expect(!again.output.contains("reloading") && !sandbox.rawActions.contains { $0.hasPrefix("launchctl ") })
	}

	@Test func uninstallsWhenTheAppLeavesApplications() async throws {
		let sandbox = try await Self.installed()
		let downloaded = sandbox.directory.appending(path: "Downloads/Native Aerials.app", directoryHint: .isDirectory)
		try Self.move(try sandbox.app, to: downloaded)
		let result = try await Self.runHelper(sandbox, ["NATIVE_AERIALS_APPLICATIONS": sandbox.apps.path, "NATIVE_AERIALS_REGISTERED_APPS": downloaded.path])
		#expect(result.status == 0 && sandbox.actions == Sandbox.turnOffActions, "\(result.output)")
		#expect(!sandbox.exists(sandbox.agentFile) && !sandbox.exists(sandbox.paths.supportDirectory))
	}

	@Test func handsOffToARegisteredCopy() async throws {
		let sandbox = try await Self.installed()
		let downloaded = sandbox.directory.appending(path: "Downloads/Native Aerials.app", directoryHint: .isDirectory)
		let other = sandbox.directory.appending(path: "Other/Native Aerials.app", directoryHint: .isDirectory)
		try sandbox.cloneApp(to: downloaded)
		try sandbox.cloneApp(to: other)
		try FileManager.default.removeItem(at: try sandbox.app)
		let result = try await Self.runHelper(sandbox, [
			"NATIVE_AERIALS_REGISTERED_APPS": "\(downloaded.path):\(other.path)",
			"NATIVE_AERIALS_APPLICATIONS": "\(sandbox.apps.path):\(other.deletingLastPathComponent().path)",
		])
		#expect(result.lines.contains(Self.checkingFrom(other)) && sandbox.installedCatalog != nil, "\(result.output)")
		#expect(sandbox.agentRecord?.appPath == other.path)
		#expect(await Self.reloaded(sandbox))
	}

	@Test func keepsTheAgentOnTheCopyInApplications() async throws {
		let sandbox = try await Self.installed()
		let downloaded = sandbox.directory.appending(path: "Downloads/Native Aerials.app", directoryHint: .isDirectory)
		try sandbox.cloneApp(to: downloaded)
		let record = sandbox.agentRecord
		let job = sandbox.digest(sandbox.agentFile)
		let applications = ["NATIVE_AERIALS_APPLICATIONS": sandbox.apps.path]
		#expect(try await sandbox.run(["--agent", "--handed-off"], executable: Sandbox.executable(of: downloaded), environment: applications).status == 0)
		#expect(try await sandbox.run(["upgrade"], executable: Sandbox.executable(of: downloaded), environment: applications).status == 0)
		#expect(sandbox.agentRecord == record && sandbox.digest(sandbox.agentFile) == job && sandbox.rawActions.isEmpty)
	}

	@Test func waitsUntilAQuarantinedCopyIsOpened() async throws {
		let sandbox = try await Self.installed()
		let app = try sandbox.app
		let quarantine = "0083;68cc8650;Safari;"
		#expect(setxattr(app.path, "com.apple.quarantine", quarantine, quarantine.utf8.count, 0, 0) == 0)
		let result = try await Self.runHelper(sandbox)
		#expect(result.status == 0 && result.output.contains("hasn't been opened yet"), "\(result.output)")
		#expect(result.lines.contains("agent: checking from \(Sandbox.resolved(sandbox.helper))"))
		#expect(Self.keptEverything(sandbox) && sandbox.rawActions.isEmpty)
	}

	@Test func uninstallsWhenTheAppIsInTheTrash() async throws {
		let sandbox = try await Self.installed()
		let trashed = sandbox.directory.appending(path: "home/.Trash/Native Aerials.app", directoryHint: .isDirectory)
		try Self.move(try sandbox.app, to: trashed)
		let result = try await Self.runHelper(sandbox)
		#expect(result.status == 0 && sandbox.actions == Sandbox.turnOffActions)
		#expect(try sandbox.savedChoiceIDs.isDisjoint(with: Self.combinedIDs))
		#expect(!sandbox.exists(sandbox.agentFile) && !sandbox.exists(sandbox.paths.supportDirectory))
		let enable = try await sandbox.run(["enable"], executable: Sandbox.executable(of: trashed))
		#expect(enable.status == 1 && enable.error.contains("turns on only from the Applications folder"), "\(enable.error)")
		#expect(!sandbox.exists(sandbox.paths.customDirectory) && !sandbox.exists(sandbox.paths.supportDirectory) && sandbox.rawActions.isEmpty)
	}

	@Test func uninstallsWhenTheAppIsDeleted() async throws {
		let sandbox = try await Self.installed()
		try FileManager.default.removeItem(at: try sandbox.app)
		#expect(try await Self.runHelper(sandbox).status == 0)
		#expect(!sandbox.exists(sandbox.paths.customDirectory) && !sandbox.exists(sandbox.paths.supportDirectory))
		#expect(sandbox.rawActions.last == sandbox.ownBootout)
	}

	@Test(.enabled(if: !SystemInfo.isRoot, "permissions don't apply to root"))
	func keepsAnAppItCannotRead() async throws {
		let sandbox = try await Self.installed()
		let state = sandbox.digest(sandbox.paths.stateFile)
		try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: sandbox.apps.path)
		defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sandbox.apps.path) }
		let result = try await Self.runHelper(sandbox)
		#expect(result.status == 0 && result.output.contains("can't be read"))
		#expect(Self.keptEverything(sandbox) && sandbox.rawActions.isEmpty && sandbox.digest(sandbox.paths.stateFile) == state)
	}

	@Test func looksAgainBeforeUninstalling() async throws {
		let sandbox = try await Self.installed()
		let app = try sandbox.app
		let spare = sandbox.directory.appending(path: "Spare/Native Aerials.app", directoryHint: .isDirectory)
		try sandbox.cloneApp(to: spare)
		try FileManager.default.removeItem(at: app)
		async let result = Self.runHelper(sandbox, ["NATIVE_AERIALS_CONFIRM_DELAY": "3"])
		try await Task.sleep(for: .seconds(4.5))
		try FileManager.default.moveItem(at: spare, to: app)
		let finished = try await result
		#expect(finished.status == 0)
		#expect(Self.keptEverything(sandbox) && sandbox.rawActions.isEmpty, "\(sandbox.rawActions)")
	}

	@Test func treatsAQuicklyReplacedAppAsPresent() async throws {
		let sandbox = try await Self.installed()
		let app = try sandbox.app
		let parked = sandbox.directory.appending(path: "Parked/Native Aerials.app", directoryHint: .isDirectory)
		try Self.move(app, to: parked)
		async let result = Self.runHelper(sandbox)
		try await Task.sleep(for: .seconds(1))
		try FileManager.default.moveItem(at: parked, to: app)
		#expect(try await result.output.contains("agent: checking from"))
		#expect(Self.keptEverything(sandbox) && sandbox.rawActions.isEmpty)
	}

	@Test func finishesAPartialUndo() async throws {
		let sandbox = try await Self.installed()
		try sandbox.setPreference(Sandbox.overrideKey, nil)
		#expect(try await Self.runHelper(sandbox).status == 0)
		#expect(sandbox.actions == ["delete \(Sandbox.forceLocalKey)", "remove-custom", "replace", "restart", "bootout \(AgentJob.label)"])
		#expect(!sandbox.exists(sandbox.paths.customDirectory) && !sandbox.exists(sandbox.paths.supportDirectory))
	}

	@Test func leavesAnotherToolsOverride() async throws {
		let sandbox = try await Self.installed()
		try sandbox.setPreference(Sandbox.overrideKey, Self.foreignCatalog)
		#expect(try await Self.runHelper(sandbox).status == 0)
		#expect(sandbox.actions == ["remove-custom", "restart", "bootout \(AgentJob.label)"])
		#expect(sandbox.preferences[Sandbox.overrideKey] as? String == Self.foreignCatalog && !sandbox.exists(sandbox.paths.supportDirectory))
	}

	@Test func retiresWhenTurnedOff() async throws {
		let sandbox = try await Self.installed()
		let app = try sandbox.app
		try await sandbox.run("disable")
		let support = sandbox.paths.supportDirectory
		for name in ["Native Aerials", "Native Aerials.debug.dylib"] where sandbox.exists(app.appending(path: "Contents/MacOS/\(name)")) {
			try FileManager.default.copyItem(at: app.appending(path: "Contents/MacOS/\(name)"), to: support.appending(path: name))
		}
		try AgentRecord(appPath: app.path, appBookmark: nil, sourceDigest: "x").save(to: sandbox.agentRecordFile)
		try FileManager.default.createDirectory(at: sandbox.paths.launchAgents, withIntermediateDirectories: true)
		try PropertyListSerialization.data(fromPropertyList: [String: Any](), format: .xml, options: 0).write(to: sandbox.agentFile)
		let result = try await Self.runHelper(sandbox)
		#expect(result.status == 0 && result.error.isEmpty, "\(result.error)")
		#expect(!sandbox.exists(sandbox.agentFile) && sandbox.contents(of: support) == [sandbox.paths.automaticRecordFile.lastPathComponent])
		#expect(sandbox.rawActions == [sandbox.ownBootout])
	}

	@Test func changesNothingWhenNothingChanged() async throws {
		let sandbox = try await Self.installed()
		try await sandbox.run("--agent", "--handed-off")
		let catalog = sandbox.digest(sandbox.paths.catalogFile)
		let state = sandbox.digest(sandbox.paths.stateFile)
		#expect(try await sandbox.run("--agent", "--handed-off").status == 0)
		#expect(sandbox.rawActions.isEmpty && sandbox.digest(sandbox.paths.catalogFile) == catalog && sandbox.digest(sandbox.paths.stateFile) == state)
	}

	@Test func rebuildsAfterASystemUpdate() async throws {
		let sandbox = try await Self.installed()
		let catalog = try #require(sandbox.installedCatalog)
		try sandbox.makeStateStale()
		#expect(try await sandbox.run("--agent", "--handed-off").status == 0)
		#expect(sandbox.actions == ["restart"] && sandbox.state?.osBuild == SystemInfo.buildVersion)
		#expect(JSONTree.equal(sandbox.installedCatalog?.root, catalog.root))
	}

	@Test func rebuildsAStaleCatalog() async throws {
		let sandbox = try await Self.installed()
		let catalog = try #require(sandbox.installedCatalog)
		var stale = catalog.root
		stale["categories"] = (stale["categories"] as? [[String: Any]])?.map { category in
			var category = category
			category["subcategories"] = (category["subcategories"] as? [[String: Any]])?.map { subcategory in
				subcategory["id"] as? String == Self.gg.subcategoryID ? subcategory.filter { $0.key != "combineVariants" } : subcategory
			}
			return category
		}
		try JSONTree.serialize(stale).write(to: sandbox.paths.catalogFile)
		#expect(try await sandbox.run("--agent", "--handed-off").status == 0)
		#expect(sandbox.actions == ["restart"])
		#expect(JSONTree.equal(sandbox.installedCatalog?.root, catalog.root))
	}

	@Test func stepsAsideWhenAppleShipsEverySet() async throws {
		let sandbox = try await Self.installed()
		let apple = try sandbox.write(CatalogFixture().shippingSolar(AerialSet.all), named: "apple")
		#expect(try await sandbox.run(["--agent", "--handed-off"], environment: ["NATIVE_AERIALS_MANIFEST": apple.path]).status == 0)
		#expect(sandbox.actions == ["delete \(Sandbox.overrideKey)", "delete \(Sandbox.forceLocalKey)", "remove-custom", "restart", "bootout \(AgentJob.label)"])
		#expect(!sandbox.exists(sandbox.agentFile) && !sandbox.exists(sandbox.paths.supportDirectory))
		#expect(sandbox.rawActions.last == sandbox.ownBootout)
	}

	@Test func followsWhatAppleShipsPerSet() async throws {
		let sandbox = try await Self.installed()
		let source = CatalogFixture().shippingSolar([.tahoe])
		let apple = try sandbox.write(source, named: "apple")
		#expect(try await sandbox.run(["--agent", "--handed-off"], environment: ["NATIVE_AERIALS_MANIFEST": apple.path]).status == 0)
		#expect(sandbox.actions == ["restart"] && sandbox.exists(sandbox.agentFile))
		let installed = try #require(sandbox.installedCatalog)
		#expect(JSONTree.equal(CatalogFixture.entries(of: .tahoe, in: installed.root), CatalogFixture.entries(of: .tahoe, in: source.root)))
	}

	@Test func switchesOffWhenACombinedSetsLayoutChanges() async throws {
		let sandbox = try await Self.installed()
		let reordered = try sandbox.write(CatalogFixture().reorderedAssets(.tahoe), named: "reordered")
		let result = try await sandbox.run(["--agent", "--handed-off"], environment: ["NATIVE_AERIALS_MANIFEST": reordered.path])
		#expect(result.status == 0 && result.error.contains("unexpected aerial catalog"))
		#expect(sandbox.actions == Sandbox.turnOffActions)
		#expect(try sandbox.savedChoiceIDs.isDisjoint(with: Self.combinedIDs))
		#expect(!sandbox.exists(sandbox.paths.customDirectory) && !sandbox.exists(sandbox.agentFile) && !sandbox.exists(sandbox.paths.supportDirectory))
		#expect(sandbox.rawActions.last == sandbox.ownBootout)
	}
}
