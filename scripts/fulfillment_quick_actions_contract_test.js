"use strict";

// Cross-language source contract test. No app build, Firebase SDK, or network.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const adminRoot = path.resolve(__dirname, "..");
const read = (file) => fs.readFileSync(path.join(adminRoot, file), "utf8");
const view = read("PurePetsAdmin/Features/Fulfillment/FulfillmentListView.swift");
const service = read("PurePetsAdmin/Fulfillment/PPFulfillmentService.m");
const backend = read("../Pure Pets Infra/functions/fulfillmentOrders.js");

function between(source, start, end) {
  const begin = source.indexOf(start);
  assert.notEqual(begin, -1, `Missing start: ${start}`);
  const finish = source.indexOf(end, begin + start.length);
  assert.notEqual(finish, -1, `Missing end: ${end}`);
  return source.slice(begin, finish);
}

// Execute the actual Infra transition table, isolated from SDK initialization.
const statuses = between(backend, "const FULFILLMENT_STATUS =", "\n});") + "\n});";
const transitions = between(backend, "const PROVIDER_FULFILLMENT_TRANSITION =", "\n});") + "\n});";
const graph = vm.runInNewContext(`${statuses}\n${transitions}\nPROVIDER_FULFILLMENT_TRANSITION`, {}, { timeout: 1000 });
const quickActions = between(view, "    var nextQuickAction:", "\nstruct FulfillmentEventSnapshot");
const officialActions = between(service, "+ (NSArray<NSString *> *)availableOfficialActionsForStatus:", "\n@end");
const overrideTargets = between(service, "+ (NSArray<NSString *> *)allowedOverrideTargetsForStatus:", "+ (BOOL)isOfficialPlatformFulfillment:");
const rows = [...quickActions.matchAll(/case "([^"]+)":\s*action = \(Language\.get\("([^"]+)", alter: "[^"]+"\), "([^"]+)", "([^"]+)", "[^"]+"\)/g)];
assert.equal(rows.length, 4, "All four operational quick actions must be covered");
for (const [, currentStatus, titleKey, targetStatus, action] of rows) {
  assert.equal(graph[currentStatus]?.[action], targetStatus, `${currentStatus}: Admin action must produce the displayed target in Infra`);
  assert.equal(graph[currentStatus]?.[targetStatus], undefined, "Regression: target status is not a callable action");
  assert.match(officialActions, new RegExp(`@"${currentStatus}": @\\[[^\\]]*@"${action}"`));
  assert.match(overrideTargets, new RegExp(`@"${currentStatus}": @\\[[^\\]]*@"${targetStatus}"`));
  for (const language of ["ar", "en"]) {
    const strings = read(`PurePetsAdmin/${language}.lproj/Localizable.strings`);
    assert.match(strings, new RegExp(`"${titleKey}"\\s*=`));
    const note = strings.match(/"Fulfillment_Quick_Audit_Note"\s*=\s*"([^"]+)";/)?.[1];
    assert.ok(note && note.includes("%@") && note.length >= 3 && note.length < 400);
  }
}
assert.doesNotMatch(quickActions, /case "pending"|case "processing"|case "completed"/);
assert.match(quickActions, /canAdminOverride\(\)/);
assert.match(quickActions, /isOfficialPlatformFulfillment\(rawRecord\)/);
assert.match(quickActions, /ownerType == "partner" && !ownerID\.isEmpty/);

const submit = between(view, "    func quickAdvance(", "    func executeAdminOverride(");
assert.match(submit, /action\.targetStatus == targetStatus/);
assert.match(submit, /action: action\.providerAction/);
assert.doesNotMatch(submit, /action: targetStatus/);
assert.match(submit, /expectedStatus: record\.status/);
assert.match(submit, /targetStatus: targetStatus/); // Partner override retains its status contract.
assert.match(submit, /isOfficialPlatformFulfillment\(record\.rawRecord\)/);
assert.doesNotMatch(submit, /uuidString\.prefix/);
assert.match(submit, /beginAction\(\)/);
assert.match(between(view, "    private func beginAction(", "    private func receiveCommand("), /errorMessage = nil/);

// Regression: these are Firestore registrations, not NotificationCenter tokens.
assert.match(view, /listener\?\.remove\(\)/);
assert.match(view, /eventsListener\?\.remove\(\)/);
assert.doesNotMatch(view, /NotificationCenter\.default\.removeObserver/);
assert.match(view, /self\.listenerGeneration == generation/);
assert.match(view, /eventsListenerGeneration == generation/);
assert.match(view, /func reload\(\)\s*\{\s*stopListening\(\)\s*startListening\(\)/);
assert.match(view, /AdminErrorBanner\(message: error, retry: \{ viewModel\.reload\(\) \}\)/);
console.log("PASS: four quick actions match Infra, invalid aliases excluded, permissions/ownership/replay payloads preserved, localized notes and listener teardown checked (source contract only).");
