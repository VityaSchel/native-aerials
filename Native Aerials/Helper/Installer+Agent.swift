import Foundation

nonisolated extension Installer {
	static let moveNotice = "Native Aerials turns on only from the Applications folder. Move it there and open it again."

	var helper: AgentHelper { AgentHelper(directory: locations.supportDirectory) }
	var launch: LaunchControl { LaunchControl(label: AgentJob.label, dryRun: locations.dryRun) }
	var agentFile: URL { AgentJob.file(in: locations.launchAgents) }
	var isAgentInstalled: Bool { FileManager.default.fileExists(atPath: agentFile.path) }

	var appBundle: URL? {
		let app = URL(filePath: executablePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		return app.pathExtension == "app" ? app : nil
	}

	var needsMoveToApplications: Bool {
		!locations.allowsApp(at: executablePath)
	}

	var canInstallAgent: Bool {
		appBundle != nil && !needsMoveToApplications
	}

	func agentJob(watching app: URL) -> AgentJob {
		AgentJob(
			directory: locations.launchAgents,
			helper: helper.executable,
			watchedPaths: [app.path, locations.videosDirectory.path, locations.manifestDirectory.path]
		)
	}

	func installAgent() throws {
		guard let app = appBundle, canInstallAgent else {
			log.warn(
				"Native Aerials runs from \(executablePath), which the background helper cannot watch, so the helper was not added; move the app to Applications and open it again",
				notice: Self.moveNotice
			)
			return
		}
		try helper.install(from: URL(filePath: executablePath), app: app)
		let job = agentJob(watching: app)
		let digest = try job.digest()
		if try job.write() || !launch.isLoaded || helper.record?.loadedJobDigest != digest {
			log.note("background helper: \(job.file.path)")
			try launch.reload(job.file)
			try helper.recordLoadedJob(digest)
		}
	}

	func installAgentReporting() {
		do {
			try installAgent()
		} catch {
			let summary = InstallerError(describing: error).summary
			log.warn("could not add the background helper \(agentFile.path): \(error.localizedDescription)", notice: summary)
		}
	}

	func removeAgent() {
		let existed = isAgentInstalled
		do {
			if existed {
				try FileManager.default.removeItem(at: agentFile)
				log.note("removed the background helper \(agentFile.path)")
			}
		} catch {
			log.warn(
				"could not remove the background helper \(agentFile.path): \(error.localizedDescription)",
				notice: "The background helper couldn’t be removed. \(error.localizedDescription)"
			)
		}
		if existed || launch.isLoaded {
			launch.bootout()
		}
		helper.remove()
	}

	var hasArtifactsToUpgrade: Bool {
		installation() == .enabled && canInstallAgent
	}

	func upgradeOwnArtifacts() {
		guard hasArtifactsToUpgrade else {
			return
		}
		installAgentReporting()
	}
}
