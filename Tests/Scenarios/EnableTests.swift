import Foundation
import Testing

nonisolated struct EnableTests {
	static let gg = AerialSet.goldenGate
	static let tahoe = AerialSet.tahoe
	static let allVideos = AerialSet.all.flatMap(\.videos)

	@Test func refusesWithoutACompleteSet() async throws {
		let placed = [Self.tahoe.day, Self.gg.morning]
		let sandbox = try Sandbox(videos: placed)
		let result = try await sandbox.run("enable")
		let missing = Self.allVideos.filter { video in !placed.contains { $0.assetID == video.assetID } }.map(\.name).joined(separator: ", ")
		#expect(result.status == 1)
		#expect(result.error.contains("no set has all four videos on disk (missing: \(missing))"), "\(result.error)")
		#expect(sandbox.installedCatalog == nil && sandbox.rawActions.isEmpty && !sandbox.hasOverride)
		#expect(!sandbox.exists(sandbox.paths.launchAgents) && !sandbox.exists(sandbox.paths.supportDirectory))
	}

	@Test func refusesToTurnOnOutsideApplications() async throws {
		let sandbox = try Sandbox(videos: Self.allVideos)
		let applications = sandbox.directory.appending(path: "Applications").path
		let result = try await sandbox.run(["enable"], environment: ["NATIVE_AERIALS_APPLICATIONS": applications])
		#expect(result.status == 1 && result.error.contains("turns on only from \(applications), so move it there"), "\(result.error)")
		#expect(sandbox.installedCatalog == nil && sandbox.rawActions.isEmpty && !sandbox.hasOverride)
		#expect(!sandbox.exists(sandbox.paths.launchAgents) && !sandbox.exists(sandbox.paths.supportDirectory))
		#expect(try await sandbox.run(["enable"], environment: ["NATIVE_AERIALS_APPLICATIONS": sandbox.apps.path]).status == 0)
	}

	@Test func combinesOnlyCompleteSets() async throws {
		let sandbox = try Sandbox(videos: Self.tahoe.videos + [Self.gg.day])
		let index = sandbox.digest(sandbox.paths.indexFile)
		let result = try await sandbox.run("enable")
		#expect(result.status == 0)
		#expect(sandbox.combinedSetIDs == [Self.tahoe.subcategoryID])
		#expect(sandbox.anchors(of: Self.tahoe) == 4 && sandbox.anchors(of: Self.gg) == 0)
		#expect(sandbox.state?.mergedSets == [Self.tahoe.slug])
		#expect(sandbox.preferences[Sandbox.overrideKey] as? String == (try sandbox.locations().catalogTarget))
		#expect(sandbox.preferences[Sandbox.forceLocalKey] as? Bool == true)
		#expect(sandbox.actions == Sandbox.turnOnActions)
		#expect(sandbox.digest(sandbox.paths.indexFile) == index)
		#expect(result.lines.contains("Combined: \(Self.tahoe.slug)"))
		#expect((sandbox.agentPlist?["WatchPaths"] as? [String])?[1] == sandbox.videos.path)
		let snapshot = try sandbox.snapshot()
		let sets = Dictionary(uniqueKeysWithValues: snapshot.sets.map { ($0.subcategoryID, $0) })
		#expect(snapshot.isOn && sets[Self.tahoe.subcategoryID]?.isMerged == true && sets[Self.gg.subcategoryID]?.isMerged == false)
		#expect(sets[Self.gg.subcategoryID]?.readiness == .missingVideos([Self.gg.morning, Self.gg.evening, Self.gg.night].map(\.assetID)))
		let variants = Dictionary(uniqueKeysWithValues: snapshot.sets.flatMap(\.variants).map { ($0.assetID, $0.download) })
		#expect(variants[Self.gg.day.assetID] == .onDisk && variants[Self.gg.night.assetID] == .missing)
	}

	@Test func combinesEverySetAndInstallsTheAgent() async throws {
		let sandbox = try Sandbox(videos: Self.allVideos)
		let result = try await sandbox.run("enable")
		let app = try sandbox.app
		#expect(result.status == 0)
		#expect(result.output.contains("each combined set is one item now (\(AerialSet.all.map(\.displayName).joined(separator: ", ")))"))
		#expect(sandbox.combinedSetIDs == Set(AerialSet.all.map(\.subcategoryID)))
		#expect(AerialSet.all.allSatisfy { sandbox.anchors(of: $0) == 4 })
		let state = try #require(sandbox.state)
		#expect(state.mergedSets == AerialSet.all.map(\.slug))
		#expect(state.bundledDigest == sandbox.digest(sandbox.bundledCatalog))
		#expect(state.catalogDigest == sandbox.digest(sandbox.paths.catalogFile))
		#expect(state.source == sandbox.manifest.path && state.osBuild == SystemInfo.buildVersion)
		let plist = try #require(sandbox.agentPlist)
		#expect(plist["ProgramArguments"] as? [String] == [sandbox.helper.path, AgentJob.argument])
		#expect(plist["WatchPaths"] as? [String] == [Sandbox.resolved(app), sandbox.videos.path, try sandbox.locations().manifestDirectory.path])
		#expect(plist["RunAtLoad"] as? Bool == true && plist["ThrottleInterval"] as? Int == AgentJob.throttleInterval && plist["KeepAlive"] == nil)
		#expect(sandbox.rawActions.filter { $0.hasPrefix("launchctl ") } == ["launchctl bootstrap gui/\(getuid()) \(sandbox.agentFile.path)"])
		#expect(try await sandbox.tool("/usr/bin/codesign", "-v", "--strict", sandbox.helper.path).status == 0)
		#expect(try await sandbox.run(["--version"], executable: sandbox.helper).output.hasPrefix("Native Aerials "))
		#expect(sandbox.agentRecord?.appPath == Sandbox.resolved(app))
	}

	@Test func combinesASetCompletedLater() async throws {
		let sandbox = try Sandbox(videos: Self.tahoe.videos)
		try await sandbox.run("enable")
		sandbox.place(Self.gg.videos)
		try await sandbox.run("enable")
		#expect(sandbox.combinedSetIDs == Set(AerialSet.all.map(\.subcategoryID)))
		#expect(sandbox.actions == ["restart"])
	}

	@Test func secondEnableChangesNothing() async throws {
		let sandbox = try Sandbox(videos: Self.allVideos)
		try await sandbox.run("enable")
		let catalog = sandbox.digest(sandbox.paths.catalogFile)
		let state = sandbox.digest(sandbox.paths.stateFile)
		let result = try await sandbox.run("enable")
		#expect(result.status == 0 && sandbox.rawActions.isEmpty)
		#expect(sandbox.digest(sandbox.paths.catalogFile) == catalog && sandbox.digest(sandbox.paths.stateFile) == state)
		#expect(result.lines.contains("Already enabled; nothing changed."))
	}

	@Test func stepsAsideWhenAppleShipsEverySet() async throws {
		let sandbox = try Sandbox(videos: Self.allVideos)
		try await sandbox.run("enable")
		let apple = try sandbox.write(CatalogFixture().shippingSolar(AerialSet.all), named: "apple")
		let result = try await sandbox.run(["enable"], environment: ["NATIVE_AERIALS_MANIFEST": apple.path])
		#expect(result.status == 0)
		#expect(result.output.contains("Apple's catalog now has its own solar data for: \(AerialSet.all.map(\.slug).sorted().joined(separator: " ")). Removing Native Aerials."))
		#expect(!sandbox.exists(sandbox.paths.customDirectory) && !sandbox.hasOverride && !sandbox.exists(sandbox.agentFile))
	}

	@Test(arguments: CatalogVariant.allCases)
	func acceptsCatalogVariants(_ variant: CatalogVariant) async throws {
		let sandbox = try Sandbox(videos: Self.allVideos)
		try variant.catalog.data.write(to: sandbox.manifest)
		let index = sandbox.digest(sandbox.paths.indexFile)
		let result = try await sandbox.run("enable")
		#expect(result.status == 0, "\(result.error)")
		#expect(sandbox.combinedSetIDs == Set(AerialSet.all.map(\.subcategoryID)))
		#expect(sandbox.actions == Sandbox.turnOnActions)
		#expect(sandbox.preferences[Sandbox.forceLocalKey] as? Bool == true)
		#expect(sandbox.digest(sandbox.paths.indexFile) == index)
	}

	@Test func fallsBackToTheBundledCatalog() async throws {
		let sandbox = try Sandbox(videos: Self.allVideos)
		try CatalogFixture.invalidJSON.write(to: sandbox.manifest)
		let result = try await sandbox.run("enable")
		#expect(result.status == 0)
		#expect(sandbox.state?.source == sandbox.bundledCatalog.path)
		#expect(sandbox.combinedSetIDs == Set(AerialSet.all.map(\.subcategoryID)))
	}

	@Test func combinesOnlySetsInTheCatalog() async throws {
		let sandbox = try Sandbox(catalog: CatalogFixture().without(.goldenGate), videos: Self.allVideos)
		let result = try await sandbox.run("enable")
		#expect(result.status == 0)
		#expect(result.lines.contains("Combined: \(Self.tahoe.slug)"))
		#expect(!result.output.contains(Self.gg.displayName) && !result.error.contains(Self.gg.displayName))
		#expect(sandbox.combinedSetIDs == [Self.tahoe.subcategoryID])
		#expect(try sandbox.installer().mergePlan().readiness[.goldenGate] == .notInCatalog)
		#expect(try sandbox.snapshot().sets.map(\.subcategoryID) == [Self.tahoe.subcategoryID])
	}

	@Test(arguments: LayoutChange.allCases)
	func combinesTheOtherSetWhenOneHasAnUnexpectedLayout(_ change: LayoutChange) async throws {
		let source = change.apply(to: CatalogFixture(), .tahoe)
		let sandbox = try Sandbox(catalog: source, videos: Self.allVideos)
		let result = try await sandbox.run("enable")
		#expect(result.status == 0, "\(result.error)")
		#expect(sandbox.combinedSetIDs == [Self.gg.subcategoryID] && sandbox.anchors(of: Self.gg) == 4)
		let installed = try #require(sandbox.installedCatalog)
		#expect(JSONTree.equal(CatalogFixture.entries(of: .tahoe, in: installed.root), CatalogFixture.entries(of: .tahoe, in: source.root)))
		#expect(sandbox.actions == Sandbox.turnOnActions)
		#expect(try sandbox.snapshot().sets.first { $0.subcategoryID == Self.tahoe.subcategoryID }?.readiness == .unexpectedLayout)
	}

	@Test func leavesSetsAppleShipsAsApple() async throws {
		for (shipped, ours) in [(Self.tahoe, Self.gg), (Self.gg, Self.tahoe)] {
			let source = CatalogFixture().shippingSolar([shipped])
			let sandbox = try Sandbox(index: IndexFixture.combined, catalog: source, videos: Self.allVideos)
			let result = try await sandbox.run("enable")
			#expect(result.status == 0)
			#expect(result.lines.contains("Combined: \(ours.slug)") && result.lines.contains("Apple already combines \(shipped.displayName) itself"))
			#expect(sandbox.anchors(of: ours) == 4 && sandbox.installedCatalog?.combines(subcategoryID: ours.subcategoryID) == true)
			let installed = try #require(sandbox.installedCatalog)
			#expect(JSONTree.equal(CatalogFixture.entries(of: shipped, in: installed.root), CatalogFixture.entries(of: shipped, in: source.root)))
			#expect(sandbox.actions == Sandbox.turnOnActions)
		}
		let bundled = try Sandbox(videos: Self.allVideos)
		try CatalogFixture().shippingSolar([.tahoe]).data.write(to: bundled.bundledCatalog)
		let result = try await bundled.run("enable")
		#expect(result.status == 0 && result.lines.contains("Combined: \(Self.gg.slug)"))
		#expect(bundled.combinedSetIDs == [Self.gg.subcategoryID])
	}
}
