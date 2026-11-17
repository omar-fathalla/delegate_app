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

  test("decideStaffPhonesMint clears on collision (attack victim phone)", () => {
    const d = logic.decideStaffPhonesMint("01000000002", true);
    assert.equal(d.action, "clear");
    assert.equal(d.reason, "phone_collision");
    const merged = logic.mergeStaffPhonesClaims({role: "hr", phones: ["01000000001"]}, d);
    assert.equal(merged.phones, undefined);
    assert.equal(merged.role, "hr");
  });

  test("docHoldsPhone normalizes every phone field", () => {
    const target = normalizePhone("01055500003");
    assert.ok(logic.docHoldsPhone({phone: "01055500003"}, target));
    assert.ok(logic.docHoldsPhone({phoneNumber: "+20 105 550 0003"}, target));
    assert.ok(logic.docHoldsPhone({mobileNumber: "0020-105-550-0003"}, target));
    assert.ok(logic.docHoldsPhone({mobile: "٠١٠٥٥٥٠٠٠٠٣"}, target));
    assert.ok(logic.docHoldsPhone({phoneNumber: 1055500003}, target));
    assert.ok(!logic.docHoldsPhone({phoneNumber: "01055500004", email: "01055500003"}, target));
    assert.ok(!logic.docHoldsPhone(undefined, target));
  });

  test("phoneCollisionQueryValues fits one `in` query and includes numeric forms", () => {
    const values = logic.phoneCollisionQueryValues("01055500003");
    assert.ok(values.length <= 10);
    assert.ok(values.includes("+201055500003"));
    assert.ok(values.includes(1055500003));
    assert.ok(values.includes(201055500003));
  });

  test("resolveStaffMintPhone prefers the Auth phone", () => {
    assert.deepEqual(logic.resolveStaffMintPhone("+201000000009", "01055500003"),
      {source: "auth", phone: "+201000000009"});
    assert.deepEqual(logic.resolveStaffMintPhone(undefined, " 01055500003 "),
      {source: "users_doc", phone: "01055500003"});
    assert.deepEqual(logic.resolveStaffMintPhone(null, ""), {source: "none", phone: ""});
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