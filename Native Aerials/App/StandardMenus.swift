import SwiftUI

struct StandardMenus: Commands {
	var body: some Commands {
		CommandGroup(replacing: .toolbar) {}
		CommandGroup(replacing: .help) {}
	}
}
