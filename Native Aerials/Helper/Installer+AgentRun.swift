import Foundation

nonisolated extension Installer {
	func runAgent(handedOff: Bool, locator: AppLocator) -> Int32 {
		guard !handedOff, let record = helper.record else {
			return syncAsAgent()
		}
		switch locator.locate(record) {
		case .gone:
			return uninstallAsAgent()
		case .unreachable(let app):
			log.note("agent: \(app.path) can't be read right now; keeping everything as it is")
			return syncAsAgent()
		case .present(let app), .moved(let app):
			if !isRunning(from: app) {
				handOff(to: app)
			}
			return syncAsAgent()
		}
	}

	private func waitForFreshVideosToSettle() {
		let settle: TimeInterval = 3
		let files = (try? FileManager.default.contentsOfDirectory(at: locations.videosDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
		let newest = files.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
		guard let newest, locations.dryRun == nil else {
			return
		}
		let wait = settle - Date.now.timeIntervalSince(newest)
		if wait > 0 {
			Thread.sleep(forTimeInterval: min(wait, settle))
		}
	}

	private func syncAsAgent() -> Int32 {
		log.note("agent: checking from \(executablePath)")
		waitForFreshVideosToSettle()
		var reloads = false
		do {
			try locked {
				_ = try sync()
				switch installation() {
				case .enabled:
					reloads = refreshOwnFiles()
				case .partial:
					log.note("agent: Native Aerials is only partly set up; finishing the undo")
					try disable()
					retireSelf()
				case .off, .foreign:
					retireSelf()
				}
			}
		} catch {
			log.warn("agent: \(error.localizedDescription)")
			return InstallerError(describing: error).summary == EngineLock.busySummary ? 0 : 1
		}
		if reloads {
			scheduleReload()
		}
		return 0
	}

	private func uninstallAsAgent() -> Int32 {
		log.note("Native Aerials was removed; undoing its changes")
		do {
			try locked {
				try disable()
				retireSelf()
			}
		} catch {
			log.warn("agent: could not undo after the app was removed: \(error.localizedDescription)")
			return 1
		}
		return 0
	}

	private func refreshOwnFiles() -> Bool {
		guard canInstallAgent, let app = appBundle else {
			return false
		}
		do {
			try helper.install(from: URL(filePath: executablePath), app: app)
			return try agentJob(watching: app).write()
		} catch {
			log.warn("agent: could not refresh its own files: \(error.localizedDescription)")
			return false
		}
	}

	private func scheduleReload() {
		let process = Process()
		process.executableURL = helper.executable
		process.arguments = [AgentJob.reloadArgument] + (locations.dryRun?.arguments ?? [])
		process.standardInput = FileHandle.nullDevice
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		do {
			try process.run()
			log.note("agent: the app moved; reloading the background helper so launchd watches the new place")
		} catch {
			log.warn("agent: could not start the reload: \(error.localizedDescription)")
		}
	}

	func reloadAgentJob() -> Int32 {
		setsid()
		signal(SIGTERM, SIG_IGN)
		let parent = getppid()
		let deadline = Date.now.addingTimeInterval(5)
		while parent != 1 && getppid() == parent && Date.now < deadline {
			Thread.sleep(forTimeInterval: 0.05)
		}
		do {
			try locked {
				guard installation() == .enabled, isAgentInstalled else {
					return
				}
				let digest = SystemInfo.sha256(of: agentFile)
				try launch.reload(agentFile)
				try helper.recordLoadedJob(digest)
				log.note("agent: reloaded \(agentFile.path)")
			}
		} catch {
			log.warn("agent: could not reload \(agentFile.path): \(error.localizedDescription)")
			return 1
		}
		return 0
	}

	private func retireSelf() {
		try? FileManager.default.removeItem(at: agentFile)
		helper.remove()
		signal(SIGTERM, SIG_IGN)
		launch.bootout()
	}

	private func isRunning(from app: URL) -> Bool {
		guard let bundle = appBundle else {
			return false
		}
		return SystemInfo.resolvedPath(bundle.path) == SystemInfo.resolvedPath(app.path)
	}

	private func handOff(to app: URL) {
		guard AppLocator.isApproved(app), let executable = AppLocator.executable(of: app)?.path else {
			log.note("agent: \(app.path) can't be read or hasn't been opened yet; checking with the helper's own code")
			return
		}
		let arguments = [executable, AgentJob.argument, AgentJob.handedOffArgument] + (locations.dryRun?.arguments ?? [])
		var pointers = arguments.map { strdup($0) } + [nil]
		execv(executable, &pointers)
		pointers.forEach { free($0) }
		log.warn("agent: could not hand over to \(executable): \(String(cString: strerror(errno)))")
	}
}
