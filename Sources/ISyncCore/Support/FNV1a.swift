import Foundation

/// The 64-bit FNV-1a hash. The package uses it to find changed records and to
/// make idempotency keys. It is not a security control.
enum FNV1a {
    static func hash(_ bytes: some Sequence<UInt8>) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// The hash as 16 lowercase hexadecimal digits.
    static func hexDigest(_ bytes: some Sequence<UInt8>) -> String {
        let digits = String(hash(bytes), radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}
