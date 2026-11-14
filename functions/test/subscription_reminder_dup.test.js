/**
 * Regression: one reminder per supervisor per company when organizationUID is mixed.
 * (Mohamed UT repro: dup.test.js — mixed org vs missing org on same company.)
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const R = require("../lib/subscription_reminder_logic");
const J = require("../lib/subscription_jobs");

test("groupUncoveredDelegatesByCompany merges mixed org fields into one company group", () => {
  const groups = R.groupUncoveredDelegatesByCompany([
    {companyUID: "c1", organizationUID: "o1"},
    {companyUID: "c1"},
    {companyUID: "c1", organizationUID: ""},
  ]);
  assert.equal(groups.size, 1);
  const g = groups.get("c1");
  assert.equal(g.count, 3);
  assert.equal(g.organizationUID, "o1");
  assert.equal(g.orgConflict, false);
});

test("groupUncoveredDelegatesByCompany flags org conflict under one company", () => {
  const groups = R.groupUncoveredDelegatesByCompany([
    {companyUID: "c1", organizationUID: "o1"},
    {companyUID: "c1", organizationUID: "o2"},
  ]);
  const g = groups.get("c1");
  assert.equal(g.count, 2);
  assert.equal(g.orgConflict, true);
  assert.deepEqual(g.organizationUIDs, ["o1", "o2"]);
});

test("partial lookup also targets shared supervisor_{companyUID} inbox", () => {
  const uids = R.expandReminderDeliveryUids({
    companyUID: "c_partial",
    candidates: [{uid: "sup1", role: "supervisor", companyId: "c_partial", status: "active"}],
    partialLookupRecovery: true,
  });
  assert.deepEqual(uids, ["sup1", "supervisor_c_partial"]);
});

test("every live supervisor on company is notified when orgs differ on requests", () => {
  const ids = R.recipientUidsForSubscriptionReminder({
    companyUID: "c1",
    organizationUID: "o1",
    candidates: [
      {uid: "sup_o1", role: "supervisor", companyUID: "c1", organizationUID: "o1"},
      {uid: "sup_o2", role: "supervisor", companyUID: "c1", organizationUID: "o2"},
    ],
  });
  assert.deepEqual(ids, ["sup_o1", "sup_o2"]);
});

test("recipientUidsForSubscriptionReminder yields one uid set per company call", () => {
  const ids = R.recipientUidsForSubscriptionReminder({
    companyUID: "c1",
    organizationUID: "o1",
    candidates: [
      {uid: "sup1", role: "supervisor", companyUID: "c1", organizationUID: "o1"},
    ],
  });
  assert.deepEqual(ids, ["sup1"]);
});

test("supervisor lookup failure flags company and allows inbox fallback path", async () => {
  let threw = false;
  const db = {
    collection() {
      return {
        where(_field, _op, part) {
          return {
            async get() {
              threw = true;
              throw new Error("Too many disjunctions");
            },
          };
        },
      };
    },
  };
  const {byCompany, lookupFailedCompanyUids} = await J.loadCompanySupervisorCandidates(db, ["c_dup"]);
  assert.ok(threw);
  assert.equal(byCompany.size, 0);
  assert.ok(lookupFailedCompanyUids.has("c_dup"));
  const recipients = R.recipientUidsForSubscriptionReminder({
    companyUID: "c_dup",
    candidates: byCompany.get("c_dup") || [],
  });
  assert.deepEqual(recipients, ["supervisor_c_dup"]);
});