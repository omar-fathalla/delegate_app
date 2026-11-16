const {describe, test} = require("node:test");
const assert = require("node:assert/strict");
const logic = require("../lib/staff_phones_claim_logic");
const {phoneQueryVariants, normalizePhone} = require("../lib/delegate_login_logic");

describe("staff_phones_claim_logic", () => {
  test("staffPhonesFromStoredPhone matches delegate phoneQueryVariants", () => {
    const raw = "01012000005";
    assert.deepEqual(
      logic.staffPhonesFromStoredPhone(raw),
      phoneQueryVariants(normalizePhone(raw)),
    );
  });

  test("staffPhonesFromStoredPhone clears on empty", () => {
    assert.deepEqual(logic.staffPhonesFromStoredPhone(""), []);
    assert.deepEqual(logic.staffPhonesFromStoredPhone(null), []);
  });

  test("mergeStaffPhonesClaims preserves role fields", () => {
    const merged = logic.mergeStaffPhonesClaims(
      {role: "hr", orgId: "o1"},
      {action: "set", phones: ["01012000005"]},
    );
    assert.equal(merged.role, "hr");
    assert.deepEqual(merged.phones, ["01012000005"]);
    const cleared = logic.mergeStaffPhonesClaims(merged, {action: "clear"});
    assert.equal(cleared.role, "hr");
    assert.equal(cleared.phones, undefined);
  });

  test("decideStaffPhonesMint refuses collision (attack victim phone)", () => {
    const d = logic.decideStaffPhonesMint("01000000002", true, false);
    assert.equal(d.action, "skip");
    assert.equal(d.reason, "phone_collision");
  });

  test("decideStaffPhonesMint sets when no collision", () => {
    const d = logic.decideStaffPhonesMint("01012000005", false);
    assert.equal(d.action, "set");
    assert.ok(d.phones?.includes("01012000005"));
  });

  test("decideStaffPhonesMint clears when phone removed", () => {
    const d = logic.decideStaffPhonesMint("", false);
    assert.equal(d.action, "clear");
  });
});