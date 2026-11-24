// TAS-55: a delegate gets only name / phone / email / photo of its supervisors.
const {describe, test} = require("node:test");
const assert = require("node:assert/strict");
const {parseScope, toCard, cardsFrom, isDenial} = require("../lib/supervisor_cards_logic");

const tok = {role: "delegate", orgId: "o1", companyId: "c1"};

describe("parseScope", () => {
  test("defaults to the token's company", () => {
    assert.deepEqual(parseScope({}, tok), {organizationUID: "o1", companyUID: "c1"});
  });
  test("another company of the same delegate (orgIds / companyIds)", () => {
    const t = {...tok, orgIds: ["o1", "o2"], companyIds: ["c1", "c2"]};
    assert.deepEqual(parseScope({organizationUID: "o2", companyUID: "c2"}, t),
      {organizationUID: "o2", companyUID: "c2"});
  });
  test("a company the token does not cover is denied", () => {
    const r = parseScope({organizationUID: "o1", companyUID: "c9"}, tok);
    assert.ok(isDenial(r));
    assert.equal(r.reason, "other_company");
  });
  test("staff tokens and no token are denied", () => {
    assert.equal(parseScope({}, {role: "company-admin"}).reason, "not_delegate");
    assert.equal(parseScope({}, {}).reason, "not_delegate");
    assert.equal(parseScope({}, undefined).reason, "unauthenticated");
  });
  test("no company anywhere", () => {
    assert.equal(parseScope({}, {role: "delegate"}).reason, "no_company");
  });
});

describe("toCard", () => {
  test("keeps only the four allowed fields", () => {
    const card = toCard("s1", {
      fullName: "مشرف تجريبي", phoneNumber: "01000000009", email: "sup@example.test",
      profileImageUrl: "https://example.test/p.jpg",
      nationalityID: "29001010000000", documents: [{documentURL: "https://x"}], status: "active",
    });
    assert.deepEqual(card, {
      uid: "s1", displayName: "مشرف تجريبي", phoneNumber: "01000000009",
      email: "sup@example.test", photoUrl: "https://example.test/p.jpg",
    });
    assert.equal(Object.keys(card).length, 5);
  });
  test("name falls back like the app", () => {
    assert.equal(toCard("x", {firstName: "أ", lastName: "ب"}).displayName, "أ ب");
    assert.equal(toCard("x", {name: "ج"}).displayName, "ج");
  });
});

describe("cardsFrom", () => {
  test("skips the caller, inactive supervisors and duplicate phones", () => {
    const cards = cardsFrom("me", [
      {id: "me", data: {fullName: "أنا", phoneNumber: "01000000001", status: "active"}},
      {id: "s1", data: {fullName: "س1", phoneNumber: "01000000002", status: "active"}},
      {id: "s1b", data: {fullName: "س1 نسخة", phoneNumber: "01000000002", status: "active"}},
      {id: "s2", data: {fullName: "س2", phoneNumber: "01000000003", status: "suspended"}},
      {id: "s3", data: {fullName: "س3", phoneNumber: "01000000004"}},
    ]);
    assert.deepEqual(cards.map((c) => c.uid), ["s1", "s3"]);
  });
});
