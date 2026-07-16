import Foundation

nonisolated struct JSONDuplicateKeyScanner {
    let bytes: [UInt8]
    var index = 0

    init(data: Data) {
        bytes = Array(data)
    }

    mutating func validate() throws {
        skipWhitespace()
        try parseValue(path: "$")
        skipWhitespace()
        guard index == bytes.count else {
            throw LiveFleetContractError.invalidJSON("unexpected trailing content")
        }
    }

    private mutating func parseValue(path: String) throws {
        skipWhitespace()
        guard index < bytes.count else { throw LiveFleetContractError.invalidJSON("unexpected end of input") }
        switch bytes[index] {
        case 0x7B: try parseObject(path: path)
        case 0x5B: try parseArray(path: path)
        case 0x22: _ = try parseString()
        default: try parsePrimitive()
        }
    }

    private mutating func parseObject(path: String) throws {
        index += 1
        skipWhitespace()
        if consume(0x7D) { return }
        var keys = Set<String>()
        while true {
            let key = try parseString()
            guard keys.insert(key).inserted else {
                throw LiveFleetContractError.duplicateKey("\(path).\(key)")
            }
            skipWhitespace()
            guard consume(0x3A) else { throw LiveFleetContractError.invalidJSON("expected colon") }
            try parseValue(path: "\(path).\(key)")
            skipWhitespace()
            if consume(0x7D) { return }
            guard consume(0x2C) else { throw LiveFleetContractError.invalidJSON("expected comma") }
            skipWhitespace()
        }
    }

    private mutating func parseArray(path: String) throws {
        index += 1
        skipWhitespace()
        if consume(0x5D) { return }
        var element = 0
        while true {
            try parseValue(path: "\(path)[\(element)]")
            element += 1
            skipWhitespace()
            if consume(0x5D) { return }
            guard consume(0x2C) else { throw LiveFleetContractError.invalidJSON("expected comma") }
        }
    }

    private mutating func parseString() throws -> String {
        guard index < bytes.count, bytes[index] == 0x22 else {
            throw LiveFleetContractError.invalidJSON("expected string")
        }
        let start = index
        index += 1
        var escaped = false
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if escaped { escaped = false; continue }
            if byte == 0x5C { escaped = true; continue }
            if byte == 0x22 {
                let data = Data(bytes[start..<index])
                do { return try JSONDecoder().decode(String.self, from: data) }
                catch { throw LiveFleetContractError.invalidJSON("invalid string") }
            }
        }
        throw LiveFleetContractError.invalidJSON("unterminated string")
    }

    private mutating func parsePrimitive() throws {
        let start = index
        while index < bytes.count, ![0x20, 0x09, 0x0A, 0x0D, 0x2C, 0x5D, 0x7D].contains(bytes[index]) {
            index += 1
        }
        guard index > start else { throw LiveFleetContractError.invalidJSON("expected value") }
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }
}
