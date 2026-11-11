const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/photo_permission_notify_logic");

test("notifies company admin/supervisor of the delegate company", () => {
  const users = [
    {id: "supA", role: "admin", companyUID: "coA"},
    {id: "supHyphen", role: "company-admin", companyUID: "coA"},
    {id: "supB", role: "admin", companyUID: "coB"},
    {id: "hr", role: "hr", companyUID: "coA"},
  ];
  assert.deepEqual(L.photoPermissionNotifyUserIds(users, "coA", "o1").sort(), ["supA", "supHyphen"]);
});

test("notifies org-admins of the delegate org and skips other orgs", () => {
  const users = [
    {id: "oaSame", role: "organization-admin", companyUID: "coB", organizationUID: "o1"},
    {id: "oaIds", role: "organizationAdmin", organizationUIDs: ["o2", "o1"]},
    {id: "oaOther", role: "organization-admin", organizationUID: "o2"},
  ];
  assert.deepEqual(L.photoPermissionNotifyUserIds(users, "coA", "o1").sort(), ["oaIds", "oaSame"]);
});

test("notifies marketing-promotion of the same company and global approvers", () => {
  const users = [
    {id: "mpA", role: "marketingPromotion", companyUID: "coA"},
    {id: "mpB", role: "marketing-promotion", companyUID: "coB"},
    {id: "sa", role: "superAdmin"},
    {id: "tech", role: "technicalSupport"},
    {id: "acc", role: "accountant", companyUID: "coA"},
  ];
  assert.deepEqual(
    L.photoPermissionNotifyUserIds(users, "coA", "o1").sort(),
    ["mpA", "sa", "tech"],
  );
});

test("empty company yields no company-scoped recipients; global approvers still notify", () => {
  const users = [
    {id: "supA", role: "admin", companyUID: "coA"},
    {id: "sa", role: "super-admin"},
  ];
  assert.deepEqual(L.photoPermissionNotifyUserIds(users, "", "o1"), ["sa"]);
});
