// TAS-34: one push per notification doc, carrying the permission id.
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {pushDataFor} = require("../lib/notification_push_logic");

test("photo permission doc keeps its permissionId in the push data", () => {
  assert.deepEqual(pushDataFor({type: "photo_permission", organizationId: "o1", companyId: "c1", permissionId: "p1"}, "support_alert"), {
    type: "photo_permission", organizationId: "o1", companyId: "c1", taskId: "", permissionId: "p1",
  });
});

test("missing fields become empty strings and the fallback type applies", () => {
  assert.deepEqual(pushDataFor({taskId: "t1"}, "support_alert"), {
    type: "support_alert", organizationId: "", companyId: "", taskId: "t1",
  });
});
