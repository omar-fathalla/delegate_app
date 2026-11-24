// TAS-261: an old Build.ID binding moves once to the unique ANDROID_ID.
const {describe, test} = require("node:test");
const assert = require("node:assert/strict");
const {decideDeviceBinding} = require("../lib/delegate_login_logic");

const base = {approvedRequestId: null, pendingRequestId: null};

describe("decideDeviceBinding with a legacy id", () => {
  test("old Build.ID binding + same legacy id -> moved to the new aid_ id", () => {
    assert.deepEqual(
      decideDeviceBinding({...base, storedDeviceId: "TP1A.220624.014", requestedDeviceId: "aid_abc123", legacyDeviceId: "TP1A.220624.014"}),
      {action: "bind", deviceId: "aid_abc123", consumeRequestId: null},
    );
  });
  test("already on the new id -> allow", () => {
    assert.deepEqual(
      decideDeviceBinding({...base, storedDeviceId: "aid_abc123", requestedDeviceId: "aid_abc123", legacyDeviceId: "TP1A.220624.014"}),
      {action: "allow", deviceId: "aid_abc123"},
    );
  });
  test("an aid_ binding is never moved by a legacy id", () => {
    const r = decideDeviceBinding({...base, storedDeviceId: "aid_other", requestedDeviceId: "aid_abc123", legacyDeviceId: "aid_other"});
    assert.equal(r.action, "mismatch");
  });
  test("a different legacy id is a mismatch", () => {
    const r = decideDeviceBinding({...base, storedDeviceId: "TP1A.220624.014", requestedDeviceId: "aid_abc123", legacyDeviceId: "UP1A.231005.007"});
    assert.equal(r.action, "mismatch");
  });
  test("the new id must be an aid_ id to move a binding", () => {
    const r = decideDeviceBinding({...base, storedDeviceId: "TP1A.220624.014", requestedDeviceId: "uuid_x", legacyDeviceId: "TP1A.220624.014"});
    assert.equal(r.action, "mismatch");
  });
  test("no legacy id keeps the old behaviour", () => {
    assert.equal(decideDeviceBinding({...base, storedDeviceId: "TP1A.220624.014", requestedDeviceId: "aid_abc123"}).action, "mismatch");
    assert.equal(decideDeviceBinding({...base, storedDeviceId: "", requestedDeviceId: "aid_abc123"}).action, "bind");
  });
});
