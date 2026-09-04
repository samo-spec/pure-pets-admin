import Foundation

public final class Firestore: @unchecked Sendable {
  public static func firestore() -> Firestore { Firestore() }
  public func collection(_ path: String) -> CollectionReference { CollectionReference() }
}
public protocol ListenerRegistration: Sendable { func remove() }
public final class Registration: ListenerRegistration {
  public init() {}
  public func remove() {}
}
open class Query: @unchecked Sendable {
  public func getDocuments(completion: @escaping @Sendable (QuerySnapshot?, Error?) -> Void) {}
}
public final class CollectionReference: Query, @unchecked Sendable {
  public func document(_ path: String) -> DocumentReference { DocumentReference() }
  public func addSnapshotListener(_ listener: @escaping @Sendable (QuerySnapshot?, Error?) -> Void)
    -> ListenerRegistration
  { Registration() }
}
public final class DocumentReference: @unchecked Sendable {
  public func collection(_ path: String) -> CollectionReference { CollectionReference() }
  public func addSnapshotListener(
    _ listener: @escaping @Sendable (DocumentSnapshot?, Error?) -> Void
  ) -> ListenerRegistration { Registration() }
  public func getDocument(completion: @escaping @Sendable (DocumentSnapshot?, Error?) -> Void) {}
  public func setData(
    _ documentData: [String: Any], merge: Bool, completion: @escaping @Sendable (Error?) -> Void
  ) {}
}
open class DocumentSnapshot: @unchecked Sendable {
  public func data() -> [String: Any]? { nil }
}
public final class QueryDocumentSnapshot: DocumentSnapshot, @unchecked Sendable {
  public var documentID: String = ""
  public override func data() -> [String: Any] { [:] }
}
public final class QuerySnapshot: @unchecked Sendable {
  public var documents: [QueryDocumentSnapshot] = []
}
public final class Timestamp: @unchecked Sendable {
  public func dateValue() -> Date { .now }
}
public final class FieldValue: @unchecked Sendable {
  public static func serverTimestamp() -> FieldValue { FieldValue() }
  public static func delete() -> FieldValue { FieldValue() }
}
