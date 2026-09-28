import AppKit

enum AppMover {
	static let destination: URL? = {
		#if DEBUG
		return nil
		#else
		let locations = Locations(dryRun: nil)
		guard DryRun.environmentPath == nil, !locations.allowsApp(at: SystemInfo.executablePath), let folder = writableFolder(of: locations) else {
			return nil
		}
		return folder.appending(path: "Native Aerials.app", directoryHint: .isDirectory)
		#endif
	}()

	static func offerMoveToApplications() {
		guard let target = destination else {
			return
		}
		NSApp.activate()
		let alert = NSAlert()
		if let version = AppLocator.info(of: target)?["CFBundleShortVersionString"] as? String {
			alert.messageText = "Replace Native Aerials \(version) in Applications?"
			alert.addButton(withTitle: "Replace")
		} else {
			alert.messageText = "Move Native Aerials to Applications?"
			alert.addButton(withTitle: "Move to Applications")
		}
		alert.informativeText = "Native Aerials turns on only from the Applications folder, where its background helper can keep your wallpaper in sync."
		alert.addButton(withTitle: "Cancel")
		guard alert.runModal() == .alertFirstButtonReturn else {
			NSApp.terminate(nil)
			return
		}
		Task {
			do {
				try move(Bundle.main.bundleURL, to: target)
				let configuration = NSWorkspace.OpenConfiguration()
				configuration.createsNewApplicationInstance = true
				NSApp.setActivationPolicy(.accessory)
				_ = try await NSWorkspace.shared.openApplication(at: target, configuration: configuration)
				NSApp.terminate(nil)
			} catch {
				NSAlert(error: error).runModal()
				NSApp.terminate(nil)
			}
		}
	}

	private static func writableFolder(of locations: Locations) -> URL? {
		let fileManager = FileManager.default
		return locations.applicationFolders?.map { URL(filePath: $0, directoryHint: .isDirectory) }.first { folder in
			fileManager.fileExists(atPath: folder.path)
				? fileManager.isWritableFile(atPath: folder.path)
				: fileManager.isWritableFile(atPath: folder.deletingLastPathComponent().path)
		}
	}

	private static func move(_ app: URL, to target: URL) throws {
		let fileManager = FileManager.default
		let folder = target.deletingLastPathComponent()
		let staged = folder.appending(path: ".\(target.lastPathComponent).new", directoryHint: .isDirectory)
		try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
		try? fileManager.removeItem(at: staged)
		var movedOriginal = false
		do {
			if fileManager.isDeletableFile(atPath: app.path) {
				try fileManager.moveItem(at: app, to: staged)
				movedOriginal = true
			} else {
				try fileManager.copyItem(at: app, to: staged)
			}
			let contents = (try? fileManager.subpathsOfDirectory(atPath: staged.path)) ?? []
			for path in [staged.path] + contents.map({ "\(staged.path)/\($0)" }) {
				removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW)
			}
			if AppLocator.info(of: target) != nil {
				try fileManager.trashItem(at: target, resultingItemURL: nil)
			}
			try fileManager.moveItem(at: staged, to: target)
		} catch {
			if movedOriginal {
				try? fileManager.moveItem(at: staged, to: app)
			} else {
				try? fileManager.removeItem(at: staged)
			}
			throw error
		}
	}
}
