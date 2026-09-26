import Foundation
import Testing

struct WindowFlowTests {
	static let gg = AerialSet.goldenGate
	static let tahoe = AerialSet.tahoe

	static func opened(videos: [AerialVideo], showing assetID: String) async throws -> WindowHarness {
		let window = WindowHarness(try Sandbox(index: IndexFixture.everywhere(assetID), videos: videos))
		try await window.start()
		return window
	}

	@Test func opensWithoutChangesAndRefusesAnIncompleteTurnOn() async throws {
		let window = try await Self.opened(videos: [Self.tahoe.day, Self.gg.morning, Self.gg.day, Self.gg.night], showing: Self.tahoe.morning.assetID)
		defer { window.stop() }
		let sandbox = window.sandbox
		try await Task.sleep(for: .seconds(1.5))
		#expect(sandbox.rawActions.isEmpty)
		#expect(!window.state.switchIsOn && window.state.rows.allSatisfy { !$0.animatesMerge })
		#expect(window.status(Self.tahoe.morning) == .missing && window.tile(Self.tahoe.morning)?.isSelected == false)
		#expect(window.tile(Self.gg.morning)?.isSelected == true && window.status(Self.gg.day) == .ready)
		#expect(window.state.footnote?.text.hasPrefix("Dry run") == true)
		window.model.setEnabled(true)
		#expect(window.state.switchIsOn && window.state.isWorking)
		#expect(await window.until { !window.state.isWorking && !window.state.switchIsOn })
		#expect(Set(window.state.flashes.filter { $0.value > 0 }.keys) == Set([Self.tahoe.morning, Self.tahoe.evening, Self.tahoe.night, Self.gg.evening].map(\.assetID)))
		#expect(window.state.message == nil && window.state.footnote?.text.hasPrefix("Dry run") == true)
		#expect(sandbox.restarts == 0 && sandbox.rawActions == ["open wallpaper", "hint Download every video of a set first"])
	}

	@Test func followsDownloadsStartedInSettings() async throws {
		let window = try await Self.opened(videos: [Self.tahoe.day, Self.gg.morning, Self.gg.day, Self.gg.night], showing: Self.tahoe.morning.assetID)
		defer { window.stop() }
		let sandbox = window.sandbox
		let evening = Self.gg.evening
		let index = sandbox.digest(sandbox.paths.indexFile)
		let flashes = window.flashes(evening)
		window.model.choose(try #require(window.tile(evening)))
		#expect(window.flashes(evening) == flashes + 1)
		#expect(Array(sandbox.rawActions.suffix(2)) == window.hint(evening))
		try await Task.sleep(for: .seconds(1))
		#expect(sandbox.digest(sandbox.paths.indexFile) == index && sandbox.restarts == 0 && !window.state.isWorking)
		#expect(window.status(evening) == .missing)

		window.send(evening, .requested)
		#expect(window.status(evening) == .downloading(percent: 0) && window.marker == [evening.assetID])
		window.send(evening, .started(assetID: evening.assetID), .progress(40))
		#expect(window.status(evening) == .downloading(percent: 40))
		window.send(evening, .cancelling)
		#expect(window.status(evening) == .missing)
		window.send(evening, .failed(code: DownloadUpdate.cancelledCode), .failed(code: DownloadUpdate.cancelledCode), .ended)
		#expect(window.status(evening) == .missing && window.flashes(evening) == flashes + 1 && window.marker.isEmpty)

		window.send(evening, .requested, .started(assetID: evening.assetID), .progress(12), .failed(code: -1009))
		#expect(window.status(evening) == .missing && window.flashes(evening) == flashes + 2)
		window.send(evening, .failed(code: -1009), .ended)
		#expect(window.status(evening) == .missing && window.flashes(evening) == flashes + 2)

		window.send(evening, .requested, .progress(55))
		#expect(window.status(evening) == .downloading(percent: 55))
		window.model.receive(.extensionRestarted)
		#expect(window.status(evening) == .missing && window.marker.isEmpty)

		window.send(evening, .requested, .progress(30), .cancelling)
		window.send(Self.tahoe.night, .requested)
		#expect(window.status(evening) == .missing && window.status(Self.tahoe.night) == .downloading(percent: 0))
		window.send(Self.tahoe.night, .cancelling)
		#expect(window.status(Self.tahoe.night) == .missing)

		window.send(evening, .requested, .progress(99), .completed)
		#expect(window.status(evening) == .downloading(percent: 100) && window.marker.isEmpty)
		sandbox.place([evening])
		#expect(await window.until { window.status(evening) == .ready })
		window.send(evening, .ended)
		#expect(window.state.downloads.entries.isEmpty)
	}

	@Test func offersAndRemovesUnusedDownloads() async throws {
		let window = try await Self.opened(videos: [Self.tahoe.day] + Self.gg.videos, showing: Self.tahoe.morning.assetID)
		defer { window.stop() }
		let sandbox = window.sandbox
		#expect(window.tile(Self.tahoe.morning)?.canRemove == false && window.tile(Self.gg.morning)?.canRemove == false)
		#expect(window.tile(Self.gg.day)?.canRemove == true && window.tile(Self.tahoe.day)?.canRemove == true)
		window.model.receive(.selectionChanged(AerialSelection(ids: [Self.gg.day.assetID])))
		#expect(window.tile(Self.gg.day)?.canRemove == false && window.tile(Self.tahoe.day)?.canRemove == true)
		window.model.receive(.selectionChanged(AerialSelection(includesCategories: true)))
		#expect(window.state.rows.allSatisfy { !$0.canRemove && $0.tiles.allSatisfy { !$0.canRemove } })
		window.model.receive(.selectionChanged(AerialSelection()))
		#expect(window.tile(Self.gg.day)?.canRemove == true)

		let restarts = sandbox.restarts
		let index = sandbox.digest(sandbox.paths.indexFile)
		let flashes = window.flashes(Self.gg.day)
		window.model.removeDownload(.video(Self.gg.day.assetID))
		#expect(await window.until { !sandbox.exists(Self.gg.day) && window.status(Self.gg.day) == .missing && !window.state.isWorking })
		#expect(window.removals == ["remove-download \(sandbox.file(Self.gg.day).path)"])
		#expect(sandbox.restarts == restarts && sandbox.digest(sandbox.paths.indexFile) == index)
		#expect(window.flashes(Self.gg.day) == flashes && window.state.message == nil)

		window.model.removeDownload(.video(Self.gg.morning.assetID))
		#expect(await window.until { !window.state.isWorking && window.state.message != nil })
		#expect(sandbox.exists(Self.gg.morning) && window.removals.count == 1)
		window.model.choose(try #require(window.tile(Self.gg.night)))
		#expect(await window.until { !window.state.isWorking && window.selected == Self.gg.night.assetID })
		#expect(sandbox.restarts == restarts + 1 && window.tile(Self.gg.night)?.canRemove == false)
		window.model.removeDownload(.video(Self.gg.night.assetID))
		#expect(await window.until { !window.state.isWorking && window.state.message?.text.contains("in use as a wallpaper") == true })
		#expect(sandbox.exists(Self.gg.night))
		sandbox.place([Self.gg.day])
		#expect(await window.until { window.status(Self.gg.day) == .ready })
	}

	@Test func combinesAndSplitsSetsAsVideosComeAndGo() async throws {
		let window = try await Self.opened(videos: [Self.tahoe.day] + Self.gg.videos, showing: Self.gg.night.assetID)
		defer { window.stop() }
		let sandbox = window.sandbox
		let model = window.model
		model.setEnabled(true)
		#expect(await window.until { !window.state.isWorking && window.state.switchIsOn && window.row(Self.gg)?.isMerged == true })
		#expect(window.row(Self.tahoe)?.isMerged == false && window.row(Self.gg)?.animatesMerge == true)
		#expect(window.flashes(Self.tahoe.morning) == 1 && window.installedFootnote == nil)

		let afterOn = sandbox.restarts
		model.receive(.update(configuration: "ABCDEF12", .requested))
		model.receive(.update(configuration: "ABCDEF12", .progress(20)))
		#expect(window.marker == ["ABCDEF12"])
		sandbox.place([Self.tahoe.morning, Self.tahoe.evening, Self.tahoe.night])
		#expect(await window.until { Set(Self.tahoe.videos.map(\.assetID)).isSubset(of: window.state.onDiskAssetIDs) })
		try await Task.sleep(for: .seconds(AppModel.syncDelay + 1))
		#expect(sandbox.restarts == afterOn && window.row(Self.tahoe)?.isMerged == false && !window.state.isWorking)
		model.receive(.update(configuration: "ABCDEF12", .ended))
		#expect(await window.until { !window.state.isWorking && window.row(Self.tahoe)?.isMerged == true })
		#expect(sandbox.restarts == afterOn + 1 && window.selected == Self.gg.night.assetID)
		#expect(window.state.rows.allSatisfy { !$0.animatesMerge })

		#expect(window.row(Self.tahoe)?.canRemove == true && window.row(Self.gg)?.canRemove == false)
		let beforeRemoval = sandbox.restarts
		let tahoeFlashes = Self.tahoe.videos.map(window.flashes)
		model.removeDownload(.automatic(Self.tahoe.subcategoryID))
		#expect(await window.until { Self.tahoe.videos.allSatisfy { !sandbox.exists($0) } })
		#expect(await window.until { !window.state.isWorking && window.row(Self.tahoe)?.isMerged == false })
		#expect(sandbox.restarts == beforeRemoval + 1 && Self.tahoe.videos.map(window.flashes) == tahoeFlashes)
		#expect(window.selected == Self.gg.night.assetID)
		sandbox.place(Self.tahoe.videos)
		#expect(await window.until { !window.state.isWorking && window.row(Self.tahoe)?.isMerged == true })

		let dayFlashes = window.flashes(Self.gg.day)
		sandbox.remove([Self.gg.day])
		#expect(await window.until { !window.state.isWorking && window.row(Self.gg)?.isMerged == false })
		#expect(window.flashes(Self.gg.day) == dayFlashes + 1 && window.state.switchIsOn)

		let beforeClick = sandbox.restarts
		model.chooseMerged(try #require(window.row(Self.tahoe)))
		#expect(window.state.isWorking)
		model.open(.loginItems)
		#expect(window.state.isWorking && sandbox.rawActions.contains("open loginItems"))
		#expect(await window.until { !window.state.isWorking && window.selected == Self.tahoe.subcategoryID && window.row(Self.tahoe)?.isSelected == true })
		#expect(sandbox.restarts == beforeClick + 1 && window.row(Self.tahoe)?.canRemove == false)

		let beforeBackground = sandbox.restarts
		sandbox.place([Self.gg.day])
		#expect(await window.until { !window.state.isWorking && window.row(Self.gg)?.isMerged == true })
		#expect(window.selected == Self.tahoe.subcategoryID)
		model.choose(try #require(window.tile(Self.gg.day)))
		try await Task.sleep(for: .seconds(1))
		#expect(sandbox.restarts == beforeBackground + 1 && window.selected == Self.tahoe.subcategoryID && !window.state.isWorking)
		try await Task.sleep(for: .seconds(3))
		#expect(sandbox.restarts == beforeBackground + 1)

		sandbox.remove([Self.tahoe.night])
		#expect(await window.until { !window.state.isWorking && window.row(Self.tahoe)?.isMerged == false && window.state.switchIsOn })
		#expect(window.selected.flatMap(AerialSet.video(withAssetID:)).map(sandbox.exists) == true)
		sandbox.remove([Self.gg.night])
		#expect(await window.until { !window.state.isWorking && window.row(Self.gg)?.isMerged == false && window.state.snapshot?.isOn == true })
		#expect(window.state.switchIsOn && window.installedFootnote == nil)
		#expect(window.status(Self.tahoe.night) == .missing && window.status(Self.gg.night) == .missing)
		sandbox.place([Self.gg.night, Self.tahoe.night])
		#expect(await window.until { !window.state.isWorking && window.row(Self.tahoe)?.isMerged == true && window.row(Self.gg)?.isMerged == true })
	}

	@Test func quitWaitsForTheEngine() async throws {
		let sandbox = try Sandbox(videos: AerialSet.all.flatMap(\.videos))
		_ = try sandbox.engine().turnOn()
		sandbox.environment["NATIVE_AERIALS_LOCK_TIMEOUT"] = "30"
		let lock = open(sandbox.paths.lockFile.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
		defer { close(lock) }
		try #require(flock(lock, LOCK_EX) == 0)
		let window = WindowHarness(sandbox)
		try await window.start()
		defer { window.stop() }
		#expect(window.state.isLoaded && window.state.switchIsOn && window.state.rows.allSatisfy(\.isMerged))
		window.model.setEnabled(false)
		#expect(window.state.isWorking)
		var replied = false
		window.model.quitWhenIdle { replied = true }
		try await Task.sleep(for: .milliseconds(500))
		#expect(!replied && window.state.isWorking)
		flock(lock, LOCK_UN)
		#expect(await window.until { replied })
	}

	@Test func turningOffAndOnKeepsAutomatic() async throws {
		let sandbox = try Sandbox(videos: AerialSet.all.flatMap(\.videos))
		_ = try sandbox.engine().turnOn()
		_ = try sandbox.engine().select(.automatic(Self.gg.subcategoryID))
		let window = WindowHarness(sandbox)
		try await window.start()
		defer { window.stop() }
		let model = window.model
		model.setEnabled(false)
		#expect(await window.until { !window.state.isWorking && !window.state.switchIsOn && window.row(Self.tahoe)?.isMerged == false })
		#expect(window.selected == Self.gg.day.assetID)
		let beforeOn = sandbox.restarts
		model.setEnabled(true)
		#expect(await window.until { !window.state.isWorking && window.state.switchIsOn && window.selected == Self.gg.subcategoryID && window.row(Self.gg)?.isSelected == true })
		#expect(sandbox.restarts == beforeOn + 1)
		model.setEnabled(false)
		#expect(await window.until { !window.state.isWorking && !window.state.switchIsOn && window.selected == Self.gg.day.assetID })

		sandbox.remove([Self.tahoe.morning])
		#expect(await window.until { window.status(Self.tahoe.morning) == .missing })
		let restarts = sandbox.restarts
		let index = sandbox.digest(sandbox.paths.indexFile)
		model.choose(try #require(window.tile(Self.tahoe.morning)))
		try await Task.sleep(for: .seconds(1))
		#expect(sandbox.restarts == restarts && sandbox.digest(sandbox.paths.indexFile) == index)
		#expect(Array(sandbox.rawActions.suffix(2)) == window.hint(Self.tahoe.morning))

		window.send(Self.tahoe.morning, .requested, .progress(5))
		#expect(window.status(Self.tahoe.morning) == .downloading(percent: 5))
		#expect(window.state.downloads.deadline.map { abs($0.timeIntervalSinceNow - DownloadTracker.stallLimit) < 5 } == true)
		#expect(window.marker == [Self.tahoe.morning.assetID])
		model.stopWatchingDownloads()
		#expect(window.marker.isEmpty && !sandbox.exists(sandbox.paths.downloadActivityFile))
	}
}
