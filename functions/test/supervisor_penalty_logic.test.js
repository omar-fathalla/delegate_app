// TAS-320: a supervisor delegate records a penalty on a delegate of its company.
const {describe, test} = require("node:test");
const assert = require("node:assert/strict");
const {parsePenaltyInput, isSupervisorPosition, isActiveDelegate, callerDelegateIds, buildPenaltyDoc, MAX_FINE} =
  require("../lib/supervisor_penalty_logic");

const good = {targetDelegateId: "d2", title: "تأخير", category: "protocol_breach", fineAmount: 50};

describe("parsePenaltyInput", () => {
  test("accepts a valid request and normalises the category", () => {
    const r = parsePenaltyInput(good);
    assert.equal(r.category, "PROTOCOL_BREACH");
    assert.equal(r.fineAmount, 50);
  });
  test("defaults the category to OTHER", () => {
    assert.equal(parsePenaltyInput({...good, category: ""}).category, "OTHER");
  });
  test("refuses missing target, short title, bad category, bad amounts", () => {
    for (const bad of [
      {...good, targetDelegateId: ""}, {...good, targetDelegateId: "a/b"},
      {...good, title: "x"}, {...good, category: "HACK"},
      {...good, fineAmount: 0}, {...good, fineAmount: -5}, {...good, fineAmount: MAX_FINE + 1}, {...good, fineAmount: "abc"},
    ]) assert.ok("error" in parsePenaltyInput(bad), JSON.stringify(bad));
  });
});

describe("supervisor and target checks", () => {
  test("supervisor positions", () => {
    assert.ok(isSupervisorPosition("Supervisor"));
    assert.ok(isSupervisorPosition("مشرف"));
    assert.ok(!isSupervisorPosition("Promoter"));
  });
  test("deleted / rejected delegates are not active", () => {
    assert.ok(isActiveDelegate({status: "active"}));
    assert.ok(isActiveDelegate({status: "suspended"}));
    assert.ok(!isActiveDelegate({status: "deleted"}));
    assert.ok(!isActiveDelegate(undefined));
  });
  test("caller ids are the uid plus the delegateIds claim", () => {
    assert.deepEqual(callerDelegateIds("u1", {delegateIds: ["d1", "u1", ""]}), ["u1", "d1"]);
  });
});

describe("buildPenaltyDoc", () => {
  test("is ISSUED at once and scoped to the company", () => {
    const doc = buildPenaltyDoc({input: parsePenaltyInput(good), organizationUID: "o1", companyUID: "c1",
      companyName: "Co", supervisorId: "s1", supervisorName: "مشرف", supervisorPhone: "", targetName: "مندوب"});
    assert.equal(doc.status, "ISSUED");
    assert.equal(doc.companyId, "c1");
    assert.equal(doc.organizationId, "o1");
    assert.equal(doc.targetDelegateId, "d2");
    assert.equal(doc.createdByRole, "supervisor_delegate");
    assert.equal(doc.fineAmount, 50);
  });
});
