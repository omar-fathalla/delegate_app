// TAS-49: staff phone / email change goes through updateOwnStaffContact.
const {describe, test} = require("node:test");
const assert = require("node:assert/strict");
const {
  parseContactRequest,
  callerAllowed,
  phoneTakenByOther,
  emailPatch,
  isDenial,
} = require("../lib/staff_contact_logic");

describe("parseContactRequest", () => {
  test("phone is normalized to 01xxxxxxxxx", () => {
    assert.deepEqual(parseContactRequest({field: "phone", value: "+20 100 000 0001"}), {
      field: "phone", phone: "01000000001",
    });
    assert.deepEqual(parseContactRequest({field: "phone", value: "1200000002"}), {
      field: "phone", phone: "01200000002",
    });
  });

  test("bad phone and bad field are refused", () => {
    for (const value of ["", "123", "0130000000", "0100000000099", "abc"]) {
      const r = parseContactRequest({field: "phone", value});
      assert.ok(isDenial(r), value);
      assert.equal(r.reason, "bad_phone");
    }
    assert.equal(parseContactRequest({field: "role", value: "x"}).reason, "bad_field");
    assert.equal(parseContactRequest(null).reason, "bad_field");
  });

  test("email takes no value (it is read from Firebase Auth)", () => {
    assert.deepEqual(parseContactRequest({field: "email", value: "someone@else.test"}), {field: "email"});
  });
});

describe("callerAllowed", () => {
  test("staff roles pass", () => {
    for (const role of ["hr", "company-admin", "organization_admin", "super-admin", "marketing", "accountant"]) {
      assert.equal(callerAllowed(undefined, {role}), null, role);
    }
  });

  test("delegates, non-staff and missing docs are refused", () => {
    assert.equal(callerAllowed("delegate", {role: "hr"}).reason, "delegate_token");
    assert.equal(callerAllowed(undefined, {role: "delegate"}).reason, "not_staff");
    assert.equal(callerAllowed(undefined, {role: ""}).reason, "not_staff");
    assert.equal(callerAllowed(undefined, undefined).reason, "no_user_doc");
  });
});

describe("phoneTakenByOther", () => {
  test("only another account counts", () => {
    assert.equal(phoneTakenByOther("me", []), false);
    assert.equal(phoneTakenByOther("me", ["me"]), false);
    assert.equal(phoneTakenByOther("me", ["me", "victim"]), true);
  });
});

describe("emailPatch", () => {
  test("copies the confirmed Auth email, lower-cased", () => {
    assert.deepEqual(emailPatch(" New@Example.TEST "), {email: "new@example.test"});
  });
  test("no Auth email is refused", () => {
    assert.equal(emailPatch(undefined).reason, "no_auth_email");
    assert.equal(emailPatch("").reason, "no_auth_email");
  });
});
