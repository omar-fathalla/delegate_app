// TAS-112: a delegate changes its phone with an OTP on the new number.
const {describe, test} = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/delegate_phone_change_logic");

const own = [{path: "organizations/o/companies/c/delegates/d1", id: "d1", phone: "01000000001", nationalId: "29001010000001"}];
const parsed = {newPhone: "01000000002", nationalId: "29001010000001"};
const base = {parsed, own, otherDelegateWithPhone: false, staffWithPhone: false, requestsToday: 0};

describe("parseRequest", () => {
  test("normalizes the new number", () => {
    assert.deepEqual(L.parseRequest({newPhone: "+20 100 000 0002", nationalId: " 29001010000001 "}),
      {newPhone: "01000000002", nationalId: " 29001010000001 "});
  });
  test("bad phone / missing national ID", () => {
    assert.equal(L.parseRequest({newPhone: "123", nationalId: "1"}).reason, "bad_phone");
    assert.equal(L.parseRequest({newPhone: "01000000002"}).reason, "bad_national_id");
  });
});

describe("ownDocs", () => {
  test("keeps only the caller's ids, once per path", () => {
    const found = [
      own[0], own[0],
      {path: "organizations/o2/companies/c/delegates/d1", id: "d1", phone: "", nationalId: ""},
      {path: "organizations/o/companies/c/delegates/other", id: "other", phone: "", nationalId: ""},
    ];
    const r = L.ownDocs("d1", {delegateIds: ["d1"]}, found);
    assert.deepEqual(r.map((d) => d.path), [own[0].path, "organizations/o2/companies/c/delegates/d1"]);
  });
});

describe("decideRequest", () => {
  test("ok", () => assert.deepEqual(L.decideRequest(base), {ok: true}));
  test("wrong national ID", () =>
    assert.equal(L.decideRequest({...base, parsed: {...parsed, nationalId: "29001010000009"}}).reason, "national_id_mismatch"));
  test("same number", () =>
    assert.equal(L.decideRequest({...base, parsed: {...parsed, newPhone: "01000000001"}}).reason, "same_phone"));
  test("number of another delegate or staff", () => {
    assert.equal(L.decideRequest({...base, otherDelegateWithPhone: true}).reason, "phone_taken");
    assert.equal(L.decideRequest({...base, staffWithPhone: true}).reason, "phone_taken");
  });
  test("rate limit", () =>
    assert.equal(L.decideRequest({...base, requestsToday: L.PHONE_CHANGE_MAX_PER_DAY}).reason, "too_many"));
  test("no profile", () => assert.equal(L.decideRequest({...base, own: []}).reason, "no_profile"));
});

describe("decideConfirm", () => {
  const pending = {newPhone: "01000000002", status: "pending", expiresAtMs: 2000};
  const ok = {pending, authPhoneE164: "+201000000002", nowMs: 1000, otherDelegateWithPhone: false, staffWithPhone: false};
  test("ok when Auth holds the new number", () =>
    assert.deepEqual(L.decideConfirm(ok), {ok: true, newPhone: "01000000002"}));
  test("Auth still has the old number (OTP not done)", () =>
    assert.equal(L.decideConfirm({...ok, authPhoneE164: "+201000000001"}).reason, "phone_not_verified"));
  test("no Auth phone", () => assert.equal(L.decideConfirm({...ok, authPhoneE164: undefined}).reason, "phone_not_verified"));
  test("expired / missing / used request", () => {
    assert.equal(L.decideConfirm({...ok, nowMs: 3000}).reason, "expired");
    assert.equal(L.decideConfirm({...ok, pending: null}).reason, "no_request");
    assert.equal(L.decideConfirm({...ok, pending: {...pending, status: "done"}}).reason, "no_request");
  });
  test("taken meanwhile", () =>
    assert.equal(L.decideConfirm({...ok, otherDelegateWithPhone: true}).reason, "phone_taken"));
});

describe("claims and patches", () => {
  test("phones follow the new number; OTP stays verified when required", () => {
    const c = L.nextClaims({role: "delegate", phones: ["01000000001"], otp_required: true, otp_verified: true}, "01000000002");
    assert.ok(c.phones.includes("01000000002"));
    assert.ok(!c.phones.includes("01000000001"));
    assert.equal(c.otp_verified, true);
    assert.equal(c.role, "delegate");
    assert.equal(L.nextClaims({role: "delegate"}, "01000000002").otp_verified, undefined);
  });
  test("patch writes phone only when the copy uses it", () => {
    assert.deepEqual(L.delegatePatch({phoneNumber: "x"}, "01000000002"), {phoneNumber: "01000000002"});
    assert.deepEqual(L.delegatePatch({phone: "x"}, "01000000002"), {phoneNumber: "01000000002", phone: "01000000002"});
  });
  test("mask and E.164", () => {
    assert.equal(L.maskPhone("01000000002"), "0100****002");
    assert.equal(L.toE164("01000000002"), "+201000000002");
  });
});

// TAS-112 (user decision 2026-11-24): UAE mobiles too.
const LL = require("../lib/delegate_login_logic");
describe("UAE numbers", () => {
  test("every UAE form normalizes to 05xxxxxxxx", () => {
    for (const raw of ["+971 50 123 4567", "00971501234567", "971501234567", "0501234567", "501234567", "+٩٧١٥٠١٢٣٤٥٦٧"]) {
      assert.equal(LL.normalizePhone(raw), "0501234567", raw);
    }
  });
  test("Egyptian forms are unchanged", () => {
    for (const raw of ["+201000000002", "00201000000002", "1000000002", "01000000002"]) {
      assert.equal(LL.normalizePhone(raw), "01000000002", raw);
    }
  });
  test("variants cover the stored UAE forms", () => {
    const v = LL.phoneQueryVariants("0501234567");
    for (const x of ["0501234567", "501234567", "971501234567", "+971501234567", "00971501234567"]) assert.ok(v.includes(x), x);
  });
  test("E.164", () => {
    assert.equal(LL.phoneToE164("0501234567"), "+971501234567");
    assert.equal(LL.phoneToE164("01000000002"), "+201000000002");
    assert.equal(LL.phoneToE164("0601234567"), "");
    assert.equal(L.toE164("0501234567"), "+971501234567");
  });
  test("phone change accepts a UAE number and confirms against the +971 Auth phone", () => {
    assert.deepEqual(L.parseRequest({newPhone: "+971501234567", nationalId: "1"}), {newPhone: "0501234567", nationalId: "1"});
    assert.equal(L.parseRequest({newPhone: "+966501234567", nationalId: "1"}).reason, "bad_phone");
    const r = L.decideConfirm({pending: {newPhone: "0501234567", status: "pending", expiresAtMs: 2000},
      authPhoneE164: "+971501234567", nowMs: 1000, otherDelegateWithPhone: false, staffWithPhone: false});
    assert.deepEqual(r, {ok: true, newPhone: "0501234567"});
  });
  test("login accepts a UAE number and OTP claims match it", () => {
    const v = LL.validateLoginInput("+971501234567", "29001010000001");
    assert.equal(v.ok, true);
    assert.equal(v.phone, "0501234567");
    assert.equal(LL.phoneMatchesDelegateClaims("+971501234567", LL.phoneQueryVariants("0501234567")), true);
  });
});
