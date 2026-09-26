import Foundation

nonisolated extension Installer {
	@discardableResult
	func removeDownload(of choice: AerialChoice, keeping pinned: Set<String> = []) throws -> [String] {
		let targets = try removalTargets(of: choice)
		let index = store.hasIndex ? try store.readIndex().inUse(spaces: locations.liveSpaceIDs, includingRecent: true) : nil
		guard index?.shufflesAerials(categoryIDs: sourceCatalog()?.categoryIDs ?? []) != true else {
			throw InstallerError(
				"an aerial shuffle is a saved wallpaper choice and may be playing \(choice), so its download was kept",
				summary: "An aerial shuffle is in use as a wallpaper, so the download of \(choice) was kept."
			)
		}
		let protected = AerialSet.addingVideos(ofSetsIn: pinned.union(index?.choiceAssetIDs ?? []))
		guard !protected.contains(choice.assetID), !targets.contains(where: protected.contains) else {
			throw InstallerError(
				"\(choice) is a saved wallpaper choice, so its download was kept",
				summary: "\(choice) is in use as a wallpaper, so its download was kept."
			)
		}
		for id in targets {
			try removeVideo(id)
		}
		return targets
	}

	private func removalTargets(of choice: AerialChoice) throws -> [String] {
		guard let set = choice.set else {
			throw InstallerError("\(choice.assetID) is not an aerial video or set Native Aerials knows", summary: "Couldn’t remove that download.")
		}
		guard choice.assetID != AerialSet.systemDefaultAssetID else {
			throw InstallerError(
				"\(choice) is macOS's default aerial and stays downloaded",
				summary: "\(choice) is macOS’s default aerial, so it stays downloaded."
			)
		}
		let candidates = if case .video(let id) = choice { [id] } else { set.assetIDs }
		let targets = candidates.filter { $0 != AerialSet.systemDefaultAssetID && locations.isDownloaded(assetID: $0) }
		guard !targets.isEmpty else {
			throw InstallerError("\(choice) has no download to remove", summary: "\(choice) has no download to remove.")
		}
		return targets
	}

	private func removeVideo(_ id: String) throws {
		let name = AerialSet.displayName(forAssetID: id)
		let directory = SystemInfo.resolvedPath(locations.videosDirectory.path) ?? locations.videosDirectory.path
		let file = URL(filePath: directory, directoryHint: .isDirectory).appending(path: "\(id).mov")
		let summary = "Couldn’t remove the download of \(name)."
		var info = stat()
		guard lstat(file.path, &info) == 0 else {
			guard errno == ENOENT else {
				throw InstallerError("cannot inspect \(file.path): \(String(cString: strerror(errno)))", summary: summary)
			}
			return
		}
		guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_size > 0 else {
			throw InstallerError("\(file.path) is not a video file of yours, so it was left alone", summary: summary)
		}
		if let dryRun = locations.dryRun {
			dryRun.record("remove-download \(file.path)")
			guard file.path.hasPrefix(dryRun.directory.path + "/") else {
				log.note("[dry-run] would remove the download of \(name) (\(file.path))")
				return
			}
		}
		do {
			try FileManager.default.removeItem(at: file)
		} catch let error as CocoaError where error.code == .fileNoSuchFile {
			return
		} catch {
			throw InstallerError("cannot remove \(file.path): \(error.localizedDescription)", summary: summary)
		}
		log.note("removed the download of \(name) (\(file.path))")
	}
}
