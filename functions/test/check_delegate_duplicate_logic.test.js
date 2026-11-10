const test = require("node:test");
const assert = require("node:assert");
const L = require("../lib/check_delegate_duplicate_logic");

test("normalizeIdDigits trims, strips spaces, and maps Arabic digits", () => {
  assert.strictEqual(L.normalizeIdDigits(" 291 0101 "), "2910101");
  assert.strictEqual(L.normalizeIdDigits("٢٩١٠١٠١"), "2910101");
});

test("no hits is not a duplicate", () => {
  assert.deepStrictEqual(L.decideDuplicate("c1", []), {duplicate: false});
  assert.deepStrictEqual(L.publicDuplicateResult({duplicate: false}), {duplicate: false});
});

test("a hit in the caller's company is same_company and never returns a company name", () => {
  const d = L.decideDuplicate("c1", [
    {companyUID: "c1", companyName: "Acme", field: "nationalId"},
  ]);
  assert.deepStrictEqual(d, {duplicate: true, reason: "same_company", field: "nationalId"});
  assert.deepStrictEqual(L.publicDuplicateResult(d), {duplicate: true, reason: "same_company"});
});

test("a hit in another company returns only that company's name", () => {
  const d = L.decideDuplicate("c1", [
    {companyUID: "c2", companyName: "شركة النور", field: "phoneNumber"},
  ]);
  assert.strictEqual(d.duplicate, true);
  assert.strictEqual(d.reason, "another_company");
  assert.strictEqual(d.companyName, "شركة النور");
  assert.deepStrictEqual(L.publicDuplicateResult(d), {
    duplicate: true,
    reason: "another_company",
    companyName: "شركة النور",
  });
});

test("same-company takes precedence over a cross-company hit", () => {
  const d = L.decideDuplicate("c1", [
    {companyUID: "c2", companyName: "Other", field: "nationalId"},
    {companyUID: "c1", companyName: "Mine", field: "nationalId"},
  ]);
  assert.strictEqual(d.reason, "same_company");
  assert.ok(!d.companyName);
});

test("open request and existing delegate status gates", () => {
  assert.ok(L.isOpenRequestStatus("pending"));
  assert.ok(L.isOpenRequestStatus("approved"));
  assert.ok(!L.isOpenRequestStatus("rejected"));
  assert.ok(!L.isOpenRequestStatus("cancelled"));
  assert.ok(L.isExistingDelegateStatus("active"));
  assert.ok(L.isExistingDelegateStatus("suspended"));
  assert.ok(!L.isExistingDelegateStatus("inactive"));
});

test("normalizeEgyptianPhone folds +20, 0020, dashes, and spaces to 01xxxxxxxxx", () => {
  assert.strictEqual(L.normalizeEgyptianPhone("+201000000022"), "01000000022");
  assert.strictEqual(L.normalizeEgyptianPhone("00201000000022"), "01000000022");
  assert.strictEqual(L.normalizeEgyptianPhone("010-0000-0022"), "01000000022");
  assert.strictEqual(L.normalizeEgyptianPhone("010 0000 0022"), "01000000022");
  assert.strictEqual(L.normalizeEgyptianPhone("201000000022"), "01000000022");
  assert.strictEqual(L.normalizeEgyptianPhone("01000000022"), "01000000022");
});

test("phoneQueryVariants include local, +20, and 20 forms", () => {
  const v = L.phoneQueryVariants("+201000000022");
  assert.ok(v.includes("01000000022"));
  assert.ok(v.includes("201000000022") || v.includes("+201000000022"));
});

test("action_required is an open request status", () => {
  assert.ok(L.isOpenRequestStatus("action_required"));
});

test("isSameDelegateRecord matches id, uid, and request pointers", () => {
  assert.ok(L.isSameDelegateRecord({uid: "d1"}, "x", "d1"));
  assert.ok(L.isSameDelegateRecord({}, "d1", "d1"));
  assert.ok(L.isSameDelegateRecord({existingDelegateUid: "d1"}, "req", "d1"));
  assert.ok(!L.isSameDelegateRecord({uid: "d2"}, "x", "d1"));
  assert.ok(!L.isSameDelegateRecord({uid: "d1"}, "d1", ""));
});

test("phoneQueryVariants match stored dashes and spaces (L-1)", () => {
  const v = L.phoneQueryVariants("01000000073");
  assert.ok(v.includes("010-0000-0073"), v.join(","));
  assert.ok(v.includes("0100 000 0073"), v.join(","));
});

test("phoneQueryVariants include +20 spaced form (L-1)", () => {
  const v = L.phoneQueryVariants("01000000044");
  assert.ok(v.includes("+20 100 000 0044"), v.join(","));
});

test("isValidEgyptianNationalId requires 14 digits", () => {
  assert.ok(L.isValidEgyptianNationalId("29901010101011"));
  assert.ok(!L.isValidEgyptianNationalId("123"));
  assert.ok(!L.isValidEgyptianNationalId("abc' OR 1=1"));
  assert.ok(L.isValidEgyptianNationalId(L.normalizeIdDigits("٢٩٩٠١٠١٠١٠١٠١١")));
});

test("isValidEgyptianPhone accepts normalized 01xxxxxxxxx and rejects junk", () => {
  assert.ok(L.isValidEgyptianPhone("01000000022"));
  assert.ok(L.isValidEgyptianPhone("+201000000022"));
  assert.ok(L.isValidEgyptianPhone("010-0000-0022"));
  assert.ok(!L.isValidEgyptianPhone("abc"));
  assert.ok(!L.isValidEgyptianPhone("12345"));
  assert.ok(!L.isValidEgyptianPhone(""));
});

test("duplicateHitFromDoc treats missing companyUID as a legacy other-company hit", () => {
  const hit = L.duplicateHitFromDoc({organizationUID: "o9", fullName: "قديم"}, "phoneNumber");
  assert.strictEqual(hit.companyUID, "__legacy__:o9");
  assert.strictEqual(hit.companyName, "شركة غير محددة");
  assert.strictEqual(hit.field, "phoneNumber");
  const named = L.duplicateHitFromDoc({companyUID: "c1", companyName: "شركة 1"}, "nationalId");
  assert.strictEqual(named.companyUID, "c1");
  assert.strictEqual(named.companyName, "شركة 1");
});

test("isValidEgyptianNationalId enforces ^[0-9]{14}$ (M-5)", () => {
  assert.ok(L.isValidEgyptianNationalId("29001010100011"));
  assert.ok(!L.isValidEgyptianNationalId("2900101010001a"));
  assert.ok(!L.isValidEgyptianNationalId("2900-101010012"));
  assert.ok(!L.isValidEgyptianNationalId("٢٩٠٠١٠١٠١٠٠٠١١"));
  assert.ok(!L.isValidEgyptianNationalId("2900101010001"));
});
