import Foundation

/// A measured value, split the way an instrument sets one: the integer part on
/// its own right-aligned lane, the separator and a single fraction digit in a
/// fixed lane beside it, and the unit left-aligned in a lane of its own.
///
/// Splitting the three is what stops a column of readings from reflowing when
/// `956,5 MB` becomes `1 GB` on the next sample.
struct Measure: Equatable {
    let integer: String
    /// Includes the locale's decimal separator. Empty when no fraction is shown.
    let fraction: String
    let unit: String
    let isMeasured: Bool

    static let unavailable = Measure(integer: "—", fraction: "", unit: "", isMeasured: false)

    /// What VoiceOver reads. Symbols become words.
    var spoken: String {
        guard isMeasured else { return "unavailable" }
        let number = integer + fraction
        switch unit {
        case "": return number
        case "%": return "\(number) percent"
        case "KB": return "\(number) kilobytes"
        case "MB": return "\(number) megabytes"
        case "GB": return "\(number) gigabytes"
        case "TB": return "\(number) terabytes"
        default: return "\(number) \(unit)"
        }
    }

    /// For tooltips, chips and menu titles, where lanes do not apply.
    var inline: String {
        guard isMeasured else { return "—" }
        if unit.isEmpty { return integer + fraction }
        if unit == "%" { return integer + fraction + unit }
        return "\(integer)\(fraction) \(unit)"
    }

    // MARK: Builders

    /// Memory uses binary units, matching Activity Monitor.
    static func memory(_ bytes: UInt64?, digits: Int = 1) -> Measure {
        guard let bytes else { return .unavailable }
        return scaled(Double(bytes), divisor: 1024, units: byteUnits, digits: digits)
    }

    /// Storage uses decimal units, matching Finder. These two genuinely differ
    /// and must not be merged.
    static func disk(_ bytes: UInt64?, digits: Int = 1) -> Measure {
        guard let bytes else { return .unavailable }
        return scaled(Double(bytes), divisor: 1000, units: byteUnits, digits: digits)
    }

    static func percent(_ value: Double?, digits: Int = 1) -> Measure {
        guard let value, value.isFinite else { return .unavailable }
        return split(number: format(min(999, max(0, value)), digits: digits), unit: "%")
    }

    static func count(_ value: Int) -> Measure {
        split(number: format(Double(value), digits: 0), unit: "")
    }

    // MARK: Formatting

    private static let byteUnits = ["bytes", "KB", "MB", "GB", "TB"]

    private static func scaled(_ value: Double, divisor: Double, units: [String], digits: Int) -> Measure {
        var amount = value
        var index = 0
        while amount >= divisor, index < units.count - 1 {
            amount /= divisor
            index += 1
        }
        // The integer lane holds three digits. Step up rather than overflow it,
        // which is why no reading in the app needs `minimumScaleFactor`.
        if amount >= 1000, index < units.count - 1 {
            amount /= divisor
            index += 1
        }
        let places = index == 0 ? 0 : digits
        return split(number: format(amount, digits: places), unit: units[index])
    }

    /// `String(format:)` is locale-blind, which is why a period used to sit
    /// directly above a comma in the same column. Nothing a reader sees goes
    /// through it.
    private static func format(_ value: Double, digits: Int) -> String {
        let formatter = digits == 0 ? zeroDigits : oneDigit
        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }

    private static func split(number: String, unit: String) -> Measure {
        let separator = oneDigit.decimalSeparator ?? "."
        guard let range = number.range(of: separator) else {
            return Measure(integer: number, fraction: "", unit: unit, isMeasured: true)
        }
        return Measure(
            integer: String(number[number.startIndex..<range.lowerBound]),
            fraction: String(number[range.lowerBound...]),
            unit: unit,
            isMeasured: true
        )
    }

    private static func makeFormatter(_ digits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        formatter.usesGroupingSeparator = false
        return formatter
    }

    private static let oneDigit = makeFormatter(1)
    private static let zeroDigits = makeFormatter(0)
}
