import SwiftUI

let size: CGFloat = 1024
let lean: CGFloat = 0.2
let radius: CGFloat = 0.26 * size
let bleed: CGFloat = 256
let panes = [("morning", "#FF9F87"), ("day", "#D8F08C"), ("evening", "#5B8CFF"), ("night", "#3E2C7A")]
let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = CommandLine.arguments.dropFirst().first.map { URL(filePath: $0) } ?? repository.appending(path: "Native Aerials/AppIcon.icon/Assets")

func svgNumber(_ value: CGFloat) -> String {
	let fixed = String(format: "%.3f", Double(value))
	return String(fixed.reversed().drop { $0 == "0" }.drop { $0 == "." }.reversed())
}

func svgPoint(_ point: CGPoint) -> String { "\(svgNumber(point.x)) \(svgNumber(point.y))" }

func panePath(_ index: Int) -> Path {
	guard index > 0 else {
		return Path(CGRect(x: -bleed, y: -bleed, width: size + 2 * bleed, height: size + 2 * bleed))
	}
	let left = size * CGFloat(index) / CGFloat(panes.count)
	let rect = CGRect(x: left, y: 0, width: size + bleed - left, height: size)
	let rounded = UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius, bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous).path(in: rect)
	return rounded.applying(CGAffineTransform(a: 1, b: 0, c: -lean, d: 1, tx: size / 2 * lean, ty: 0))
}

func svgPathData(_ path: Path) -> String {
	var commands: [String] = []
	var current = CGPoint.zero
	path.forEach { element in
		switch element {
		case .move(let to):
			commands.append("M \(svgPoint(to))")
			current = to
		case .line(let to):
			commands.append("L \(svgPoint(to))")
			current = to
		case .quadCurve(let to, let control):
			commands.append("Q \(svgPoint(control)) \(svgPoint(to))")
			current = to
		case .curve(let to, let control1, let control2):
			if [to, control1, control2].contains(where: { svgPoint($0) != svgPoint(current) }) {
				commands.append("C \(svgPoint(control1)) \(svgPoint(control2)) \(svgPoint(to))")
			}
			current = to
		case .closeSubpath:
			commands.append("Z")
		}
	}
	return commands.joined(separator: " ")
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (index, (name, fill)) in panes.enumerated() {
	let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><path d="\#(svgPathData(panePath(index)))" fill="\#(fill)"/></svg>\#n"#
	try svg.write(to: output.appending(path: "\(name).svg"), atomically: true, encoding: .utf8)
}
