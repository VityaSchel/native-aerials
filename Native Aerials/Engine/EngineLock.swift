import Foundation

nonisolated enum EngineLock {
	static let busySummary = "Native Aerials is busy in the background. Try again in a moment."

	static func withLock<T>(_ file: URL, timeout: TimeInterval, _ body: () throws -> T) throws -> T {
		let descriptor = try acquire(file, timeout: timeout)
		defer { close(descriptor) }
		return try body()
	}

	private static func acquire(_ file: URL, timeout: TimeInterval) throws -> Int32 {
		try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
		let deadline = Date.now.addingTimeInterval(timeout)
		while true {
			let descriptor = open(file.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
			guard descriptor >= 0 else {
				throw InstallerError("cannot open \(file.path): \(String(cString: strerror(errno)))", summary: "Couldn’t make the change. Try again.")
			}
			if flock(descriptor, LOCK_EX | LOCK_NB) == 0 && isStillNamed(file, by: descriptor) {
				return descriptor
			}
			close(descriptor)
			guard Date.now < deadline else {
				throw InstallerError("another Native Aerials process has been busy for \(Int(timeout)) s", summary: busySummary)
			}
			Thread.sleep(forTimeInterval: 0.1)
		}
	}

	private static func isStillNamed(_ file: URL, by descriptor: Int32) -> Bool {
		var held = stat()
		var named = stat()
		return fstat(descriptor, &held) == 0 && stat(file.path, &named) == 0
			&& held.st_dev == named.st_dev && held.st_ino == named.st_ino
	}
}
