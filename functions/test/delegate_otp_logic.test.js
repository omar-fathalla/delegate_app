const test = require("node:test");
const assert = require("node:assert/strict");
const logic = require("../lib/delegate_login_logic");

test("parseOtpEnforcementEnabled is off unless the field is boolean true", () => {
  assert.equal(logic.parseOtpEnforcementEnabled(null), false);
  assert.equal(logic.parseOtpEnforcementEnabled({}), false);
  assert.equal(logic.parseOtpEnforcementEnabled({otpEnforcementEnabled: false}), false);
  assert.equal(logic.parseOtpEnforcementEnabled({otpEnforcementEnabled: "true"}), false);
  assert.equal(logic.parseOtpEnforcementEnabled({otpEnforcementEnabled: 1}), false);
  assert.equal(logic.parseOtpEnforcementEnabled({otpEnforcementEnabled: true}), true);
});

test("applyOtpEnforcementClaims adds otp flags only when enforcement is on", () => {
  const base = {role: "delegate", delegateId: "d1", phones: ["01234567890"]};
  const off = logic.applyOtpEnforcementClaims(base, false);
  assert.equal(Object.prototype.hasOwnProperty.call(off, "otp_required"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(off, "otp_verified"), false);
  assert.equal(off.role, "delegate");

  const on = logic.applyOtpEnforcementClaims(base, true);
  assert.equal(on.otp_required, true);
  assert.equal(on.otp_verified, false);
  assert.equal(on.role, "delegate");
  assert.deepEqual(on.phones, ["01234567890"]);
});

test("phoneMatchesDelegateClaims accepts E.164 against local claim variants", () => {
  const phones = logic.phoneQueryVariants("01234567890");
  assert.equal(logic.phoneMatchesDelegateClaims("+201234567890", phones), true);
  assert.equal(logic.phoneMatchesDelegateClaims("+201111111111", phones), false);
  assert.equal(logic.phoneMatchesDelegateClaims("", phones), false);
  assert.equal(logic.phoneMatchesDelegateClaims("+201234567890", null), false);
  assert.equal(logic.phoneMatchesDelegateClaims("+201234567890", []), false);
});

test("decideConfirmDelegateOtp rejects missing phone, wrong role, and mismatch", () => {
  assert.equal(
    logic.decideConfirmDelegateOtp({authPhone: "+201234567890", claims: null}).reason,
    "not_delegate",
  );
  assert.equal(
    logic.decideConfirmDelegateOtp({
      authPhone: null,
      claims: {role: "delegate", phones: ["01234567890"]},
    }).reason,
    "phone_not_linked",
  );
  assert.equal(
    logic.decideConfirmDelegateOtp({
      authPhone: "+201111111111",
      claims: {role: "delegate", phones: ["01234567890"]},
    }).reason,
    "phone_mismatch",
  );
});

test("decideConfirmDelegateOtp sets otp_verified when the linked phone matches", () => {
  const decision = logic.decideConfirmDelegateOtp({
    authPhone: "+201234567890",
    claims: {
      role: "delegate",
      delegateId: "d1",
      phones: ["01234567890", "+201234567890"],
      otp_required: true,
      otp_verified: false,
    },
  });
  assert.equal(decision.ok, true);
  assert.equal(decision.nextClaims.otp_verified, true);
  assert.equal(decision.nextClaims.otp_required, true);
  assert.equal(decision.nextClaims.role, "delegate");
  assert.equal(decision.nextClaims.delegateId, "d1");
});

test("decideConfirmDelegateOtp still verifies when enforcement claims are absent", () => {
  const decision = logic.decideConfirmDelegateOtp({
    authPhone: "+201234567890",
    claims: {role: "delegate", phones: ["01234567890"]},
  });
  assert.equal(decision.ok, true);
  assert.equal(decision.nextClaims.otp_verified, true);
});
