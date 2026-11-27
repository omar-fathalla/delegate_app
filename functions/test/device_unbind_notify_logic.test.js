// TAS-367: one supervisor notification per new device-change request.
const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/device_unbind_notify_logic");
const D = require("../lib/delegate_login_logic");

test("pending request -> supervisor broadcast with a fixed id", () => {
  const n = L.unbindRequestNotification("r1", {status: "pending", companyUID: "c1", organizationUID: "o1",
    delegateName: "Fake Delegate", delegateUid: "d1", requestedDeviceModel: "SM-M315F"});
  assert.equal(n.id, "unbind_request_r1");
  assert.equal(n.doc.delegateUid, "supervisor_c1");
  assert.equal(n.doc.type, "device_unbind_request");
  assert.match(n.doc.body, /Fake Delegate/);
  assert.match(n.doc.body, /SM-M315F/);
});

test("no company or not pending -> nothing", () => {
  assert.equal(L.unbindRequestNotification("r2", {status: "pending"}), null);
  assert.equal(L.unbindRequestNotification("r3", {status: "approved", companyUID: "c1"}), null);
});

test("mismatch details: supervisor and request age only when known", () => {
  const full = D.deviceMismatchDetails({supervisorName: "Sup", supervisorPhone: "0100"}, 123);
  assert.deepEqual(full, {reason: "device_mismatch", requestStatus: "pending",
    supervisorName: "Sup", supervisorPhone: "0100", requestCreatedAtMs: 123});
  assert.deepEqual(D.deviceMismatchDetails({}, null), {reason: "device_mismatch", requestStatus: "pending"});
});
