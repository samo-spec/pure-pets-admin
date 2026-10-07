"use strict";

// Source-contract regression gate. No native build, credentials or network.
// A failed protected projection must never become a synthetic successful fleet.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const root = path.resolve(__dirname, "..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");
const service = read("PurePetsAdmin/Delivery/PPDeliveryService.m");
const view = read("PurePetsAdmin/Features/Delivery/DeliveryListView.swift");
const backend = read("../Pure Pets Infra/functions/deliveryCommandCenter.js");

function between(source, start, end) {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from + start.length);
  assert.ok(from >= 0 && to > from, "Missing source boundary: " + start);
  return source.slice(from, to);
}

const fetch = between(service, "- (void)fetchCommandCenterWithCompletion:", "- (void)fetchDossierForRequestID:");
assert.equal((fetch.match(/callFunction:/g) || []).length, 1);
assert.match(fetch, /callFunction:@"getDeliveryCommandCenter"/);
assert.match(fetch, /params:@\{@"pageSize": @100\}/);
assert.doesNotMatch(fetch, /collectionWithPath:|getDocuments|FIRFirestore|fallbackDict|companyId/);
assert.match(fetch, /if \(error\) \{\s*if \(completion\) completion\(nil, error\);\s*return;/);
for (const [key, type] of [["jobs", "NSArray"], ["carrier", "NSDictionary"], ["permissions", "NSArray"]]) {
  assert.ok(fetch.includes('![result[@"' + key + '"] isKindOfClass:' + type + '.class]'), "Validate " + key + " before accepting a projection");
}
assert.match(fetch, /completion\(nil, PPDeliveryInvalidResponseError\(\)\)/);
assert.doesNotMatch(fetch, /jobs.*(?:count|length)\s*[><=]/, "An authorized empty queue must remain a valid success");
const valid = fetch.indexOf("initWithDictionary:result");
assert.ok(valid > fetch.indexOf("PPDeliveryInvalidResponseError()"));

const commandCenter = between(backend, "const getDeliveryCommandCenter = onCall", "\nconst ");
assert.match(commandCenter, /requireDeliveryStaffPermission\(request, DELIVERY_PERMISSION\.VIEW, company\)/);
assert.match(commandCenter, /resolveCompany\(request\.data\?\.companyId\)/);
assert.match(commandCenter, /redactJobForPermissions\(job, effectiveStaff\)/);
assert.match(commandCenter, /permissions: Object\.values\(DELIVERY_PERMISSION\)/);

const load = between(view, "    func load(refresh:", "    func loadMembers(");
assert.match(load, /completion: \(@MainActor @Sendable \(\) -> Void\)\?/, "Refresh completion must cross the service callback safely and run on the main actor");
assert.match(load, /guard !isLoading && !isRefreshing/);
assert.match(load, /defer \{ completion\?\(\) \}/);
assert.match(load, /self\.incident\?\.domainCode == "DELIVERY_PERMISSION_DENIED"/);
for (const statement of ["self.snapshot = nil", "self.companyMembers = []", "self.dossier = nil", "self.selectedRequestID = nil"]) {
  assert.ok(load.includes(statement), "Denied projection must clear: " + statement);
}
const members = between(view, "    func loadMembers(", "    func inviteDriver(");
assert.match(members, /guard self\.snapshot != nil, self\.officialCompanyID == resolvedCompanyID else/);
assert.match(view, /\.refreshable \{ await viewModel\.refresh\(\) \}/);

const dates = between(service, "static NSDate * _Nullable PPDeliveryDate(", "static NSError *PPDeliveryInvalidResponseError(");
for (const representation of ['FIRTimestamp.class', '@"seconds"', '@"_seconds"', '@"nanoseconds"', '@"_nanoseconds"', "NSISO8601DateFormatWithFractionalSeconds"]) {
  assert.ok(dates.includes(representation), "Timestamp compatibility: " + representation);
}
assert.match(dates, /!isfinite\(secondsValue\)/);
assert.match(dates, /nanosValue < 0 \|\| nanosValue >= 1000000000\.0/);
assert.match(dates, /formatter\.formatOptions = NSISO8601DateFormatWithInternetDateTime;/);

console.log("PASS: protected projection stays callable-only; errors, empty success, response shape, denied cache, refresh completion and timestamp compatibility checked (source contracts only).");
