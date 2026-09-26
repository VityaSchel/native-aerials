import CoreGraphics
import Foundation
import Testing

nonisolated struct HintPlacementTests {
	static let size = CGSize(width: 200, height: 38)
	static let main = CGRect(x: 0, y: 94, width: 1512, height: 855)
	static let above = CGRect(x: 0, y: 982, width: 1920, height: 1047)
	static let settings = CGRect(x: 487, y: 295, width: 740, height: 625)

	static func place(_ window: CGRect, _ screens: [CGRect] = [main]) -> CGPoint? {
		HintPlacement.origin(of: size, pointingInto: window, screens: screens)
	}

	@Test func convertsWindowBoundsToAppKit() {
		let convert = HintPlacement.appKitFrame(ofCGBounds:primaryHeight:)
		#expect(convert(CGRect(x: 487, y: 62, width: 740, height: 625), 982) == CGRect(x: 487, y: 295, width: 740, height: 625))
		#expect(convert(CGRect(x: 100, y: -900, width: 700, height: 500), 982) == CGRect(x: 100, y: 1382, width: 700, height: 500))
		#expect(convert(CGRect(x: -1000, y: 300, width: 600, height: 400), 982) == CGRect(x: -1000, y: 282, width: 600, height: 400))
		let samples = [CGRect(x: 3, y: -40, width: 10, height: 20), CGRect(x: -1440, y: 1200, width: 800, height: 600), CGRect(x: 0, y: 0, width: 1512, height: 982)]
		#expect(samples.allSatisfy { convert(convert($0, 1117), 1117) == $0 })
	}

	@Test func pointsIntoTheSettingsContent() {
		#expect(Self.place(Self.settings) == CGPoint(x: 877, y: 868))
		#expect(Self.place(CGRect(x: 1200, y: 295, width: 740, height: 625)) == CGPoint(x: 1304, y: 868))
		#expect(Self.place(CGRect(x: 1420, y: 295, width: 740, height: 625)) == nil)
		#expect(Self.place(CGRect(x: 487, y: 400, width: 740, height: 625))?.y == 911)
		#expect(Self.place(CGRect(x: 487, y: -600, width: 740, height: 625)) == nil)
		#expect(Self.place(Self.settings, []) == nil)
		#expect(Self.place(CGRect(x: 100, y: 1382, width: 700, height: 500), [Self.main, Self.above]) == CGPoint(x: 470, y: 1830))
	}

	@Test func staysOnScreenInsideTheWindow() {
		var placed = 0
		var skipped = 0
		var broken: [String] = []
		let screens = [Self.main, Self.above]
		for x in stride(from: -900.0, through: 1700, by: 37) {
			for y in stride(from: -700.0, through: 1100, by: 41) {
				let window = CGRect(x: x, y: y, width: 740, height: 625)
				guard let origin = Self.place(window, screens) else {
					skipped += 1
					continue
				}
				placed += 1
				let bubble = CGRect(origin: origin, size: Self.size)
				let trafficLights = CGRect(x: window.minX, y: window.maxY - HintPlacement.toolbarHeight, width: HintPlacement.trafficLightsWidth, height: HintPlacement.toolbarHeight)
				let tip = CGPoint(x: bubble.midX, y: bubble.minY)
				if !screens.contains(where: { $0.contains(bubble) }) || bubble.intersects(trafficLights) || !window.contains(tip)
					|| tip.y > window.maxY - HintPlacement.toolbarHeight || bubble.minX < window.minX || bubble.maxX > window.maxX {
					broken.append("\(window) -> \(bubble)")
				}
			}
		}
		#expect(broken.isEmpty, "\(broken.prefix(3))")
		#expect(placed > 500 && skipped > 100)
	}
}
