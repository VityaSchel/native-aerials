import SwiftUI

struct StandardMenus: Commands {
	var body: some Commands {
		CommandGroup(replacing: .appInfo) {
			Button("About Native Aerials") {
				AboutPanel.show()
			}
		}
		CommandGroup(replacing: .toolbar) {}
		CommandGroup(replacing: .help) {}
	}
}
