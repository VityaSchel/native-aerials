import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let panes = ["morning", "day", "evening", "night"]
let side = 1024
let seed: UInt64 = 41
let glintProbability = 0.08
let minimumGlintAlpha = 0.04, maximumGlintAlpha = 0.35
let glintStrengthExponent = 2.5
let alphaLevels = 8.0

let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = CommandLine.arguments.dropFirst().first.map { URL(filePath: $0) } ?? repository.appending(path: "Native Aerials/AppIcon.icon/Assets")

var randomState = seed
func random() -> Double {
	randomState &+= 0x9E37_79B9_7F4A_7C15
	var z = randomState
	z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
	z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
	return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
}

func panePath(_ pane: String) -> CGPath {
	let svg = try! String(contentsOf: output.appending(path: "\(pane).svg"), encoding: .utf8)
	let tokens = svg.components(separatedBy: " d=\"")[1].components(separatedBy: "\"")[0].split(separator: " ").map(String.init)
	let path = CGMutablePath()
	var index = 0
	func point() -> CGPoint {
		defer { index += 2 }
		return CGPoint(x: Double(tokens[index])!, y: Double(tokens[index + 1])!)
	}
	while index < tokens.count {
		let command = tokens[index]
		index += 1
		switch command {
		case "M": path.move(to: point())
		case "L": path.addLine(to: point())
		case "C":
			let control1 = point(), control2 = point()
			path.addCurve(to: point(), control1: control1, control2: control2)
		case "Z": path.closeSubpath()
		default: fatalError("unsupported path command \(command)")
		}
	}
	return path
}

let iconShape = CGPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), cornerWidth: 236, cornerHeight: 236, transform: nil)

func visibleArea(of pane: String, coveredBy nextPane: String?) -> [UInt8] {
	var coverage = [UInt8](repeating: 0, count: side * side)
	coverage.withUnsafeMutableBytes { buffer in
		let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
		context.translateBy(x: 0, y: CGFloat(side))
		context.scaleBy(x: 1, y: -1)
		context.addPath(iconShape)
		context.clip()
		context.setFillColor(gray: 1, alpha: 1)
		context.addPath(panePath(pane))
		context.fillPath()
		if let nextPane {
			context.setBlendMode(.clear)
			context.addPath(panePath(nextPane))
			context.fillPath()
		}
	}
	return coverage
}

func satinPixels(over coverage: [UInt8]) -> [UInt8] {
	var pixels = [UInt8](repeating: 0, count: side * side * 4)
	for pixel in 0..<(side * side) {
		let chance = random(), strength = random()
		guard chance < glintProbability else { continue }
		let glint = minimumGlintAlpha + (maximumGlintAlpha - minimumGlintAlpha) * pow(strength, glintStrengthExponent)
		let alpha = (glint * (Double(coverage[pixel]) / 255) * alphaLevels).rounded() / alphaLevels
		let value = UInt8((alpha * 255).rounded())
		for channel in 0..<4 { pixels[pixel * 4 + channel] = value }
	}
	return pixels
}

func writePNG(_ pixels: [UInt8], to url: URL) {
	var pixels = pixels
	pixels.withUnsafeMutableBytes { buffer in
		let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.displayP3)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
		let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
		CGImageDestinationAddImage(destination, context.makeImage()!, nil)
		guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
	}
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (index, pane) in panes.enumerated() {
	let coverage = visibleArea(of: pane, coveredBy: panes.dropFirst(index + 1).first)
	writePNG(satinPixels(over: coverage), to: output.appending(path: "\(pane)-satin.png"))
}
