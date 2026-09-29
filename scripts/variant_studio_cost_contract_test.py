#!/usr/bin/env python3
"""Run shipping variant cost/pricing methods against a scripted local read boundary.

No Firebase service, app, simulator, or production record is accessed. Integration
assertions below are source-contract checks, not evidence of deployed behavior.
"""
from pathlib import Path
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "PurePetsAdmin/AccessorySection/PPAccessoryVariantService.swift"
source = SERVICE.read_text()
cost_start = source.index("    private func hydrateCost(for product:")
cost_end = source.index("    private static func unavailableProducts", cost_start)
cost = source[cost_start:cost_end].replace("    private func hydrateCost", "    func hydrateCost")
pricing_start = source.index("    func prepareStudioCommerce(")
pricing_end = source.index("    @MainActor\n    func persistStudioCommerce", pricing_start)
pricing = source[pricing_start:pricing_end]

fixture = r'''
import Foundation
enum AccessKind { case normal, typeLivePets }
final class PetAccessory {
 var accessoryID: String? = "variant-A"; var branchID: String? = "branch-A"; var storeID: String?
 var costPrice: NSNumber?; var price: NSNumber = 85; var wholesalePrice: NSNumber?
 var isDeleted = false; var accessKindType = AccessKind.normal
}
final class Staff {
 var admin = false; var allowed = true; var active = true; var global = false; var branches = Set(["branch-A"])
 func isAdmin() -> Bool { admin }
 func isActive() -> Bool { active }
 func hasGlobalScope() -> Bool { global }
 func hasPermission(_ name: String, inBranch branch: String?) -> Bool {
  precondition(name == "stock.cost.view")
  return allowed && (branch.map { branches.contains($0) } ?? false)
 }
}
final class PPStaffAuth {
 static let instance = PPStaffAuth(); var cachedCurrentStaff: Staff? = Staff()
 static func shared() -> PPStaffAuth { instance }
}
enum Source { case server }
struct Document {
 let id: Int; let fields: [String: Any]
 func data() -> [String: Any] { fields }
}
struct Snapshot { var documents: [Document] }
final class Database {
 var documents: [Document] = []; var calls = 0; var fail = false
 func collection(_ name: String) -> Query { precondition(name == "stockMovements"); return Query(db: self) }
}
struct Query {
 let db: Database; var filters: [String: String] = [:]; var ordered = false
 var pageSize = 0; var afterID: Int?
 func whereField(_ field: String, isEqualTo value: Any) -> Query {
  var copy = self; copy.filters[field] = value as? String; return copy
 }
 func order(by field: String, descending: Bool) -> Query {
  precondition(field == "timestamp" && descending); var copy = self; copy.ordered = true; return copy
 }
 func limit(to count: Int) -> Query { var copy = self; copy.pageSize = count; return copy }
 func start(afterDocument document: Document) -> Query { var copy = self; copy.afterID = document.id; return copy }
 func getDocuments(source: Source) async throws -> Snapshot {
  db.calls += 1
  precondition(ordered && pageSize > 0 && filters["productId"] != nil && filters["type"] == "stock_in")
  if db.fail { throw NSError(domain: "fixture.read", code: 7) }
  let matches = db.documents.filter { doc in filters.allSatisfy { doc.fields[$0.key] as? String == $0.value } }
   .sorted { ($0.fields["timestamp"] as! Int) > ($1.fields["timestamp"] as! Int) }
  let offset = afterID.flatMap { id in matches.firstIndex { $0.id == id }.map { $0 + 1 } } ?? 0
  return Snapshot(documents: Array(matches.dropFirst(offset).prefix(pageSize)))
 }
}
struct Reply { let data: Any }
final class Functions {
 var reply: Any = [:]; var calls = 0
 func httpsCallable(_ name: String) -> Functions { precondition(name == "getProductCommerce"); return self }
 func call(_ request: [String: Any]) async throws -> Reply {
  precondition(request["productId"] as? String == "variant-A"); calls += 1; return Reply(data: reply)
 }
}
enum PPAccessoryVariantServiceError: Error { case invalidResponse, validationFailed([String]) }
enum Language { static func get(_ key: String, alter: String) -> String { key } }
@MainActor final class Service {
 let db = Database(); let functions = Functions()
 // SHIPPING_COST
 // SHIPPING_PRICING
}
func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message) }
func movement(_ id: Int, _ cost: Any?, product: String = "variant-A", branch: String = "branch-A") -> Document {
 var data: [String: Any] = ["productId": product, "branchId": branch, "type": "stock_in", "timestamp": id]
 if let cost { data["costPrice"] = cost }; return Document(id: id, fields: data)
}
func same(_ a: Any, _ b: Any) -> Bool { String(describing: a) == String(describing: b) }
Task { @MainActor in
 let service = Service(); let product = PetAccessory()
 for (input, expected): (Any, Double) in [(0, 0), (80.25, 80.25), ("0", 0), (" 12.50 ", 12.50)] {
  check(Service.recordedCost(in: ["costPrice": input]) == expected, "Valid stored cost lost")
 }
 for value: Any in [NSNull(), -1, Double.infinity, Double.nan, "invalid", "-3"] {
  check(Service.recordedCost(in: ["costPrice": value]) == nil, "Invalid cost accepted")
 }
 check(Service.recordedCost(in: [:]) == nil, "Missing cost fabricated as zero")
 product.branchID = "main_store"; product.storeID = "branch-A"
 check(Service.costBranch(for: product) == "branch-A", "Branch sentinel prevented concrete branch")
 product.branchID = "branch-A"
 product.costPrice = 99; PPStaffAuth.instance.cachedCurrentStaff!.allowed = false
 try await service.hydrateCost(for: product)
 check(product.costPrice == nil && service.db.calls == 0, "Unauthorized cost read/exposure")
 PPStaffAuth.instance.cachedCurrentStaff!.allowed = true
 product.accessKindType = .typeLivePets; product.costPrice = 80
 try await service.hydrateCost(for: product)
 check(product.costPrice == nil && service.db.calls == 0, "Live unit cost leaked into variant catalog")
 product.accessKindType = .normal
 service.db.documents = [movement(1, 80), movement(2, 0), movement(3, 999, product: "variant-B"), movement(4, 888, branch: "branch-B")]
 product.costPrice = 75
 try await service.hydrateCost(for: product)
 check(product.costPrice == 0, "Zero or exact product/branch identity lost")
 service.db.documents = [movement(1, "80.25"), movement(2, NSNull()), movement(3, nil)]
 try await service.hydrateCost(for: product)
 check(product.costPrice == 80.25, "Newer costless movement hid last recorded cost")
 service.db.documents = []; product.costPrice = 0
 try await service.hydrateCost(for: product)
 check(product.costPrice == 0, "Legacy zero lost")
 product.costPrice = nil
 try await service.hydrateCost(for: product)
 check(product.costPrice == nil, "Unknown cost fabricated")
 service.db.fail = true; product.costPrice = 80
 do { try await service.hydrateCost(for: product); fatalError("Denied read silently accepted") } catch {}
 check(product.costPrice == nil, "Read error left misleading legacy cost")
 service.db.fail = false
 service.db.documents = (1...55).map { movement($0, nil) } + [movement(0, 0)]
 let calls = service.db.calls
 try await service.hydrateCost(for: product)
 check(product.costPrice == 0 && service.db.calls == calls + 2, "Cost pagination failed")
 service.db.documents = (1...500).map { movement($0, nil) }; product.costPrice = nil
 do { try await service.hydrateCost(for: product); fatalError("Truncated cost scan claimed absence") } catch {}
 check(product.costPrice == nil, "Bounded scan fabricated cost")
 let single: [String: Any] = ["id":"single", "unitsPerGroup":1, "barcode":"one", "sku":"sku-one", "retailEnabled":true, "defaultForRetail":true, "retailPriceMinor":8500, "wholesaleEnabled":true, "defaultForWholesale":true, "wholesalePriceMinor":7500]
 let pack: [String: Any] = ["id":"pack", "unitsPerGroup":12, "barcode":"box", "sku":"sku-box", "retailEnabled":true, "retailPriceMinor":90000, "wholesaleEnabled":true, "wholesalePriceMinor":80000, "active":true]
 let base: [String: Any] = ["id":"piece", "nameAr":"قطعة", "nameEn":"Piece"]
 service.functions.reply = ["hasWholesaleAccess":true, "productCommerce":["pricingRevision":7, "baseUnit":base, "currency":"QAR", "quantityGroups":[single,pack]]]
 product.wholesalePrice = 75
 let request = try await service.prepareStudioCommerce(product: product, retailPrice: 90.25, wholesalePrice: 76.5, commandId: "pricing-fixture")!
 let groups = request["quantityGroups"] as! [[String: Any]]
 check(groups.count == 2 && NSDictionary(dictionary: groups[1]).isEqual(to: pack), "Multipack content overwritten")
 check(groups[0]["retailPriceMinor"] as? Int == 9025 && groups[0]["wholesalePriceMinor"] as? Int == 7650, "Edited cents not preserved")
 check(groups[0]["barcode"] as? String == "one" && groups[0]["sku"] as? String == "sku-one", "Default group identity overwritten")
 check(request["expectedRevision"] as? Int == 7 && request["productId"] as? String == "variant-A", "Pricing authority/identity lost")
 let priceCalls = service.functions.calls
 let noChange = try await service.prepareStudioCommerce(product: product, retailPrice: 85, wholesalePrice: 75, commandId: "unchanged")
 check(noChange == nil && service.functions.calls == priceCalls, "Unchanged pricing triggered write preparation")
 do { _ = try await service.prepareStudioCommerce(product: product, retailPrice: 90, wholesalePrice: nil, commandId: "remove"); fatalError("Independent wholesale pack silently removed") } catch {}
 service.functions.reply = ["hasWholesaleAccess":false, "productCommerce":["pricingRevision":7, "baseUnit":base, "quantityGroups":[single,pack]]]
 do { _ = try await service.prepareStudioCommerce(product: product, retailPrice: 90, wholesalePrice: 75, commandId: "denied"); fatalError("Redacted pricing replayed") } catch {}
 print("VARIANT_STUDIO_COST_CONTRACT_TEST: PASS (shipping Swift cost parser, permission gating, exact identity/branch, zero, missing/invalid, denied reads, pagination/bound, and multipack pricing methods)")
 exit(0)
}
RunLoop.main.run()
'''

# The real query shape must remain satisfiable by declared Infra indexes.
indexes = json.loads((ROOT.parent / "Pure Pets Infra/firestore/indexes.json").read_text())["indexes"]
for fields in [
    [("productId", "ASCENDING"), ("type", "ASCENDING"), ("timestamp", "DESCENDING")],
    [("productId", "ASCENDING"), ("type", "ASCENDING"), ("branchId", "ASCENDING"), ("timestamp", "DESCENDING")],
]:
    assert any(i["collectionGroup"] == "stockMovements" and
               [(f["fieldPath"], f.get("order")) for f in i["fields"]] == fields
               for i in indexes), f"Missing declared cost index: {fields}"
family_load = source[source.index("    private func loadProducts(ids:"):source.index("    public func loadProduct(productId:")]
assert "hydrateCost(for: product)" in family_load, "Family load bypasses protected cost hydration"
exact = source[source.index("    public func loadProduct(productId:"):cost_start]
assert "try await hydrateCost(for: product)" in exact, "Exact variant reopen bypasses protected cost hydration"

with tempfile.TemporaryDirectory(prefix="pp-variant-cost-") as temp:
    script = Path(temp) / "VariantCost.swift"
    script.write_text(fixture.replace(" // SHIPPING_COST", cost).replace(" // SHIPPING_PRICING", pricing))
    subprocess.run(["swift", str(script)], check=True)
print("SOURCE_CONTRACTS: PASS (family/exact hydration integration and declared query indexes; live indexes and Firebase execution unverified)")
