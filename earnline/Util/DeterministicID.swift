import Foundation

enum DeterministicID {
    static func uuid(_ value: String) -> UUID {
        var h1: UInt64 = 0xcbf29ce484222325
        var h2: UInt64 = 0x84222325cbf29ce4
        for byte in value.utf8 {
            h1 ^= UInt64(byte)
            h1 &*= 0x100000001b3
            h2 ^= UInt64(byte) &+ 0x9e3779b97f4a7c15
            h2 &*= 0x100000001b3
        }

        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8((h1 >> UInt64((7 - index) * 8)) & 0xff)
            bytes[index + 8] = UInt8((h2 >> UInt64((7 - index) * 8)) & 0xff)
        }

        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
