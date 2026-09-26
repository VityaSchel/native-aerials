import CoreServices
import Foundation

nonisolated struct SystemChange: OptionSet, Hashable, Sendable {
	let rawValue: Int

	static let videos = SystemChange(rawValue: 1 << 0)
	static let thumbnails = SystemChange(rawValue: 1 << 1)
	static let settings = SystemChange(rawValue: 1 << 2)
}

nonisolated enum SystemWatcher {
	private static let latency: TimeInterval = 0.3
	private static let quietPeriod: TimeInterval = 0.25

	static func changes(for locations: Locations) -> AsyncStream<SystemChange> {
		let (stream, continuation) = AsyncStream.makeStream(of: SystemChange.self, bufferingPolicy: .bufferingNewest(16))
		let classifier = ChangeClassifier(locations: locations)
		let events = FileEventStream(
			paths: classifier.watchedDirectories,
			latency: latency,
			quietPeriod: quietPeriod,
			classify: classifier.classify,
			deliver: { continuation.yield($0) }
		)
		guard let events else {
			continuation.finish()
			return stream
		}
		continuation.onTermination = { _ in
			events.stop()
		}
		return stream
	}
}

nonisolated struct ChangeClassifier: Sendable {
	let locations: Locations

	var watchedDirectories: [String] {
		var directories = [locations.realWallpaperRoot, locations.preferencesFile.deletingLastPathComponent(), locations.launchAgents]
		if let dryRun = locations.dryRun {
			directories.append(dryRun.directory)
		}
		directories.append(locations.videosDirectory)
		return Self.outermost(directories.map { SystemInfo.resolvedPath($0.path) ?? $0.path })
	}

	func classify(_ paths: [String]) -> SystemChange {
		let videos = locations.videosDirectory.path
		let thumbnails = locations.thumbnailsDirectory.path
		let catalogDirectories = [locations.customDirectory.path, locations.manifestDirectory.path]
		let spaces = locations.home.appending(path: "Library/Preferences/com.apple.spaces.plist")
		let settingsFiles = Set([locations.indexFile, locations.realIndexFile, locations.preferencesFile, spaces, AgentJob.file(in: locations.launchAgents)].map(\.path))
		var change: SystemChange = []
		for path in paths {
			if path == videos || (path.hasPrefix(videos + "/") && path.hasSuffix(".mov")) {
				change.insert(.videos)
			} else if path == thumbnails || path.hasPrefix(thumbnails + "/") {
				change.insert(.thumbnails)
			} else if settingsFiles.contains(path) || catalogDirectories.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
				change.insert(.settings)
			}
		}
		return change
	}

	private static func outermost(_ paths: [String]) -> [String] {
		let unique = Array(Set(paths)).sorted()
		return unique.filter { path in !unique.contains { $0 != path && path.hasPrefix($0 + "/") } }
	}
}

private nonisolated final class FileEventStream: @unchecked Sendable {
	private let queue = DispatchQueue(label: "dev.hloth.native-aerials.file-events", qos: .utility)
	private let quietPeriod: TimeInterval
	private let classify: @Sendable ([String]) -> SystemChange
	private let deliver: @Sendable (SystemChange) -> Void
	private var stream: FSEventStreamRef?
	private var pending: SystemChange = []
	private var pendingSince: DispatchTime?
	private var flush: DispatchWorkItem?

	init?(
		paths: [String],
		latency: TimeInterval,
		quietPeriod: TimeInterval,
		classify: @escaping @Sendable ([String]) -> SystemChange,
		deliver: @escaping @Sendable (SystemChange) -> Void
	) {
		self.quietPeriod = quietPeriod
		self.classify = classify
		self.deliver = deliver
		var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
		let flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot
		guard let stream = FSEventStreamCreate(
			kCFAllocatorDefault, Self.callback, &context, paths as CFArray,
			FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, FSEventStreamCreateFlags(flags)
		) else {
			return nil
		}
		self.stream = stream
		FSEventStreamSetDispatchQueue(stream, queue)
		guard FSEventStreamStart(stream) else {
			FSEventStreamInvalidate(stream)
			FSEventStreamRelease(stream)
			return nil
		}
	}

	func stop() {
		queue.async {
			self.flush?.cancel()
			guard let stream = self.stream else {
				return
			}
			self.stream = nil
			FSEventStreamStop(stream)
			FSEventStreamInvalidate(stream)
			FSEventStreamRelease(stream)
		}
	}

	private func receive(_ paths: [String]) {
		let change = classify(paths)
		guard stream != nil, !change.isEmpty else {
			return
		}
		pending.formUnion(change)
		let since = pendingSince ?? .now()
		pendingSince = since
		flush?.cancel()
		let item = DispatchWorkItem { [self] in
			let batch = pending
			pending = []
			pendingSince = nil
			deliver(batch)
		}
		flush = item
		queue.asyncAfter(deadline: min(.now() + quietPeriod, since + quietPeriod * 4), execute: item)
	}

	private static let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
		guard let info, count > 0, let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] else {
			return
		}
		Unmanaged<FileEventStream>.fromOpaque(info).takeUnretainedValue().receive(paths)
	}
}
