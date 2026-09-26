import Foundation
import os

nonisolated final class Log: @unchecked Sendable {
	private static let system = Logger(subsystem: "dev.hloth.native-aerials", category: "engine")
	private static let warnedOnce = OSAllocatedUnfairLock(initialState: Set<String>())

	private let lock = NSLock()
	private var storedNotices: [String] = []
	private let echoes: Bool

	init(echoes: Bool) {
		self.echoes = echoes
	}

	var notices: [String] {
		lock.withLock { storedNotices }
	}

	func note(_ line: String, notice: String? = nil) {
		record(notice)
		if !line.isEmpty {
			Self.system.info("\(line, privacy: .public)")
		}
		if echoes {
			print(line)
		}
	}

	func warn(_ line: String, notice: String? = nil) {
		record(notice)
		Self.system.error("\(line, privacy: .public)")
		if echoes {
			FileHandle.standardError.write(Data("warning: \(line)\n".utf8))
		}
	}

	func warnOnce(_ line: String) {
		if Self.warnedOnce.withLock({ $0.insert(line).inserted }) {
			warn(line)
		}
	}

	private func record(_ notice: String?) {
		guard let notice else {
			return
		}
		lock.withLock { storedNotices.append(notice) }
	}
}
