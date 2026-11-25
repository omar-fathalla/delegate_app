// TAS-28 phase 0: callables name a delegate by its delegateId claim and still
// accept the old `auth.uid == delegate doc id` equality.
const {describe, test} = require("node:test");
const assert = require("node:assert/strict");
const {callerDelegateId, callerSelfIds} = require("../lib/caller_delegate_id");
const {callerDelegateIds} = require("../lib/supervisor_penalty_logic");
const {buildCustomClaims, stableDelegateAuthUid} = require("../lib/delegate_login_logic");
const {isTaskImageFolderId} = require("../lib/storage_upload_intent_logic");

describe("callerDelegateId", () => {
  test("today's token: claim and uid are the same id", () => {
    assert.equal(callerDelegateId("d1", {role: "delegate", delegateId: "d1"}), "d1");
  });
  test("prefers the claim when the uid differs (phase 1 dlg_ uid)", () => {
    assert.equal(callerDelegateId("dlg_abc", {role: "delegate", delegateId: "d1"}), "d1");
  });
  test("old token without the claim falls back to the uid", () => {
    assert.equal(callerDelegateId("d1", {role: "delegate"}), "d1");
  });
  test("staff token: always the uid, even with a stray delegateId claim", () => {
    assert.equal(callerDelegateId("staff1", {role: "admin", delegateId: "d1"}), "staff1");
    assert.equal(callerDelegateId("staff1", undefined), "staff1");
  });
  test("blank / non-string claim is ignored", () => {
    assert.equal(callerDelegateId("d1", {role: "delegate", delegateId: "  "}), "d1");
    assert.equal(callerDelegateId("d1", {role: "delegate", delegateId: 7}), "d1");
  });
});

describe("callerSelfIds", () => {
  test("uid and claim, deduplicated", () => {
    assert.deepEqual(callerSelfIds("d1", {role: "delegate", delegateId: "d1"}), ["d1"]);
    assert.deepEqual(callerSelfIds("dlg_x", {role: "delegate", delegateId: "d1"}), ["dlg_x", "d1"]);
  });
  test("staff: uid only", () => {
    assert.deepEqual(callerSelfIds("s1", {role: "hr", delegateId: "d1"}), ["s1"]);
  });
  test("task image folder: the uid name and the claim name are both the caller's", () => {
    const ids = callerSelfIds("dlg_x", {role: "delegate", delegateId: "d1"});
    assert.ok(ids.some((id) => isTaskImageFolderId("task_d1_123.jpg", id)));
    assert.ok(ids.some((id) => isTaskImageFolderId("task_dlg_x_123.jpg", id)));
    assert.ok(!ids.some((id) => isTaskImageFolderId("task_d2_123.jpg", id)));
  });
});

describe("supervisor penalty callerDelegateIds", () => {
  test("includes the delegateId claim", () => {
    assert.deepEqual(
      callerDelegateIds("dlg_x", {delegateId: "d1", delegateIds: ["d1", "d9"]}).sort(),
      ["d1", "d9", "dlg_x"],
    );
  });
});

describe("delegateLoginV2 already sets the claim (phase 0 precondition)", () => {
  test("delegateId claim == primary id == Auth uid for normal ids", () => {
    const claims = buildCustomClaims({id: "d1", companyId: "c1", orgId: "o1", phone: "01000000001"}, ["d1"]);
    assert.equal(claims.delegateId, "d1");
    assert.equal(stableDelegateAuthUid("d1"), claims.delegateId);
  });
  test("ids over 128 chars: uid is a hash, the claim still names the doc", () => {
    const long = "x".repeat(130);
    const claims = buildCustomClaims({id: long}, [long]);
    assert.equal(claims.delegateId, long);
    assert.notEqual(stableDelegateAuthUid(long), long);
    assert.equal(callerDelegateId(stableDelegateAuthUid(long), claims), long);
  });
});
