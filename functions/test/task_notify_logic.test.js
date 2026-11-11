const {describe, test} = require("node:test");
const assert = require("node:assert/strict");
const {
  parseAssignedTo,
  taskNotifyUserIds,
  newlyAssignedTaskUserIds,
  isGroupAssignToken,
  userInCompany,
  isExcludedFromTaskNotify,
  taskUsersFromDelegateDocs,
  taskNotifyUserIdsFromSources,
  newlyAssignedTaskUserIdsFromSources,
  assignmentNeedsCompanyDelegates,
  assignmentNeedsSectorStaff,
} = require("../lib/task_notify_logic");

const co = "co_dev_test";
const org = "org_dev_test";

function u(id, overrides = {}) {
  return {id, companyUID: co, organizationUID: org, role: "delegate", ...overrides};
}

describe("parseAssignedTo", () => {
  test("a string uid is one recipient, not its characters", () => {
    const parsed = parseAssignedTo("dlg_dev_test_1");
    assert.deepEqual(parsed, {kind: "uids", uids: ["dlg_dev_test_1"]});
  });

  test("all and Arabic الكل are the all-delegates group", () => {
    assert.deepEqual(parseAssignedTo("all"), {kind: "group", token: "all"});
    assert.deepEqual(parseAssignedTo("الكل"), {kind: "group", token: "all"});
    assert.equal(isGroupAssignToken("all"), true);
    assert.equal(isGroupAssignToken("الكل"), true);
  });

  test("sector tokens stay groups", () => {
    assert.deepEqual(parseAssignedTo("all_branch_marketing"), {
      kind: "group", token: "all_branch_marketing",
    });
    assert.deepEqual(parseAssignedTo("all_marketing_promotion"), {
      kind: "group", token: "all_marketing_promotion",
    });
  });

  test("an array of uids is de-duplicated and not confused with a string", () => {
    assert.deepEqual(parseAssignedTo(["a", "b", "a"]), {kind: "uids", uids: ["a", "b"]});
  });

  test("empty values are empty", () => {
    assert.deepEqual(parseAssignedTo(""), {kind: "empty"});
    assert.deepEqual(parseAssignedTo([]), {kind: "empty"});
    assert.deepEqual(parseAssignedTo(null), {kind: "empty"});
  });
});

describe("taskNotifyUserIds: single person", () => {
  test("notifies only that uid, never the characters of the uid", () => {
    const users = [u("dlg_dev_test_1"), u("dlg_dev_test_2")];
    assert.deepEqual(
      taskNotifyUserIds(users, "dlg_dev_test_1", {companyId: co}),
      ["dlg_dev_test_1"],
    );
  });

  test("excludes a uid who belongs to another company", () => {
    const users = [u("other", {companyUID: "co_other"})];
    assert.deepEqual(
      taskNotifyUserIds(users, "other", {companyId: co}),
      [],
    );
  });

  test("keeps an explicit uid that is not in the candidate list", () => {
    assert.deepEqual(
      taskNotifyUserIds([], "dlg_missing", {companyId: co}),
      ["dlg_missing"],
    );
  });

  test("does not notify the creator when they assigned the task to themselves as part of a typo scan", () => {
    assert.deepEqual(
      taskNotifyUserIds([u("sup")], "sup", {companyId: co, createdBy: "sup"}),
      [],
    );
  });
});

describe("taskNotifyUserIds: all / الكل, company-scoped, no duplicates", () => {
  const users = [
    u("d1"),
    u("d2"),
    u("d1-dup"), // will be same id via companyIds test below
    u("mkt", {role: "marketing"}),
    u("promo", {role: "marketingPromotion"}),
    u("other-co", {companyUID: "co_other"}),
    u("sup", {role: "supervisor"}),
    u("hr", {role: "hr"}),
    u("oa", {role: "organization-admin"}),
    u("sa", {role: "super-admin", companyUID: ""}),
    u("pending", {status: "pending"}),
    u("rejected", {status: "rejected"}),
    u("multi", {companyUID: "co_home", companyIds: [co, "co_home"]}),
  ];

  test("all notifies company field delegates only, not sector staff or other companies", () => {
    const ids = taskNotifyUserIds(users, "all", {companyId: co, createdBy: "sup"});
    assert.deepEqual(ids.sort(), ["d1", "d2", "d1-dup", "multi"].sort());
  });

  test("Arabic الكل matches all", () => {
    const a = taskNotifyUserIds(users, "all", {companyId: co});
    const b = taskNotifyUserIds(users, "الكل", {companyId: co});
    assert.deepEqual(a, b);
  });

  test("all with no company id notifies nobody (fail closed)", () => {
    assert.deepEqual(taskNotifyUserIds(users, "all", {organizationId: org}), []);
  });

  test("duplicates across the user list are collapsed", () => {
    const dup = [u("d1"), u("d1", {role: "delegate"})];
    assert.deepEqual(taskNotifyUserIds(dup, "all", {companyId: co}), ["d1"]);
  });

  test("the creator is not notified when they send to all", () => {
    const ids = taskNotifyUserIds(
      [u("d1"), u("creator-also-delegate")],
      "all",
      {companyId: co, createdBy: "creator-also-delegate"},
    );
    assert.deepEqual(ids, ["d1"]);
  });
});

describe("taskNotifyUserIds: sector groups", () => {
  const users = [
    u("d1"),
    u("mkt", {role: "marketing"}),
    u("mkt-other", {role: "marketing", companyUID: "co_other"}),
    u("mkt-org", {role: "marketing", companyUID: ""}),
    u("promo", {role: "marketingPromotion"}),
    u("promo-org", {role: "marketingPromotion", companyUID: ""}),
  ];

  test("all_branch_marketing is company marketing only, plus org-level marketing", () => {
    const ids = taskNotifyUserIds(users, "all_branch_marketing", {
      companyId: co, organizationId: org,
    });
    assert.deepEqual(ids.sort(), ["mkt", "mkt-org"].sort());
  });

  test("all_marketing_promotion is company promo only, plus org-level promo", () => {
    const ids = taskNotifyUserIds(users, "all_marketing_promotion", {
      companyId: co, organizationId: org,
    });
    assert.deepEqual(ids.sort(), ["promo", "promo-org"].sort());
  });

  test("other-company marketing is not notified", () => {
    const ids = taskNotifyUserIds(users, "all_branch_marketing", {
      companyId: co, organizationId: org,
    });
    assert.equal(ids.includes("mkt-other"), false);
    assert.equal(ids.includes("d1"), false);
  });
});

describe("newlyAssignedTaskUserIds", () => {
  const users = [u("d1"), u("d2"), u("mkt", {role: "marketing"})];

  test("switching from one person to all notifies the rest of the company group once", () => {
    const ids = newlyAssignedTaskUserIds(users, "d1", "all", {companyId: co, createdBy: "sup"});
    assert.deepEqual(ids.sort(), ["d2"].sort());
  });

  test("leaving assignedTo unchanged notifies nobody", () => {
    assert.deepEqual(
      newlyAssignedTaskUserIds(users, "all", "all", {companyId: co}),
      [],
    );
  });

  test("the old character-iteration bug would have treated all as a,l,l — we do not", () => {
    const ids = taskNotifyUserIds(users, "all", {companyId: co});
    assert.equal(ids.includes("a"), false);
    assert.equal(ids.includes("l"), false);
    assert.ok(ids.includes("d1"));
  });
});

describe("userInCompany", () => {
  test("matches companyUID, companyId, or companyIds", () => {
    assert.equal(userInCompany({id: "a", companyUID: "c1"}, "c1"), true);
    assert.equal(userInCompany({id: "a", companyId: "c1"}, "c1"), true);
    assert.equal(userInCompany({id: "a", companyUID: "x", companyIds: ["c1"]}, "c1"), true);
    assert.equal(userInCompany({id: "a", companyUID: "x"}, "c1"), false);
    assert.equal(userInCompany({id: "a", companyUID: "c1"}, ""), false);
  });
});

describe("isExcludedFromTaskNotify / HOLDS", () => {
  test("skips suspended, inactive, disabled, pending, rejected, deleted", () => {
    for (const status of ["suspended", "inactive", "disabled", "pending", "rejected", "deleted"]) {
      assert.equal(isExcludedFromTaskNotify({id: "x", status}), true, status);
    }
    assert.equal(isExcludedFromTaskNotify({id: "x", status: "active"}), false);
    assert.equal(isExcludedFromTaskNotify({id: "x", status: "approved"}), false);
  });

  test("skips a delegate with a hold even if status is still active", () => {
    assert.equal(isExcludedFromTaskNotify({
      id: "x",
      status: "active",
      holds: {admin_suspend: {at: "2026-11-11T00:00:00Z", by: "sup"}},
    }), true);
    assert.equal(isExcludedFromTaskNotify({id: "x", status: "active", holds: {}}), false);
  });

  test("all does not notify suspended or held delegates", () => {
    const users = [
      u("ok"),
      u("sus", {status: "suspended"}),
      u("held", {status: "active", holds: {subscription_expired: {at: "t", by: "sys"}}}),
    ];
    assert.deepEqual(taskNotifyUserIds(users, "all", {companyId: co}), ["ok"]);
  });
});

describe("taskUsersFromDelegateDocs", () => {
  test("uses data.uid when present, else doc id; skips empty; dedupes", () => {
    const users = taskUsersFromDelegateDocs([
      {id: "doc-1", data: {uid: "auth-1", role: "delegate", status: "approved", companyUID: co}},
      {id: "auth-2", data: {role: "marketing", status: "active", companyUID: co}},
      {id: "", data: {uid: "", role: "delegate"}},
      {id: "doc-dup", data: {uid: "auth-1", role: "delegate", status: "approved"}},
    ]);
    assert.deepEqual(users.map((x) => x.id), ["auth-1", "auth-2"]);
  });

  test("all recipients come from company delegate docs, not a users collection", () => {
    const docs = [
      {id: "dlg_dev_test_1", data: {uid: "dlg_dev_test_1", role: "delegate", status: "approved", companyUID: co}},
      {id: "dlg_no_users_doc", data: {role: "delegate", status: "active", companyUID: co}},
      {id: "sus", data: {uid: "sus", role: "delegate", status: "suspended", companyUID: co}},
    ];
    const users = taskUsersFromDelegateDocs(docs);
    const ids = taskNotifyUserIds(users, "all", {companyId: co, createdBy: "sup"});
    assert.deepEqual(ids.sort(), ["dlg_dev_test_1", "dlg_no_users_doc"].sort());
  });
});

describe("taskNotifyUserIdsFromSources: الكل vs sector tokens", () => {
  const delegates = [
    u("d1"),
    u("d2"),
    u("pending-dlg", {status: "pending"}),
    u("sus-dlg", {status: "suspended"}),
  ];
  const sectorStaff = [
    u("mkt", {role: "marketing"}),
    u("mkt-mgr", {role: "branches_marketing_manager"}),
    u("promo", {role: "marketingPromotion"}),
    u("mkt-org", {role: "marketing", companyUID: ""}),
    u("promo-org", {role: "marketingPromotion", companyUID: ""}),
    u("mkt-other", {role: "marketing", companyUID: "co_other"}),
    u("mkt-held", {role: "marketing", status: "active", holds: {admin_suspend: {at: "t", by: "sup"}}}),
  ];

  test("الكل / all uses only company delegates and excludes sector staff", () => {
    const opts = {companyId: co, organizationId: org, createdBy: "sup"};
    const fromAll = taskNotifyUserIdsFromSources(delegates, sectorStaff, "all", opts);
    const fromAr = taskNotifyUserIdsFromSources(delegates, sectorStaff, "الكل", opts);
    assert.deepEqual(fromAll.sort(), ["d1", "d2"].sort());
    assert.deepEqual(fromAr, fromAll);
    assert.equal(fromAll.includes("mkt"), false);
    assert.equal(fromAll.includes("promo"), false);
    assert.equal(fromAll.includes("mkt-mgr"), false);
  });

  test("all_branch_marketing reaches company and org-level sector staff, not field delegates", () => {
    const ids = taskNotifyUserIdsFromSources(
      delegates, sectorStaff, "all_branch_marketing",
      {companyId: co, organizationId: org},
    );
    assert.deepEqual(ids.sort(), ["mkt", "mkt-mgr", "mkt-org"].sort());
    assert.equal(ids.includes("d1"), false);
    assert.equal(ids.includes("promo"), false);
    assert.equal(ids.includes("mkt-other"), false);
    assert.equal(ids.includes("mkt-held"), false);
  });

  test("all_marketing_promotion reaches company and org-level promo staff, not field delegates", () => {
    const ids = taskNotifyUserIdsFromSources(
      delegates, sectorStaff, "all_marketing_promotion",
      {companyId: co, organizationId: org},
    );
    assert.deepEqual(ids.sort(), ["promo", "promo-org"].sort());
    assert.equal(ids.includes("d1"), false);
    assert.equal(ids.includes("mkt"), false);
  });

  test("assignmentNeeds* picks the right source for each token", () => {
    assert.equal(assignmentNeedsCompanyDelegates("all"), true);
    assert.equal(assignmentNeedsCompanyDelegates("الكل"), true);
    assert.equal(assignmentNeedsSectorStaff("all"), false);
    assert.equal(assignmentNeedsSectorStaff("الكل"), false);
    assert.equal(assignmentNeedsCompanyDelegates("all_branch_marketing"), false);
    assert.equal(assignmentNeedsSectorStaff("all_branch_marketing"), true);
    assert.equal(assignmentNeedsSectorStaff("all_marketing_promotion"), true);
    assert.equal(assignmentNeedsCompanyDelegates("some-uid"), true);
    assert.equal(assignmentNeedsSectorStaff("some-uid"), false);
  });

  test("switching from الكل to a sector token notifies sector staff, not the delegate group again", () => {
    const opts = {companyId: co, organizationId: org, createdBy: "sup"};
    const ids = newlyAssignedTaskUserIdsFromSources(
      delegates, sectorStaff, "all", "all_branch_marketing", opts);
    assert.deepEqual(ids.sort(), ["mkt", "mkt-mgr", "mkt-org"].sort());
  });
});
