import Foundation
import Testing

nonisolated struct AutomaticRestoreTests {
	static let gg = AerialSet.goldenGate
	static let tahoe = AerialSet.tahoe
	static let allVideos = AerialSet.all.flatMap(\.videos)
	static let everyDesktop = IndexFixture.desktopCount
	static let live = IndexFixture.liveCount
	static let dead = IndexFixture.deadCount

	static func turnedOffFromGoldenGateAutomatic(_ videos: [AerialVideo] = allVideos, environment: [String: String] = [:]) async throws -> Sandbox {
		let sandbox = try Sandbox(videos: videos)
		sandbox.environment.merge(environment) { $1 }
		#expect(try await sandbox.run("enable").status == 0)
		#expect(try await sandbox.run("select", gg.subcategoryID).status == 0)
		#expect(try await sandbox.run("disable").status == 0)
		return sandbox
	}

	@Test func bringsAutomaticBackOnLiveDesktops() async throws {
		let sandbox = try await Self.turnedOffFromGoldenGateAutomatic()
		#expect(try sandbox.desktops == .init(Self.everyDesktop, [Self.gg.day.assetID]))
		let record = try #require(sandbox.record)
		#expect(record.slots.count == Self.live && record.slots.allSatisfy { $0.automatic == Self.gg.subcategoryID && $0.video == Self.gg.day.assetID })
		#expect(Set(record.slots.filter { $0.path.first == "Spaces" }.map { $0.path[1] }) == [IndexFixture.liveSpace])
		#expect(sandbox.contents(of: sandbox.paths.supportDirectory) == [sandbox.paths.automaticRecordFile.lastPathComponent])
		#expect(!sandbox.exists(sandbox.agentFile) && !sandbox.exists(sandbox.paths.customDirectory))
		#expect(sandbox.rawActions.filter { $0.hasPrefix("launchctl ") } == [sandbox.ownBootout])
		#expect(sandbox.contents(of: sandbox.paths.indexFile.deletingLastPathComponent()) == ["Index.plist"])
		let recorded = sandbox.digest(sandbox.paths.automaticRecordFile)
		try await sandbox.run("disable")
		#expect(sandbox.digest(sandbox.paths.automaticRecordFile) == recorded)
		let on = try await sandbox.run("enable")
		#expect(try sandbox.liveDesktops == .init(Self.live, [Self.gg.subcategoryID]))
		#expect(try sandbox.deadDesktops == .init(Self.dead, [Self.gg.day.assetID]))
		#expect(sandbox.actions == Sandbox.turnOnRestoringActions)
		#expect(sandbox.record == nil && FileManager.default.isExecutableFile(atPath: sandbox.helper.path))
		#expect(on.output.contains("\(Self.gg.day.name) -> \(Self.gg.combinedName) again"))
		let snapshot = try sandbox.snapshot()
		#expect(snapshot.desktopChoice == .automatic(Self.gg.subcategoryID))
		let set = snapshot.sets.first { $0.subcategoryID == Self.gg.subcategoryID }
		#expect(set?.isMerged == true && set?.isMergedByApple == false && set?.isSelected == true)
		try await sandbox.run("enable")
		#expect(sandbox.rawActions.isEmpty)
		#expect(try sandbox.liveDesktops == .init(Self.live, [Self.gg.subcategoryID]) && sandbox.deadDesktops == .init(Self.dead, [Self.gg.day.assetID]))
	}

	@Test func keepsWhatTheUserPickedWhileOff() async throws {
		let sandbox = try await Self.turnedOffFromGoldenGateAutomatic()
		try sandbox.editIndex { IndexFixture.repainting($0, where: { $0.first == "SystemDefault" }, with: IndexFixture.choice(Self.tahoe.night.assetID)) }
		try await sandbox.run("enable")
		#expect(try sandbox.liveDesktops == .init(Self.live, [Self.gg.subcategoryID, Self.tahoe.night.assetID]))
		#expect(try sandbox.deadDesktops == .init(Self.dead, [Self.gg.day.assetID]))
		#expect(WallpaperIndex(root: try sandbox.indexRoot).choiceAssetID(at: ["SystemDefault", "Linked", "Content", "Choices", "0"]) == Self.tahoe.night.assetID)
		try await sandbox.run("disable")
		try await sandbox.run("select", Self.tahoe.night.assetID)
		try await sandbox.run("enable")
		#expect(try sandbox.desktops == .init(Self.everyDesktop, [Self.tahoe.night.assetID]))
		#expect(sandbox.actions == Sandbox.turnOnActions && sandbox.record == nil)
	}

	@Test func keepsTheVideoWhenTheSetCannotBeCombined() async throws {
		let sandbox = try await Self.turnedOffFromGoldenGateAutomatic()
		try sandbox.markDownloading([Self.tahoe.day.assetID])
		#expect(try await sandbox.run("enable").status == 1 && sandbox.record != nil)
		sandbox.clearDownloads()
		sandbox.remove([Self.gg.night])
		try await sandbox.run("enable")
		#expect(sandbox.combinedSetIDs == [Self.tahoe.subcategoryID])
		#expect(try sandbox.desktops == .init(Self.everyDesktop, [Self.gg.day.assetID]))
		#expect(sandbox.actions == Sandbox.turnOnActions && sandbox.record == nil)
		sandbox.place([Self.gg.night])
		try await sandbox.run("sync")
		#expect(sandbox.combinedSetIDs == Set(AerialSet.all.map(\.subcategoryID)))
		#expect(try sandbox.desktops == .init(Self.everyDesktop, [Self.gg.day.assetID]))
	}

	@Test func forgetsAutomaticWhenSwitchedOffOrSteppingAside() async throws {
		let reordered = try Sandbox(videos: Self.allVideos)
		try await reordered.run("enable")
		try await reordered.run("select", Self.gg.subcategoryID)
		let layout = try reordered.write(CatalogFixture().reorderedAssets(.tahoe), named: "reordered")
		#expect(try await reordered.run(["sync"], environment: ["NATIVE_AERIALS_MANIFEST": layout.path]).lines.contains("sync: turned-off"))
		#expect(try reordered.desktops == .init(Self.everyDesktop, [Self.gg.day.assetID]) && !reordered.exists(reordered.paths.supportDirectory))
		try await reordered.run("enable")
		#expect(try reordered.desktops == .init(Self.everyDesktop, [Self.gg.day.assetID]))

		let aside = try Sandbox(videos: Self.allVideos)
		try await aside.run("enable")
		try await aside.run("select", Self.gg.subcategoryID)
		let apple = try aside.write(CatalogFixture().shippingSolar(AerialSet.all), named: "apple")
		#expect(try await aside.run(["sync"], environment: ["NATIVE_AERIALS_MANIFEST": apple.path]).lines.contains("sync: turned-off"))
		#expect(try aside.desktops == .init(Self.everyDesktop, [Self.gg.subcategoryID]) && !aside.exists(aside.paths.supportDirectory))

		let off = try await Self.turnedOffFromGoldenGateAutomatic()
		let offApple = try off.write(CatalogFixture().shippingSolar(AerialSet.all), named: "apple")
		#expect(try await off.run(["enable"], environment: ["NATIVE_AERIALS_MANIFEST": offApple.path]).output.contains("Removing Native Aerials"))
		#expect(try off.desktops == .init(Self.everyDesktop, [Self.gg.day.assetID]) && !off.exists(off.paths.supportDirectory))
	}

	@Test func forgetsAutomaticWhenTheVideoIsPickedAgain() async throws {
		let sandbox = try await Self.turnedOffFromGoldenGateAutomatic()
		#expect(try await sandbox.run("select", Self.gg.day.assetID).output.contains("already the wallpaper everywhere"))
		#expect(sandbox.record == nil)
		try await sandbox.run("enable")
		#expect(try sandbox.desktops == .init(Self.everyDesktop, [Self.gg.day.assetID]) && sandbox.actions == Sandbox.turnOnActions)
	}

	@Test func bringsAutomaticBackForAnotherVideoOfTheSameSet() async throws {
		let sandbox = try await Self.turnedOffFromGoldenGateAutomatic()
		try sandbox.editIndex { IndexFixture.replacingChoices($0, of: Self.gg.day.assetID, with: Self.gg.morning.assetID) }
		try await sandbox.run("enable")
		#expect(try sandbox.liveDesktops == .init(Self.live, [Self.gg.subcategoryID]))
		#expect(try sandbox.deadDesktops == .init(Self.dead, [Self.gg.morning.assetID]))
		#expect(sandbox.actions == Sandbox.turnOnRestoringActions && sandbox.record == nil)
	}

	@Test func keepsAPhotoPickedWhileOff() async throws {
		let sandbox = try await Self.turnedOffFromGoldenGateAutomatic()
		try sandbox.repaint(dead: false, with: IndexFixture.photo)
		let liveParts = { try IndexFixture.desktopParts(of: sandbox.indexRoot).filter { !IndexFixture.isDead($0.path, live: sandbox.liveSpaces) }.map { $0.part["Content"] as? NSDictionary } }
		let before = try liveParts()
		let on = try await sandbox.run("enable")
		#expect(try sandbox.liveDesktops == .init(Self.live, [IndexFixture.none]) && liveParts() == before)
		#expect(try sandbox.deadDesktops == .init(Self.dead, [Self.gg.day.assetID]))
		#expect(sandbox.actions == Sandbox.turnOnActions && sandbox.record == nil && !on.output.contains(" again, as before turning off"))
		let snapshot = try sandbox.snapshot()
		#expect(snapshot.desktopChoice == nil && snapshot.selectedAssetID == nil)
		#expect(snapshot.sets.allSatisfy { !$0.isSelected && $0.variants.allSatisfy { !$0.isSelected } })
		#expect(snapshot.sets.first { $0.subcategoryID == Self.gg.subcategoryID }?.isMerged == true)
	}

	@Test func keepsAnotherAerialPickedWhileOff() async throws {
		let sandbox = try await Self.turnedOffFromGoldenGateAutomatic()
		try sandbox.repaint(dead: false, with: IndexFixture.choice(Self.tahoe.night.assetID))
		try await sandbox.run("enable")
		#expect(try sandbox.liveDesktops == .init(Self.live, [Self.tahoe.night.assetID]))
		#expect(try sandbox.deadDesktops == .init(Self.dead, [Self.gg.day.assetID]))
		#expect(sandbox.actions == Sandbox.turnOnActions && sandbox.record == nil)
		let snapshot = try sandbox.snapshot()
		#expect(snapshot.desktopChoice == .video(Self.tahoe.night.assetID))
		#expect(snapshot.sets.allSatisfy { !$0.isSelected })
		#expect(snapshot.sets.flatMap(\.variants).first { $0.assetID == Self.tahoe.night.assetID }?.isSelected == true)
	}

	@Test func neverRevivesDeletedSpaces() async throws {
		let sandbox = try Sandbox(videos: Self.allVideos)
		try await sandbox.run("enable")
		for lastUse in [IndexFixture.lastUse.addingTimeInterval(3600), Date.now.addingTimeInterval(-60)] {
			try sandbox.repaint(dead: true, with: IndexFixture.choice(Self.gg.subcategoryID), lastUse: lastUse)
			let snapshot = try sandbox.snapshot()
			#expect(snapshot.desktopChoice == .video(Self.tahoe.day.assetID))
			#expect(snapshot.sets.allSatisfy { !$0.isSelected })
		}
		try await sandbox.run("disable")
		#expect(try sandbox.deadDesktops == .init(Self.dead, [Self.gg.day.assetID]) && sandbox.liveDesktops == .init(Self.live, [Self.tahoe.day.assetID]))
		#expect(sandbox.record == nil)
		try await sandbox.run("enable")
		#expect(try sandbox.deadDesktops == .init(Self.dead, [Self.gg.day.assetID]) && sandbox.liveDesktops == .init(Self.live, [Self.tahoe.day.assetID]))
		#expect(sandbox.actions == Sandbox.turnOnActions)
	}

	@Test func restoresEveryDesktopWhenTheSpaceListIsUnreadable() async throws {
		let sandbox = try await Self.turnedOffFromGoldenGateAutomatic(environment: ["NATIVE_AERIALS_SPACES": ""])
		let record = try #require(sandbox.record)
		#expect(record.slots.count == Self.everyDesktop && record.slots.allSatisfy { $0.automatic == Self.gg.subcategoryID && $0.video == Self.gg.day.assetID })
		try await sandbox.run("enable")
		#expect(try sandbox.desktops == .init(Self.everyDesktop, [Self.gg.subcategoryID]))
	}
}
