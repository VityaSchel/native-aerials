import Foundation

nonisolated func eventually(within seconds: TimeInterval = 20, _ condition: () -> Bool) async -> Bool {
	let deadline = Date.now.addingTimeInterval(seconds)
	while !condition() {
		guard Date.now < deadline else {
			return false
		}
		try? await Task.sleep(for: .milliseconds(50))
	}
	return true
}
