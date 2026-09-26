import Foundation

nonisolated enum Installation: Equatable, Sendable {
	case enabled
	case partial
	case foreign(String)
	case off
}

nonisolated enum SetReadiness: Equatable, Sendable {
	case ready
	case missingVideos([String])
	case appleProvides
	case unexpectedLayout
	case notInCatalog
}

nonisolated struct MergePlan {
	let sourceURL: URL
	let source: AerialCatalog?
	let readiness: [AerialSet: SetReadiness]

	var listedSets: [AerialSet] { AerialSet.all.filter { readiness[$0] != .notInCatalog } }
	var readySets: [AerialSet] { AerialSet.all.filter { readiness[$0] == .ready } }
	var appleSets: [AerialSet] { AerialSet.all.filter { readiness[$0] == .appleProvides } }
	var appleProvidesAll: Bool { appleSets.count == listedSets.count }
	var hasUnexpectedLayout: Bool { readiness.values.contains(.unexpectedLayout) }

	var missingAssetIDs: [String] {
		AerialSet.all.flatMap { set -> [String] in
			guard case .missingVideos(let ids) = readiness[set] else {
				return []
			}
			return ids
		}
	}

	func sourceCombines(_ set: AerialSet) -> Bool {
		source?.combines(subcategoryID: set.subcategoryID) == true
	}
}

nonisolated struct Installer {
	let locations: Locations
	let log: Log
	let executablePath = SystemInfo.executablePath

	var preferences: AerialPreferences { AerialPreferences(dryRun: locations.dryRun) }
	var store: WallpaperStore {
		WallpaperStore(locations: locations) { [self] in
			sourceCatalog()?.assetDictionaries.compactMap { $0["id"] as? String } ?? []
		}
	}
	var processes: WallpaperProcesses { WallpaperProcesses(dryRun: locations.dryRun, log: log) }

	func locked<T>(_ body: () throws -> T) throws -> T {
		try EngineLock.withLock(locations.lockFile, timeout: locations.lockTimeout, body)
	}

	func installation() -> Installation {
		let override = preferences.overridePath
		let hasCatalog = FileManager.default.fileExists(atPath: locations.catalogFile.path)
		let pointsAtOurs = override == locations.catalogTarget
		if hasCatalog && pointsAtOurs && preferences.forceLocal == "1" {
			return .enabled
		}
		if pointsAtOurs || hasCatalog {
			return .partial
		}
		if let override {
			return .foreign(override)
		}
		return .off
	}

	func preflight() throws {
		guard FileManager.default.fileExists(atPath: locations.bundledCatalog.path) else {
			throw InstallerError(
				"no aerial catalog at \(locations.bundledCatalog.path)",
				summary: "This Mac has no aerial wallpaper catalog."
			)
		}
		if let hook = SystemInfo.missingHook {
			log.warnOnce("this macOS build's wallpaper extension has no '\(hook)' string; Native Aerials may not work here")
		}
	}

	func checkOverrideIsOurs() throws {
		guard let override = preferences.overridePath, override != locations.catalogTarget else {
			return
		}
		let domain = AerialPreferences.domain
		throw InstallerError(
			"\(AerialPreferences.overrideKey) already points at \(override), which Native Aerials did not write. Remove that setup first: defaults delete \(domain) \(AerialPreferences.overrideKey); defaults delete \(domain) \(AerialPreferences.forceLocalKey)",
			summary: "Another tool already points aerial wallpapers at its own catalog (\(override)). Remove that setup first."
		)
	}

	func sourceCatalog() -> AerialCatalog? {
		if let downloaded = AerialCatalog.loadIfValid(locations.downloadedCatalog), downloaded.hasAssets {
			return downloaded
		}
		return AerialCatalog.loadIfValid(locations.bundledCatalog)
	}

	private func appleSolarSets(in source: AerialCatalog?) -> Set<AerialSet> {
		let bundled = source?.url.path == locations.bundledCatalog.path ? nil : AerialCatalog.loadIfValid(locations.bundledCatalog)
		let catalogs = [source, bundled].compactMap { $0 }
		return Set(AerialSet.all.filter { set in catalogs.contains { $0.shipsSolarData(for: set) } })
	}

	func missingVideos(of set: AerialSet) -> [String] {
		set.assetIDs.filter { !locations.isDownloaded(assetID: $0) }
	}

	func mergePlan() -> MergePlan {
		let source = sourceCatalog()
		let apple = appleSolarSets(in: source)
		let mentioned = Set(AerialSet.all.filter { source?.mentions($0) == true })
		var readiness: [AerialSet: SetReadiness] = [:]
		for set in AerialSet.all {
			let missing = missingVideos(of: set)
			if apple.contains(set) {
				readiness[set] = .appleProvides
			} else if !mentioned.isEmpty && !mentioned.contains(set) {
				readiness[set] = .notInCatalog
			} else if source.map({ $0.hasExpectedStructure && $0.hasExpectedLayout(of: set) }) != true {
				readiness[set] = .unexpectedLayout
			} else if !missing.isEmpty {
				readiness[set] = .missingVideos(missing)
			} else {
				readiness[set] = .ready
			}
		}
		return MergePlan(sourceURL: source?.url ?? locations.bundledCatalog, source: source, readiness: readiness)
	}

	func installedCatalog() -> AerialCatalog? {
		AerialCatalog.loadIfValid(locations.catalogFile)
	}

	func installedCatalogMatches(_ patched: PatchedCatalog) -> Bool {
		guard let installed = installedCatalog() else {
			return false
		}
		return JSONTree.equal(installed.root, patched.catalog.root)
	}

	func writeCatalog(_ data: Data) throws {
		let directory = locations.customDirectory
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let staging = directory.appending(path: ".entries.json.new")
		try data.write(to: staging)
		guard rename(staging.path, locations.catalogFile.path) == 0 else {
			try? FileManager.default.removeItem(at: staging)
			throw InstallerError("could not write \(locations.catalogFile.path): \(String(cString: strerror(errno)))", summary: InstallerError.saveSummary)
		}
	}

	func writeState(_ patched: PatchedCatalog, sourceURL: URL) throws {
		let state = InstallState.current(source: sourceURL, bundled: locations.bundledCatalog, catalog: locations.catalogFile, sets: patched.sets)
		if InstallState.load(from: locations.stateFile) != state {
			try state.save(to: locations.stateFile)
		}
	}

	func reportVideos(of sets: [AerialSet]) {
		for video in sets.flatMap(\.videos) {
			if locations.isDownloaded(assetID: video.assetID) {
				log.note("  \(video.name): on disk")
			} else {
				log.note("  \(video.name): not downloaded; download it in System Settings > Wallpaper (about 0.5 GB)")
			}
		}
	}
}
