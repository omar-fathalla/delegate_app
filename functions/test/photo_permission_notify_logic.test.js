const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/photo_permission_notify_logic");

test("notifies only company admin/supervisor of the delegate company", () => {
  const users = [
    {id: "supA", role: "admin", companyUID: "coA"},
    {id: "supHyphen", role: "company-admin", companyUID: "coA"},
    {id: "supB", role: "admin", companyUID: "coB"},
    {id: "oa", role: "organization-admin", companyUID: "coA"},
    {id: "oaOther", role: "organizationAdmin", companyUID: "coB"},
    {id: "hr", role: "hr", companyUID: "coA"},
  ];
  assert.deepEqual(L.photoPermissionNotifyUserIds(users, "coA").sort(), ["supA", "supHyphen"]);
});

test("empty company yields no recipients", () => {
  assert.deepEqual(L.photoPermissionNotifyUserIds([{id: "supA", role: "admin", companyUID: "coA"}], ""), []);
});
