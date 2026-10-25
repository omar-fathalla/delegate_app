const test = require("node:test");
const assert = require("node:assert/strict");
const logic = require("../lib/delegate_login_logic");

test("normalizePhone accepts the formats stored on existing delegates", () => {
  assert.equal(logic.normalizePhone("+20 123 456 7890"), "01234567890");
  assert.equal(logic.normalizePhone("00201234567890"), "01234567890");
  assert.equal(logic.normalizePhone("1234567890"), "01234567890");
  assert.equal(logic.normalizePhone("٠١٢٣٤٥٦٧٨٩٠"), "01234567890");
  assert.equal(logic.normalizePhone("۰۱۲۳۴۵۶۷۸۹۰"), "01234567890");
  assert.equal(logic.normalizePhone("01234567890"), "01234567890");
});

test("phoneQueryVariants covers local, country, and international forms", () => {
  const variants = logic.phoneQueryVariants("01234567890");
  assert.ok(variants.includes("01234567890"));
  assert.ok(variants.includes("+201234567890"));
  assert.ok(variants.includes("201234567890"));
  assert.ok(variants.includes("00201234567890"));
  assert.ok(variants.includes("1234567890"));
});

test("validateLoginInput requires both fields and rejects short secrets", () => {
  assert.deepEqual(logic.validateLoginInput("", "12345678901234"), {
    ok: false,
    reason: "missing_phone",
  });
  assert.deepEqual(logic.validateLoginInput("01234567890", "  "), {
    ok: false,
    reason: "missing_national_id",
  });
  assert.equal(logic.validateLoginInput("01234567890", "123").ok, false);
  const ok = logic.validateLoginInput("+201234567890", "٢٩٧١٢٢٠٠٢٠١٩٨١");
  assert.equal(ok.ok, true);
  assert.equal(ok.phone, "01234567890");
  assert.equal(ok.nationalId, "29712200201981");
});

test("nationalIdsMatch ignores spaces and Arabic digits", () => {
  assert.equal(logic.nationalIdsMatch("2971 2200 201981", "٢٩٧١٢٢٠٠٢٠١٩٨١"), true);
  assert.equal(logic.nationalIdsMatch("29712200201981", "29712200201982"), false);
  assert.equal(logic.nationalIdsMatch("", "29712200201981"), false);
  assert.equal(logic.nationalIdsMatch("123", "1234"), false);
});

test("status gate rejects pending and blocked and allows legacy empty status", () => {
  assert.equal(logic.isLoginDenied("pending"), true);
  assert.equal(logic.isLoginDenied("Blocked"), true);
  assert.equal(logic.isLoginDenied("suspended"), true);
  assert.equal(logic.isLoginDenied("rejected"), true);
  assert.equal(logic.isLoginDenied("inactive"), true);
  assert.equal(logic.isLoginDenied("approved"), false);
  assert.equal(logic.isLoginDenied("active"), false);
  assert.equal(logic.isLoginDenied(""), false);
  assert.equal(logic.isLoginDenied(null), false);
  assert.equal(logic.isLoginDenied("enabled"), false);
});

test("evaluateCandidates never treats a national-id miss as success", () => {
  const base = {
    id: "doc-a",
    status: "active",
    companyId: "c1",
    orgId: "o1",
    createdAtMillis: 10,
    nationalIdMatches: false,
  };
  assert.equal(logic.evaluateCandidates([]).outcome, "not_found");
  assert.equal(logic.evaluateCandidates([base]).outcome, "bad_credentials");
  assert.equal(
    logic.evaluateCandidates([{ ...base, nationalIdMatches: true, status: "pending" }]).outcome,
    "inactive",
  );
});

test("evaluateCandidates keeps every allowed profile and picks a stable primary", () => {
  const decision = logic.evaluateCandidates([
    {
      id: "b",
      status: "pending",
      companyId: "c2",
      orgId: "o2",
      createdAtMillis: 1,
      nationalIdMatches: true,
    },
    {
      id: "z",
      status: "active",
      companyId: "c2",
      orgId: "o2",
      createdAtMillis: 50,
      nationalIdMatches: true,
    },
    {
      id: "a",
      status: "approved",
      companyId: "c1",
      orgId: "o1",
      createdAtMillis: 50,
      nationalIdMatches: true,
    },
  ]);
  assert.equal(decision.outcome, "ok");
  assert.equal(decision.primary.id, "a");
  assert.deepEqual(decision.ids, ["a", "z"]);
});

test("custom claims carry role and ids and never a national id", () => {
  const primary = {
    id: "delegate-doc",
    status: "active",
    companyId: "company-1",
    orgId: "org-1",
    createdAtMillis: 1,
    nationalIdMatches: true,
  };
  const other = { ...primary, id: "delegate-doc-2", companyId: "company-2", orgId: "org-2" };
  const claims = logic.buildCustomClaimsForProfiles(
    [primary, other],
    primary,
    ["delegate-doc", "delegate-doc-2"],
  );
  assert.equal(claims.role, "delegate");
  assert.equal(claims.delegateId, "delegate-doc");
  assert.equal(claims.companyId, "company-1");
  assert.equal(claims.orgId, "org-1");
  assert.deepEqual(claims.companyIds, ["company-1", "company-2"]);
  assert.deepEqual(claims.orgIds, ["org-1", "org-2"]);
  assert.equal(Object.prototype.hasOwnProperty.call(claims, "nationalId"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(claims, "nationalityID"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(claims, "phones"), false);
  assert.equal(logic.stableDelegateAuthUid("delegate-doc"), "delegate-doc");
});

test("custom claims include phone variants and never the national id", () => {
  const claims = logic.buildCustomClaims({
    id: "delegate-doc",
    status: "active",
    companyId: "company-1",
    orgId: "org-1",
    phone: "01234567890",
    createdAtMillis: 1,
    nationalIdMatches: true,
  }, ["delegate-doc"]);
  assert.ok(claims.phones.includes("01234567890"));
  assert.ok(claims.phones.includes("+201234567890"));
  assert.equal(Object.prototype.hasOwnProperty.call(claims, "nationalId"), false);
});

test("rate limit locks on the fifth failure and does not extend an active lock", () => {
  let state = null;
  const start = 1_000_000;
  for (let i = 0; i < 4; i++) {
    state = logic.recordFailedAttempt(state, start + i);
    assert.equal(state.locked, false);
  }
  state = logic.recordFailedAttempt(state, start + 4);
  assert.equal(state.locked, true);
  const lockedUntil = state.lockedUntilMs;
  const again = logic.recordFailedAttempt(state, start + 10);
  assert.equal(again.locked, true);
  assert.equal(again.lockedUntilMs, lockedUntil);

  const cleared = logic.clearedRateLimit(start + 20);
  assert.equal(cleared.failCount, 0);
  assert.equal(cleared.lockedUntilMs, 0);
});

test("extracts national id and phone aliases without preferring unrelated fields", () => {
  assert.equal(
    logic.extractNationalId({ nationalId: "111", nationalityID: "222" }),
    "222",
  );
  assert.equal(logic.extractPhone({ phone: "01000000000" }), "01000000000");
  const path = logic.idsFromDelegatePath(
    "organizations/org9/companies/co9/delegates/d9",
  );
  assert.deepEqual(path, { orgId: "org9", companyId: "co9" });
});
