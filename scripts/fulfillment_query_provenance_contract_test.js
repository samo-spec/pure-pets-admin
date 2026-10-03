"use strict";

// Source contract only: no app build, Firebase SDK, network, or IAM grants.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");
const service = read("PurePetsAdmin/Fulfillment/PPFulfillmentService.m");
const model = read("PurePetsAdmin/UsersSection/SecFil/PPStaffAuth.m");
const header = read("PurePetsAdmin/UsersSection/SecFil/PPStaffAuth.h");
const rules = read("../Pure Pets Infra/firestore.rules");

function between(source, start, end) {
  const begin = source.indexOf(start);
  assert.notEqual(begin, -1, `Missing ${start}`);
  const finish = source.indexOf(end, begin + start.length);
  assert.notEqual(finish, -1, `Missing ${end}`);
  return source.slice(begin, finish);
}

const policy = between(rules, "function staffDocumentHasAnyGlobalPermission", "function staffV2HasAnyPermissionForResolvedScope");
assert.match(policy, /staffUsesEnforcedAuthorization\(doc\)[\s\S]*staffV2AuthorizationIsCurrent\(doc\)[\s\S]*projection\.globalPermissions\.hasAny\(perms\)/);
assert.match(policy, /staffUsesLegacyCompatibility\(doc\)[\s\S]*doc\.permissions\.hasAny\(perms\)/);
const legacyModes = between(rules, "function staffUsesLegacyCompatibility", "function staffV2AuthorizationIsCurrent");
assert.match(legacyModes, /!\('authorizationMode' in doc\)/);
assert.match(legacyModes, /\['legacy', 'shadow', 'prepared'\]/);

for (const field of ["authorizationMode", "authorizationGlobalPermissions", "explicitPermissions"]) {
  assert.match(header, new RegExp(`@property\\s*\\([^\\n]*readonly[^\\n]*\\)[^\\n]*\\b${field};`));
}
assert.match(model, /NSArray<NSString \*> \*explicitPermissions = PPStaffCanonicalPermissionKeys\(root\[@"permissions"\]\);\s*_explicitPermissions = explicitPermissions;/);
assert.match(model, /_authorizationMode = authorizationMode == nil \? nil :\s*\(\[authorizationMode isKindOfClass:NSString\.class\] \? \[authorizationMode copy\] : @""\)/);
assert.match(model, /_authorizationGlobalPermissions = PPStaffCanonicalPermissionKeys\(authorization\[@"globalPermissions"\]\)/);

// IAM provenance plans exception queries only. It must not alter the shared
// effective-permission implementation used elsewhere in the application.
const hasPermission = between(model, "- (BOOL)hasPermission:(NSString *)perm {", "- (BOOL)hasAnyPermission:");
assert.match(hasPermission, /return PPStaffMatchesPermission\(self\.permissions, perm\);/);
assert.doesNotMatch(hasPermission, /authorizationMode|authorizationGlobalPermissions|explicitPermissions/);

const planner = between(service, "static BOOL PPFulfillmentCanReadUnassignedPlatform", "static BOOL PPFulfillmentHasParentReadScope");
assert.match(planner, /if \(!PPFulfillmentCanRead\(staff\)\) return NO;/);
assert.match(planner, /if \(staff\.isAdmin\) return YES;/);
assert.match(planner, /\[mode isEqualToString:@"enforced"\][\s\S]*globalPermissions = staff\.authorizationGlobalPermissions;/);
assert.match(planner, /mode == nil \|\| \[@\[@"legacy", @"shadow", @"prepared"\] containsObject:mode\][\s\S]*globalPermissions = staff\.explicitPermissions;/);
assert.match(planner, /else \{\s*return NO;/);
assert.doesNotMatch(planner, /globalPermissions = staff\.permissions|hasGlobalScope|branchPermissions|regionPermissions/);
assert.match(planner, /kStaffPermPaymentsView, kStaffPermPaymentsManage, kStaffPermProvidersView/);

const queries = between(service, "static NSArray<FIRQuery *> *PPFulfillmentScopedQueries", "static NSArray<FIRDocumentSnapshot *> *PPFulfillmentMergeDocuments");
assert.match(queries, /if \(PPFulfillmentCanReadUnassignedPlatform\(staff\)\) \{\s*for \(id branchValue in @\[NSNull\.null, @""\]\)/);
assert.match(queries, /queryWhereField:@"ownerType" isEqualTo:@"platform"/);
assert.match(queries, /queryWhereField:@"branchId" isEqualTo:branchValue/);
const reachable = between(service, "static BOOL PPFulfillmentStaffCanReachData", "static FIRQuery *PPFulfillmentOrderedQuery");
assert.match(reachable, /if \(unassignedBranch &&[\s\S]*PPFulfillmentCanReadUnassignedPlatform\(staff\)\)/);
const readableScope = between(service, "static BOOL PPFulfillmentHasReadableScope", "static BOOL PPFulfillmentCanReadParents");
assert.match(readableScope, /PPFulfillmentHasParentReadScope\(staff\) \|\| PPFulfillmentCanReadUnassignedPlatform\(staff\)/);
const recovery = between(service, "- (void)fetchRecoveryOrdersWithCompletion:", "- (id<FIRListenerRegistration>)observeFulfillment:");
assert.match(recovery, /PPFulfillmentHasParentReadScope\(staff\)/);
assert.doesNotMatch(recovery, /PPFulfillmentCanReadUnassignedPlatform|queryWhereField:@"ownerType"/);

console.log("PASS: fulfillment exception-query provenance matches Rules modes, branch-only/unknown grants cannot select unassigned queries, parent scope stays strict, shared permission behavior unchanged (source contract only).");
