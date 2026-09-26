import Foundation

nonisolated enum JSONTree {
	static func parse(_ data: Data) throws -> Any {
		try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
	}

	static func serialize(_ value: Any, pretty: Bool = true) throws -> Data {
		var options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
		if pretty {
			options.insert(.prettyPrinted)
		}
		let normalizedValue = normalized(value)
		guard JSONSerialization.isValidJSONObject([normalizedValue]) else {
			throw InstallerError("the aerial catalog holds a value that cannot be written as JSON", summary: InstallerError.unexpectedCatalogSummary)
		}
		return try JSONSerialization.data(withJSONObject: normalizedValue, options: options)
	}

	static func text(_ value: Any) -> String {
		guard let data = try? serialize(value, pretty: false) else {
			return "\(value)"
		}
		return String(decoding: data, as: UTF8.self)
	}

	static func isBoolean(_ value: Any?) -> Bool {
		guard let number = value as? NSNumber else {
			return false
		}
		return CFGetTypeID(number) == CFBooleanGetTypeID()
	}

	static func isTrue(_ value: Any?) -> Bool {
		isBoolean(value) && (value as? NSNumber)?.boolValue == true
	}

	static func isNull(_ value: Any?) -> Bool {
		value == nil || value is NSNull
	}

	private static func number(_ value: Any?) -> Double? {
		guard let number = value as? NSNumber, !isBoolean(number) else {
			return nil
		}
		return number.doubleValue
	}

	static func equal(_ lhs: Any?, _ rhs: Any?) -> Bool {
		if isNull(lhs) || isNull(rhs) {
			return isNull(lhs) && isNull(rhs)
		}
		if isBoolean(lhs) || isBoolean(rhs) {
			return isBoolean(lhs) && isBoolean(rhs) && isTrue(lhs) == isTrue(rhs)
		}
		if let left = number(lhs), let right = number(rhs) {
			return left == right
		}
		if let left = lhs as? String, let right = rhs as? String {
			return left == right
		}
		if let left = lhs as? [Any], let right = rhs as? [Any] {
			return left.count == right.count && zip(left, right).allSatisfy { equal($0, $1) }
		}
		if let left = lhs as? [String: Any], let right = rhs as? [String: Any] {
			return left.count == right.count && left.allSatisfy { key, value in
				right[key].map { equal(value, $0) } ?? false
			}
		}
		return false
	}

	static func isLess(_ lhs: Any?, _ rhs: Any?) -> Bool {
		let (left, right) = (rank(lhs), rank(rhs))
		if left != right {
			return left < right
		}
		if let left = number(lhs), let right = number(rhs) {
			return left < right
		}
		if let left = lhs as? String, let right = rhs as? String {
			return Array(left.unicodeScalars.map(\.value)).lexicographicallyPrecedes(right.unicodeScalars.map(\.value))
		}
		return false
	}

	private static func rank(_ value: Any?) -> Int {
		switch value {
		case _ where isNull(value): 0
		case _ where isBoolean(value): isTrue(value) ? 2 : 1
		case is NSNumber: 3
		case is String: 4
		case is [Any]: 5
		default: 6
		}
	}

	private static func isFractional(_ number: NSNumber) -> Bool {
		guard !isBoolean(number), number is NSDecimalNumber || ["d", "f"].contains(String(cString: number.objCType)) else {
			return false
		}
		let value = number.doubleValue
		return value.isFinite && value != value.rounded()
	}

	private static func normalized(_ value: Any) -> Any {
		switch value {
		case let dictionary as [String: Any]:
			return dictionary.mapValues(normalized)
		case let array as [Any]:
			return array.map(normalized)
		case let number as NSNumber where isFractional(number):
			let decimal = NSDecimalNumber(string: "\(number.doubleValue)", locale: Locale(identifier: "en_US_POSIX"))
			return Double(decimal.stringValue) == number.doubleValue ? decimal : number
		default:
			return value
		}
	}
}
