import Foundation

public enum PPDocumentValue: Codable, Equatable, Sendable {
  case string(String)
  case bool(Bool)
  case integer(Int)
  case double(Double)
  case date(Date)
  case array([PPDocumentValue])
  case object(PPDocument)
  case null

  public var stringValue: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }

  public var boolValue: Bool? {
    switch self {
    case .bool(let value): return value
    case .integer(let value): return value != 0
    case .double(let value): return value != 0
    case .string(let value):
      switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
      case "true", "yes", "1": return true
      case "false", "no", "0": return false
      default: return nil
      }
    default: return nil
    }
  }

  public var intValue: Int? {
    switch self {
    case .integer(let value): return value
    case .double(let value): return Int(value)
    case .string(let value): return Int(value)
    default: return nil
    }
  }

  public var doubleValue: Double? {
    switch self {
    case .double(let value): return value
    case .integer(let value): return Double(value)
    case .string(let value): return Double(value)
    default: return nil
    }
  }

  public var dateValue: Date? {
    switch self {
    case .date(let value): return value
    case .double(let value): return Date(timeIntervalSince1970: value)
    case .integer(let value): return Date(timeIntervalSince1970: TimeInterval(value))
    default: return nil
    }
  }

  public var arrayValue: [PPDocumentValue]? {
    guard case .array(let value) = self else { return nil }
    return value
  }

  public var objectValue: PPDocument? {
    guard case .object(let value) = self else { return nil }
    return value
  }
}

public typealias PPDocument = [String: PPDocumentValue]

extension Dictionary where Key == String, Value == PPDocumentValue {
  package func ppFirst(_ keys: [String]) -> PPDocumentValue? {
    for key in keys {
      if let value = self[key], value != .null { return value }
    }
    return nil
  }

  package func ppString(_ keys: [String]) -> String? {
    ppFirst(keys)?.stringValue?.ppNilIfBlank
  }

  package func ppBool(_ keys: [String]) -> Bool? {
    ppFirst(keys)?.boolValue
  }

  package func ppInt(_ keys: [String]) -> Int? {
    ppFirst(keys)?.intValue
  }

  package func ppDouble(_ keys: [String]) -> Double? {
    ppFirst(keys)?.doubleValue
  }

  package func ppDate(_ keys: [String]) -> Date? {
    ppFirst(keys)?.dateValue
  }

  package func ppObject(_ key: String) -> PPDocument {
    self[key]?.objectValue ?? [:]
  }
}
