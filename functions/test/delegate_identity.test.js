const test = require("node:test");
const assert = require("node:assert/strict");
const identity = require("../lib/delegate_identity");
const logic = require("../lib/delegate_login_logic");

// The exact field set found on prod ghost docs (e.g. new start / mL3nw…).
const GHOST = {
  boundDeviceBrand: "OPPO", boundDeviceId: "RP1A.200720.011", boundDeviceModel: "OPPO CPH1989",
  boundDeviceOs: "Android 11 (SDK 30)", deviceBoundAt: new Date(), deviceLastSeenAt: new Date(),
  isDeviceLocked: true, position: "Promoter", delegatePublicId: "DEL-6179", updatedAt: new Date(),
};

test("hasDelegateIdentity: ghost doc with device/backfill fields only has no identity", () => {
  assert.equal(identity.hasDelegateIdentity(GHOST), false);
  assert.equal(identity.hasDelegateIdentity({ ...GHOST, forceLogoutAt: new Date(), requireReLogin: true }), false);
  assert.equal(identity.hasDelegateIdentity({ fullName: "   " }), false);
  assert.equal(identity.hasDelegateIdentity(null), false);
  assert.equal(identity.hasDelegateIdentity(undefined), false);
});

test("hasDelegateIdentity: any name, national id or phone counts", () => {
  assert.equal(identity.hasDelegateIdentity({ fullName: "مينا عماد فوزي" }), true);
  assert.equal(identity.hasDelegateIdentity({ firstName: "مينا" }), true);
  assert.equal(identity.hasDelegateIdentity({ name: "x" }), true);
  assert.equal(identity.hasDelegateIdentity({ nationalityID: "30302141801253" }), true);
  assert.equal(identity.hasDelegateIdentity({ phoneNumber: "01279747624" }), true);
  assert.equal(identity.hasDelegateIdentity({ ...GHOST, phone: "01000000000" }), true);
});

test("isDeletedDelegateStatus", () => {
  for (const s of ["deleted", "Deleted ", "removed", "archived"]) {
    assert.equal(identity.isDeletedDelegateStatus(s), true, s);
  }
  for (const s of ["active", "suspended", "", null, undefined]) {
    assert.equal(identity.isDeletedDelegateStatus(s), false, String(s));
  }
});

test("planDeletedLinkCleanup: still linked elsewhere -> nothing", () => {
  const plan = identity.planDeletedLinkCleanup({ remainingLiveLinks: 1, usersRole: null });
  assert.deepEqual(plan, { clearDeviceBinding: false, cancelUnbindRequests: false, revokeSessions: false, reason: "still_linked" });
});

test("planDeletedLinkCleanup: staff uid with a ghost doc is never revoked", () => {
  for (const role of ["company-admin", "organization-admin", "super-admin", "supervisor"]) {
    const plan = identity.planDeletedLinkCleanup({ remainingLiveLinks: 0, usersRole: role });
    assert.equal(plan.reason, "staff_account", role);
    assert.equal(plan.revokeSessions, false);
    assert.equal(plan.clearDeviceBinding, false);
  }
});

test("planDeletedLinkCleanup: last link gone -> clear binding, unbind requests, sessions", () => {
  for (const role of [null, "", "delegate", "Promoter"]) {
    const plan = identity.planDeletedLinkCleanup({ remainingLiveLinks: 0, usersRole: role });
    assert.deepEqual(plan, { clearDeviceBinding: true, cancelUnbindRequests: true, revokeSessions: true, reason: "no_links_left" }, String(role));
  }
});

const REAL = {
  id: "d1", status: "active", companyId: "c1", orgId: "o1", createdAtMillis: 1,
  nationalIdMatches: true, phoneMatchesLogin: true, phone: "01234567890", hasIdentity: true,
};

test("evaluateCandidates: only ghost matches -> profile_missing", () => {
  const ghost = { ...REAL, hasIdentity: false };
  assert.equal(logic.evaluateCandidates([ghost]).outcome, "profile_missing");
});

test("evaluateCandidates: a ghost next to a real profile is dropped from the token", () => {
  const ghost = { ...REAL, id: "g1", companyId: "c2", hasIdentity: false };
  const decision = logic.evaluateCandidates([ghost, REAL]);
  assert.equal(decision.outcome, "ok");
  assert.deepEqual(decision.ids, ["d1"]);
  assert.equal(decision.primary.id, "d1");
});

test("evaluateCandidates: deleted status -> deleted; one live copy still signs in", () => {
  assert.equal(logic.evaluateCandidates([{ ...REAL, status: "deleted" }]).outcome, "deleted");
  const decision = logic.evaluateCandidates([{ ...REAL, id: "x", status: "removed" }, REAL]);
  assert.equal(decision.outcome, "ok");
  assert.deepEqual(decision.ids, ["d1"]);
});

test("evaluateCandidates: hasIdentity missing keeps the old behaviour", () => {
  const legacy = { ...REAL };
  delete legacy.hasIdentity;
  assert.equal(logic.evaluateCandidates([legacy]).outcome, "ok");
});
