import SceneKit

// MARK: – Vektor-Arithmetik für SCNVector3
//
// Hinweis: Auf macOS sind SCNVector3.x/y/z vom Typ CGFloat (= Double, 64-bit).
// Die Operatoren nehmen Float entgegen und casten intern – so bleibt
// FlightController.swift mit Float-Arithmetik übersichtlich.

extension SCNVector3 {

    // Konvertierung von simd_float3 (z. B. aus FlightState) nach SCNVector3
    init(_ v: simd_float3) {
        self.init(CGFloat(v.x), CGFloat(v.y), CGFloat(v.z))
    }

    // SCNVector3 + SCNVector3
    static func + (l: SCNVector3, r: SCNVector3) -> SCNVector3 {
        SCNVector3(l.x + r.x, l.y + r.y, l.z + r.z)
    }

    // SCNVector3 - SCNVector3
    static func - (l: SCNVector3, r: SCNVector3) -> SCNVector3 {
        SCNVector3(l.x - r.x, l.y - r.y, l.z - r.z)
    }

    // SCNVector3 * Float  →  intern nach CGFloat casten
    static func * (v: SCNVector3, s: Float) -> SCNVector3 {
        let f = CGFloat(s)
        return SCNVector3(v.x * f, v.y * f, v.z * f)
    }

    // SCNVector3 += SCNVector3
    static func += (l: inout SCNVector3, r: SCNVector3) {
        l = l + r
    }

    // Betrag als Float
    var length: Float {
        Float(sqrt(x * x + y * y + z * z))
    }

    // Normalisierter Einheitsvektor
    func normalized() -> SCNVector3 {
        let l = CGFloat(length)
        guard l > 0.0001 else { return SCNVector3(0, 0, -1) }
        return SCNVector3(x / l, y / l, z / l)
    }
}

// Konvertierung von SCNVector3 (CGFloat-Komponenten) nach simd_float3.
// Für Akkord-Anker-Positionen (Phase 3.9.3a), die SceneKit-frei gehalten werden.
func simd3(_ v: SCNVector3) -> simd_float3 {
    simd_float3(Float(v.x), Float(v.y), Float(v.z))
}
