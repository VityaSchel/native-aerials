import Foundation
import Testing

struct SystemWatcherTests {
	final class Batches {
		var changes: [SystemChange] = []
	}

	static func write(_ text: String, to url: URL, atomically: Bool = true) throws {
		try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
		try Data(text.utf8).write(to: url, options: atomically ? .atomic : [])
	}

	@Test func classifiesAndDebouncesChanges() async throws {
		let sandbox = try Sandbox()
		let locations = try sandbox.locations()
		let batches = Batches()
		let changes = Engine(locations: locations).changes()
		let collector = Task {
			for await change in changes {
				batches.changes.append(change)
			}
		}
		try await Task.sleep(for: .milliseconds(700))
		for burst in 0..<5 {
			try Self.write("x", to: sandbox.videos.appending(path: "burst-\(burst).mov"), atomically: false)
		}
		#expect(await eventually(within: 10) { batches.changes.contains { $0.contains(.videos) } })
		try await Task.sleep(for: .seconds(1))
		let burstBatches = batches.changes.filter { $0.contains(.videos) }.count
		let unrelated = sandbox.directory.appending(path: "unrelated.txt")
		for url in [locations.indexFile, locations.indexFile, locations.catalogFile, locations.preferencesFile, AgentJob.file(in: locations.launchAgents), unrelated] {
			try Self.write("x", to: url)
		}
		try FileManager.default.removeItem(at: sandbox.videos.appending(path: "burst-0.mov"))
		#expect(await eventually(within: 10) { batches.changes.filter { $0.contains(.videos) }.count > burstBatches && batches.changes.contains { $0.contains(.settings) } })
		collector.cancel()
		await collector.value
		let union = batches.changes.reduce(into: SystemChange()) { $0.formUnion($1) }
		#expect(union.contains(.videos) && union.contains(.settings))
		#expect((1...2).contains(burstBatches), "\(burstBatches) batches for 5 writes")
		let classifier = ChangeClassifier(locations: locations)
		for url in [locations.indexFile, locations.catalogFile, locations.preferencesFile, AgentJob.file(in: locations.launchAgents)] {
			#expect(classifier.classify([url.path]) == .settings, "\(url.lastPathComponent)")
		}
		#expect(classifier.classify([sandbox.file(AerialSet.tahoe.day).path]) == .videos)
		#expect(classifier.classify([unrelated.path]).isEmpty)
	}
}
