import Foundation

nonisolated enum CommandLineTool {
	private static let commands: Set<String> = ["enable", "disable", "status", "sync", "select", "upgrade", AgentJob.argument, AgentJob.reloadArgument]
	private static let informational: Set<String> = ["--version", "version", "--help", "-h", "help"]

	static func handles(_ arguments: [String]) -> Bool {
		let rest = arguments.dropFirst()
		guard let first = rest.first else {
			return false
		}
		return !first.hasPrefix("-") || rest.contains {
			commands.contains($0) || informational.contains($0) || $0 == DryRun.option || $0 == AgentJob.handedOffArgument
		}
	}

	static func run(_ arguments: [String]) -> Int32 {
		var command: String?
		var operand: String?
		var dryRunPath: String?
		var handedOff = false
		var remaining = Array(arguments.dropFirst())
		while !remaining.isEmpty {
			let argument = remaining.removeFirst()
			switch argument {
			case DryRun.option:
				if let next = remaining.first, !next.hasPrefix("--"), command != nil || !commands.contains(next) {
					dryRunPath = remaining.removeFirst()
				} else {
					dryRunPath = DryRun.environmentPath ?? FileManager.default.currentDirectoryPath + "/native-aerials-dry-run"
				}
			case "--version", "version":
				print("Native Aerials \(SystemInfo.appVersion)")
				return 0
			case "-h", "--help", "help":
				print(usage)
				return 0
			case AgentJob.handedOffArgument:
				handedOff = true
			case _ where command == nil && (commands.contains(argument) || !argument.hasPrefix("-")):
				command = argument
			case _ where ["select", "sync"].contains(command) && operand == nil && !argument.hasPrefix("-"):
				operand = argument
			default:
				return fail("unexpected argument \(argument)", status: 2)
			}
		}
		guard let command else {
			FileHandle.standardError.write(Data((usage + "\n").utf8))
			return 2
		}
		guard commands.contains(command) else {
			return fail("unknown command \(command)", status: 2)
		}
		return execute(command, operand: operand, handedOff: handedOff, dryRunPath: dryRunPath ?? DryRun.environmentPath)
	}

	private static func execute(_ command: String, operand: String?, handedOff: Bool, dryRunPath: String?) -> Int32 {
		guard !SystemInfo.isRoot else {
			return fail("run as your own user, not with sudo: wallpaper settings are per user")
		}
		do {
			let dryRun = try dryRunPath.map(DryRun.prepare)
			if let dryRun {
				print("[dry-run] writes go to \(dryRun.directory.path); the real system is only read")
			}
			let locations = Locations(dryRun: dryRun)
			let installer = Installer(locations: locations, log: Log(echoes: true))
			switch command {
			case "enable":
				try installer.locked { _ = try installer.enable() }
			case "disable":
				try installer.locked {
					try installer.disable(remembering: true)
					installer.removeAgent()
				}
			case "sync":
				let choice = operand.flatMap(AerialChoice.init(identifier:))
				guard operand == nil || choice != nil else {
					return fail("sync takes an optional set ID whose Automatic item it selects once the set is combined", status: 2)
				}
				try installer.locked {
					let outcome = try installer.sync(selecting: choice)
					if outcome.result == .turnedOff {
						installer.removeAgent()
					}
					print("sync: \(outcome.result.rawValue)")
				}
			case "select":
				guard let operand, let choice = AerialChoice(identifier: operand) else {
					return fail("select needs a video's asset ID, or a set ID for Automatic", status: 2)
				}
				let outcome = try installer.locked { try installer.select(choice) }
				print("select: \(outcome.changed ? "changed" : "unchanged")\(outcome.downloadFollows ? ", macOS downloads the missing videos in the background" : "")")
			case "upgrade":
				if installer.hasArtifactsToUpgrade {
					try installer.locked { installer.upgradeOwnArtifacts() }
				}
			case AgentJob.argument:
				return installer.runAgent(handedOff: handedOff, locator: AppLocator(locations: locations))
			case AgentJob.reloadArgument:
				return installer.reloadAgentJob()
			default:
				WallpaperSnapshot(installer).reportLines.forEach { print($0) }
			}
			return 0
		} catch {
			return fail(error.localizedDescription)
		}
	}

	private static func fail(_ message: String, status: Int32 = 1) -> Int32 {
		FileHandle.standardError.write(Data("native-aerials: \(message)\n".utf8))
		return status
	}

	private static let usage = """
		usage: "Native Aerials" <enable|disable|status> [--dry-run DIR]
		       "Native Aerials" sync [set ID] [--dry-run DIR]
		       "Native Aerials" select <asset ID | set ID> [--dry-run DIR]

		  enable     combine every set whose four videos are on disk into one wallpaper with an
		             Automatic option, restart the wallpaper processes, add the background helper
		             and open Wallpaper settings; works only from /Applications or ~/Applications
		  disable    undo everything and put a single-video wallpaper choice back; the next enable
		             brings Automatic back wherever that video is still the choice
		  sync       combine sets that became complete, split sets that lost a video, rebuild after
		             macOS updates (what the background helper runs); with a set ID, also pick
		             that set's Automatic item in the same restart
		  select     set the wallpaper on every desktop; a set ID picks its combined Automatic item.
		             A single video must be on disk: macOS downloads an aerial only when it is
		             picked in System Settings > Wallpaper
		  status     report what is installed, including every set ID and asset ID, read-only

		options:
		  --dry-run [DIR]   write nothing outside DIR: catalog, preferences, Index.plist, the helper
		                    and LaunchAgents go there; killall, open and launchctl are logged instead
		  --version, --help

		to try the window the same way:
		  open --env NATIVE_AERIALS_DRY_RUN=DIR "Native Aerials.app"
		"""
}
