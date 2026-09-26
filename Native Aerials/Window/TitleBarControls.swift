import SwiftUI

struct TitleBarControls: ToolbarContent {
	@Binding var isOn: Bool
	let isLoaded: Bool
	let isEnabled: Bool
	let isWorking: Bool

	var body: some ToolbarContent {
		ToolbarItem(placement: .primaryAction) {
			WorkingIndicator(isVisible: isWorking && isLoaded)
		}
		.sharedBackgroundVisibility(.hidden)
		ToolbarItem(placement: .primaryAction) {
			SunSwitch(isOn: $isOn, isLoaded: isLoaded, isEnabled: isEnabled)
				.padding(.trailing, 6)
		}
		.sharedBackgroundVisibility(.hidden)
	}
}

struct SunSwitch: View {
	@Binding var isOn: Bool
	let isLoaded: Bool
	let isEnabled: Bool

	var body: some View {
		ZStack {
			Toggle("Follow the sun", isOn: $isOn)
				.toggleStyle(.switch)
				.controlSize(.regular)
				.labelsHidden()
				.fixedSize()
				.disabled(!isEnabled)
				.opacity(isLoaded ? 1 : 0)
				.accessibilityHidden(!isLoaded)
			if !isLoaded {
				ProgressView()
					.controlSize(.small)
					.accessibilityLabel("Loading")
			}
		}
		.help("Combine each fully downloaded set into one wallpaper that follows the sun")
	}
}

struct WorkingIndicator: View {
	let isVisible: Bool

	var body: some View {
		ProgressView()
			.controlSize(.small)
			.opacity(isVisible ? 1 : 0)
			.accessibilityHidden(!isVisible)
			.accessibilityLabel("Working")
			.animation(.easeOut(duration: 0.2).delay(isVisible ? 0.3 : 0), value: isVisible)
	}
}
