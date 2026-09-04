#if canImport(FirebaseFirestore)
  import CoreFoundation
  import Foundation
  import FirebaseFirestore
  import PurePetsUserKit

  enum PPFirebaseDocumentConverter {
    static func document(from value: [String: Any]) -> PPDocument {
      value.compactMapValues(convert)
    }

    static func convert(_ value: Any) -> PPDocumentValue? {
      switch value {
      case is NSNull:
        return .null
      case let value as String:
        return .string(value)
      case let value as Bool:
        return .bool(value)
      case let value as NSNumber:
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
          return .bool(value.boolValue)
        }
        let double = value.doubleValue
        return double.rounded(.towardZero) == double
          ? .integer(value.intValue)
          : .double(double)
      case let value as Timestamp:
        return .date(value.dateValue())
      case let value as Date:
        return .date(value)
      case let value as [Any]:
        return .array(value.compactMap(convert))
      case let value as [String: Any]:
        return .object(document(from: value))
      default:
        return nil
      }
    }
  }
#endif
