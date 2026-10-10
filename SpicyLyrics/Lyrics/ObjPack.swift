import Foundation

/// Decoder for Spicy Lyrics' `SLObjPack` wire format (`src/utils/objpack.ts`).
///
/// A payload is `[values, stream]`: `values` holds every distinct primitive once and `stream`
/// is a list of opcodes. A non-negative opcode points into `values`; negative ones open containers.
enum ObjPack {
    enum DecodeError: Error {
        case invalidStructure
        case unexpectedEnd
        case invalidPointer(Int)
        case invalidCount
        case nonStringKey
        case tooDeep
    }

    private static let maxDepth = 512

    static func unpack(_ packed: Any) throws -> Any {
        guard let shell = packed as? [Any], shell.count == 2,
              let values = shell[0] as? [Any],
              let rawStream = shell[1] as? [Any]
        else { throw DecodeError.invalidStructure }

        let stream: [Int] = try rawStream.map { item in
            guard let number = item as? NSNumber else { throw DecodeError.invalidStructure }
            return number.intValue
        }
        var reader = Reader(values: values, stream: stream)
        return try reader.readValue(depth: 0)
    }

    private struct Reader {
        let values: [Any]
        let stream: [Int]
        var cursor = 0

        mutating func next() throws -> Int {
            guard cursor < stream.count else { throw DecodeError.unexpectedEnd }
            defer { cursor += 1 }
            return stream[cursor]
        }

        func primitive(_ pointer: Int) throws -> Any {
            guard pointer >= 0, pointer < values.count else { throw DecodeError.invalidPointer(pointer) }
            return values[pointer]
        }

        mutating func key() throws -> String {
            guard let key = try primitive(try next()) as? String else { throw DecodeError.nonStringKey }
            return key
        }

        mutating func count() throws -> Int {
            let n = try next()
            guard n >= 0, n <= stream.count else { throw DecodeError.invalidCount }
            return n
        }

        mutating func readValue(depth: Int) throws -> Any {
            guard depth <= ObjPack.maxDepth else { throw DecodeError.tooDeep }
            let op = try next()
            switch op {
            case 0...:
                return try primitive(op)
            case -1:
                let n = try count()
                var keys: [String] = []
                keys.reserveCapacity(n)
                for _ in 0..<n { keys.append(try key()) }
                var object: [String: Any] = [:]
                for k in keys { object[k] = try readValue(depth: depth + 1) }
                return object
            case -2:
                let n = try count()
                var array: [Any] = []
                array.reserveCapacity(n)
                for _ in 0..<n { array.append(try readValue(depth: depth + 1)) }
                return array
            case -3:
                let n = try count()
                let keyCount = try count()
                var keys: [String] = []
                for _ in 0..<keyCount { keys.append(try key()) }
                var array: [Any] = []
                array.reserveCapacity(n)
                for _ in 0..<n {
                    var object: [String: Any] = [:]
                    for k in keys { object[k] = try readValue(depth: depth + 1) }
                    array.append(object)
                }
                return array
            case -4:
                return [Any]()
            case -5:
                return [try readValue(depth: depth + 1)]
            case -6:
                return [String: Any]()
            default:
                throw DecodeError.invalidStructure
            }
        }
    }
}

// MARK: - Loose JSON helpers

enum JSONLoose {
    static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            // NSNumber also wraps booleans; those are not times.
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let number as NSNumber: return number.boolValue
        case let string as String: return string.lowercased() == "true"
        default: return nil
        }
    }

    static func string(_ value: Any?) -> String? {
        value as? String
    }

    static func objects(_ value: Any?) -> [[String: Any]] {
        (value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }
}
