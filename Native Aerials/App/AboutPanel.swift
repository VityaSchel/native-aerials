import AppKit

enum AboutPanel {
	static let repository = URL(string: "https://git.hloth.dev/hloth/native-aerials")!
	static let license = repository.appending(path: "src/branch/main/LICENSE")

	static func show() {
		NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
	}

	private static var credits: NSAttributedString {
		let links = [("Source Code", repository), ("MIT License", license)]
		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = .center
		let attributes: [NSAttributedString.Key: Any] = [
			.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
			.foregroundColor: NSColor.secondaryLabelColor,
			.paragraphStyle: paragraph,
		]
		let text = NSMutableAttributedString(string: links.map(\.0).joined(separator: "  ·  "), attributes: attributes)
		for (title, url) in links {
			text.addAttribute(.link, value: url, range: (text.string as NSString).range(of: title))
		}
		return text
	}
}
