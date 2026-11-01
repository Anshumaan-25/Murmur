import Foundation

public struct AudioMeter: Sendable {
    public private(set) var value: Double = 0
    public init() {}
    public static func normalized(_ rms: Float) -> Double {
        guard rms.isFinite, rms > 0 else { return 0 }
        let decibels = 20 * log10(Double(max(rms, 0.00001)))
        return pow(min(1, max(0, (decibels + 58) / 46)), 1.3)
    }
    public mutating func advance(rms: Float, delta: Double) -> Double {
        let target = Self.normalized(rms)
        let response = target > value ? 0.045 : 0.19
        let amount = 1 - exp(-min(0.1, max(0, delta)) / response)
        value += (target - value) * amount
        if value < 0.0001 { value = 0 }
        return value
    }
}
