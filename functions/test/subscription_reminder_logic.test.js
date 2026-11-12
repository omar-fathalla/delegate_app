const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/subscription_logic");
const R = require("../lib/subscription_reminder_logic");

test("recipientUidsForSubscriptionReminder notifies every live supervisor, not HR", () => {
  const ids = R.recipientUidsForSubscriptionReminder({
    companyUID: "c1",
    organizationUID: "o1",
    candidates: [
      {uid: "hr1", role: "hr", companyUID: "c1", organizationUID: "o1"},
      {uid: "sup1", role: "supervisor", companyUID: "c1", organizationUID: "o1"},
      {uid: "sup2", role: "company_supervisor", companyUID: "c1", organizationUID: "o1"},
    ],
  });
  assert.deepEqual(ids, ["sup1", "sup2"]);
});

test("recipientUidsForSubscriptionReminder falls back to supervisor_{company}", () => {
  assert.deepEqual(
    R.recipientUidsForSubscriptionReminder({companyUID: "c1", organizationUID: "o1", candidates: []}),
    ["supervisor_c1"],
  );
  assert.equal(R.supervisorCompanyInboxKey("c1"), "supervisor_c1");
});

test("recipientUidsForSubscriptionReminder ignores supervisor from another company", () => {
  const ids = R.recipientUidsForSubscriptionReminder({
    companyUID: "c1",
    candidates: [{uid: "sup2", role: "supervisor", companyUID: "c2"}],
  });
  assert.deepEqual(ids, ["supervisor_c1"]);
});

test("departed supervisor wrong company excluded; replacement included", () => {
  const ids = R.recipientUidsForSubscriptionReminder({
    companyUID: "c1",
    organizationUID: "o1",
    candidates: [
      {uid: "old_sup", role: "supervisor", companyUID: "c_other", organizationUID: "o1"},
      {uid: "new_sup", role: "supervisor", companyUID: "c1", organizationUID: "o1"},
    ],
  });
  assert.deepEqual(ids, ["new_sup"]);
});

test("HR or former supervisor role on request creator uid is not a recipient", () => {
  const ids = R.recipientUidsForSubscriptionReminder({
    companyUID: "c1",
    candidates: [
      {uid: "old_sup", role: "hr", companyUID: "c1"},
      {uid: "new_sup", role: "company_supervisor", companyUID: "c1"},
    ],
  });
  assert.deepEqual(ids, ["new_sup"]);
});

test("deleted/inactive supervisors excluded from fan-out", () => {
  assert.deepEqual(
    R.recipientUidsForSubscriptionReminder({
      companyUID: "c1",
      candidates: [{uid: "gone", role: "supervisor", companyUID: "c1", status: "deleted"}],
    }),
    ["supervisor_c1"],
  );
  const withReplacement = R.recipientUidsForSubscriptionReminder({
    companyUID: "c1",
    candidates: [
      {uid: "gone", role: "supervisor", companyUID: "c1", status: "deleted"},
      {uid: "live", role: "supervisor", companyUID: "c1", status: "active"},
      {uid: "off", role: "supervisor", companyUID: "c1", isActive: false},
    ],
  });
  assert.deepEqual(withReplacement, ["live"]);
});

test("subscriptionReminderAlertDoc uses Tashil Arabic style", () => {
  const h1 = L.periodFor(2027, 1);
  const h2 = L.periodFor(2027, 2);
  const doc = R.subscriptionReminderAlertDoc({
    recipientUid: "sup1",
    organizationUID: "o1",
    companyUID: "c1",
    endingPeriod: h1,
    nextPeriod: h2,
    uncoveredCount: 2,
    reminderDays: 14,
  });
  assert.equal(doc.type, "subscription_renewal_reminder");
  assert.equal(doc.delegateUid, "sup1");
  assert.equal(doc.title, "تذكير بتجديد اشتراك المناديب");
  assert.match(String(doc.body), /النصف الأول 2027/);
  assert.match(String(doc.body), /30 يونيو/);
  assert.match(String(doc.body), /مناديب/);
  assert.equal(doc.periodCode, "2027_H2");
});
