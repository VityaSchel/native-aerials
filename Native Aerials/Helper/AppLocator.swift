import AppKit

nonisolated enum AppPresence: Equatable {
	case present(URL)
	case moved(URL)
	case unreachable(URL)
	case gone
}

nonisolated enum PathPresence: Equatable {
	case exists
	case missing
	case unknown

	init(_ path: String) {
		var info = stat()
		if lstat(path, &info) == 0 {
			self = .exists
		} else {
			self = errno == ENOENT || errno == ENOTDIR ? .missing : .unknown
		}
	}
}

nonisolated struct AppLocator {
	var gracePeriod: TimeInterval = 3
	var confirmationDelay: TimeInterval = 30
	var applicationFolders: [String]?
	var registeredCopies: () -> [URL] = {
		NSWorkspace.shared.urlsForApplications(withBundleIdentifier: AgentJob.bundleIdentifier)
	}

	init(locations: Locations) {
		applicationFolders = locations.applicationFolders
		guard locations.dryRun != nil else {
			return
		}
		let listed = locations.environment["NATIVE_AERIALS_REGISTERED_APPS"] ?? ""
		let copies = listed.split(separator: ":").map { URL(filePath: String($0), directoryHint: .isDirectory) }
		registeredCopies = { copies }
		confirmationDelay = locations.environment["NATIVE_AERIALS_CONFIRM_DELAY"].flatMap(TimeInterval.init) ?? confirmationDelay
	}

	func locate(_ record: AgentRecord) -> AppPresence {
		let found = search(record)
		guard found == .gone, confirmationDelay > 0 else {
			return found
		}
		Thread.sleep(forTimeInterval: confirmationDelay)
		return search(record)
	}

	static func isApproved(_ app: URL) -> Bool {
		let userApproved: UInt16 = 0x40
		let size = getxattr(app.path, "com.apple.quarantine", nil, 0, 0, 0)
		guard size >= 0 else {
			return errno == ENOATTR
		}
		var value = [UInt8](repeating: 0, count: size)
		let length = getxattr(app.path, "com.apple.quarantine", &value, size, 0, 0)
		guard length >= 0 else {
			return false
		}
		let flags = UInt16(String(decoding: value.prefix(length).prefix { $0 != UInt8(ascii: ";") }, as: UTF8.self), radix: 16) ?? 0
		return flags & userApproved != 0
	}

	static func presence(ofCopy app: URL) -> PathPresence {
		switch PathPresence(app.path) {
		case .exists: PathPresence(app.appending(path: "Contents/Info.plist").path)
		case let other: other
		}
	}

	static func info(of app: URL) -> [String: Any]? {
		guard let data = try? Data(contentsOf: app.appending(path: "Contents/Info.plist")),
			let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
			info["CFBundleIdentifier"] as? String == AgentJob.bundleIdentifier
		else {
			return nil
		}
		return info
	}

	static func executable(of app: URL) -> URL? {
		(info(of: app)?["CFBundleExecutable"] as? String).map { app.appending(path: "Contents/MacOS/\($0)") }
	}

	private func search(_ record: AgentRecord) -> AppPresence {
		let recorded = URL(filePath: record.appPath, directoryHint: .isDirectory)
		if isEligible(recorded) {
			switch waitForCopy(at: recorded) {
			case .exists: return .present(recorded)
			case .unknown: return .unreachable(recorded)
			case .missing: break
			}
		}
		var unreadable: URL?
		for candidate in [resolve(record.appBookmark)].compactMap({ $0 }) + registeredCopies() where isEligible(candidate) {
			switch Self.presence(ofCopy: candidate) {
			case .exists: return .moved(candidate)
			case .unknown: unreadable = unreadable ?? candidate
			case .missing: continue
			}
		}
		if let unreadable {
			return .unreachable(unreadable)
		}
		return .gone
	}

	private func isEligible(_ app: URL) -> Bool {
		SystemInfo.isAllowedLocation(SystemInfo.resolvedPath(app.path) ?? app.path, applicationFolders: applicationFolders)
	}

	private func waitForCopy(at app: URL) -> PathPresence {
		let deadline = Date.now.addingTimeInterval(gracePeriod)
		while true {
			let presence = Self.presence(ofCopy: app)
			guard presence == .missing, Date.now < deadline else {
				return presence
			}
			Thread.sleep(forTimeInterval: 0.5)
		}
	}

	private func resolve(_ bookmark: Data?) -> URL? {
		guard let bookmark else {
			return nil
		}
		var isStale = false
		return try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &isStale)
	}
}
