import Foundation

nonisolated enum DownloadMonitor {
	static let predicate = #"(process == "WallpaperAerialsExtension" AND subsystem == "com.apple.wallpaper" AND (category == "download" OR category == "aerial-assets")) OR (process == "WallpaperAgent" AND subsystem == "com.apple.wallpaper" AND category == "coordinator" AND eventMessage BEGINSWITH "User settings update intent")"#

	static func events() -> AsyncStream<DownloadEvent> {
		let (stream, continuation) = AsyncStream.makeStream(of: DownloadEvent.self, bufferingPolicy: .bufferingNewest(256))
		let reader = LogStreamReader(deliver: { continuation.yield($0) }, finish: { continuation.finish() })
		guard reader.start() else {
			continuation.finish()
			return stream
		}
		continuation.onTermination = { _ in
			reader.stop()
		}
		return stream
	}
}

private nonisolated final class LogStreamReader: @unchecked Sendable {
	private let process = Process()
	private let lock = NSLock()
	private let deliver: @Sendable (DownloadEvent) -> Void
	private let finish: @Sendable () -> Void
	private var buffer = Data()
	private var parser = DownloadLogParser()

	init(deliver: @escaping @Sendable (DownloadEvent) -> Void, finish: @escaping @Sendable () -> Void) {
		self.deliver = deliver
		self.finish = finish
	}

	func start() -> Bool {
		let pipe = Pipe()
		process.executableURL = URL(filePath: "/usr/bin/log")
		process.arguments = ["stream", "--style", "ndjson", "--level", "default", "--predicate", DownloadMonitor.predicate]
		process.standardOutput = pipe
		process.standardError = FileHandle.nullDevice
		pipe.fileHandleForReading.readabilityHandler = { [self] handle in
			let data = handle.availableData
			guard !data.isEmpty else {
				handle.readabilityHandler = nil
				finish()
				return
			}
			consume(data)
		}
		process.terminationHandler = { [finish] _ in
			finish()
		}
		do {
			try process.run()
			return true
		} catch {
			pipe.fileHandleForReading.readabilityHandler = nil
			return false
		}
	}

	func stop() {
		if process.isRunning {
			process.terminate()
		}
	}

	private func consume(_ data: Data) {
		let events = lock.withLock {
			buffer.append(data)
			var events: [DownloadEvent] = []
			while let newline = buffer.firstIndex(of: 0x0A) {
				let line = buffer[buffer.startIndex..<newline]
				buffer.removeSubrange(buffer.startIndex...newline)
				events += parser.events(inNDJSONLine: Data(line))
			}
			return events
		}
		events.forEach(deliver)
	}
}
