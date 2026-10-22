import Foundation

/// Gets the plain text from the `attributedBody` column of chat.db.
///
/// Since macOS 13, many rows have a NULL `text` column. The text is then only in
/// `attributedBody`, which is an `NSAttributedString` in the `typedstream` format.
/// This decoder does not parse the full format. It finds the `NSString` class
/// record and reads the length-prefixed UTF-8 bytes after it.
public enum AttributedBodyDecoder {
    private static let classMarker = Array("NSString".utf8)
    /// The `+` type tag comes a few bytes after the class name.
    private static let typeTag: UInt8 = 0x2B
    private static let maxTagDistance = 16

    public static func text(from data: Data) -> String? {
        let bytes = [UInt8](data)
        guard let markerStart = firstIndex(of: classMarker, in: bytes) else { return nil }

        let searchStart = markerStart + classMarker.count
        let searchEnd = min(bytes.count, searchStart + maxTagDistance)
        guard searchStart < searchEnd,
            let tagIndex = bytes[searchStart..<searchEnd].firstIndex(of: typeTag)
        else { return nil }

        var index = tagIndex + 1
        guard let length = readLength(bytes, at: &index), index + length <= bytes.count else { return nil }
        return String(bytes: bytes[index..<(index + length)], encoding: .utf8)
    }

    /// Reads a typedstream integer. 0x81 starts a 2-byte little-endian value and
    /// 0x82 starts a 4-byte little-endian value. Other values below 0x80 are the
    /// value itself.
    private static func readLength(_ bytes: [UInt8], at index: inout Int) -> Int? {
        guard index < bytes.count else { return nil }
        let tag = bytes[index]
        index += 1
        switch tag {
        case 0x00..<0x80:
            return Int(tag)
        case 0x81:
            return readLittleEndian(bytes, at: &index, width: 2)
        case 0x82:
            return readLittleEndian(bytes, at: &index, width: 4)
        default:
            return nil
        }
    }

    private static func readLittleEndian(_ bytes: [UInt8], at index: inout Int, width: Int) -> Int? {
        guard index + width <= bytes.count else { return nil }
        var value = 0
        for offset in 0..<width {
            value |= Int(bytes[index + offset]) << (8 * offset)
        }
        index += width
        return value
    }

    private static func firstIndex(of pattern: [UInt8], in bytes: [UInt8]) -> Int? {
        guard !pattern.isEmpty, bytes.count >= pattern.count else { return nil }
        for start in 0...(bytes.count - pattern.count) where bytes[start] == pattern[0] {
            if bytes[start..<(start + pattern.count)].elementsEqual(pattern) { return start }
        }
        return nil
    }
}
