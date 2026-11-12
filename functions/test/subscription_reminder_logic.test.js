const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/subscription_logic");
const R = require("../lib/subscription_reminder_logic");

test("userIdForSubscriptionInvoice prefers company supervisor user, not request creator", () => {
  const id = R.userIdForSubscriptionInvoice({
    companyUID: "c1",
    organizationUID: "o1",
    candidates: [
      {uid: "hr1", role: "hr", companyUID: "c1", organizationUID: "o1"},
      {uid: "sup1", role: "supervisor", companyUID: "c1", organizationUID: "o1"},
    ],
  });
  assert.equal(id, "sup1");
});

test("userIdForSubscriptionInvoice falls back to supervisor_{company}", () => {
  assert.equal(
    R.userIdForSubscriptionInvoice({companyUID: "c1", organizationUID: "o1", candidates: []}),
    "supervisor_c1",
  );
  assert.equal(R.supervisorCompanyInboxKey("c1"), "supervisor_c1");
});

test("userIdForSubscriptionInvoice ignores supervisor from another company", () => {
  const id = R.userIdForSubscriptionInvoice({
    companyUID: "c1",
    candidates: [{uid: "sup2", role: "supervisor", companyUID: "c2"}],
  });
  assert.equal(id, "supervisor_c1");
});

test("replacement supervisor when original left company (wrong companyUID on role)", () => {
  const id = R.userIdForSubscriptionInvoice({
    companyUID: "c1",
    organizationUID: "o1",
    candidates: [
      {uid: "old_sup", role: "supervisor", companyUID: "c_other", organizationUID: "o1"},
      {uid: "new_sup", role: "supervisor", companyUID: "c1", organizationUID: "o1"},
    ],
  });
  assert.equal(id, "new_sup");
});

test("replacement supervisor when original no longer has supervisor role", () => {
  const id = R.userIdForSubscriptionInvoice({
    companyUID: "c1",
    candidates: [
      {uid: "old_sup", role: "hr", companyUID: "c1"},
      {uid: "new_sup", role: "company_supervisor", companyUID: "c1"},
    ],
  });
  assert.equal(id, "new_sup");
});

test("original supervisor deleted/inactive excluded — replacement or inbox fallback", () => {
  assert.equal(
    R.userIdForSubscriptionInvoice({
      companyUID: "c1",
      candidates: [{uid: "gone", role: "supervisor", companyUID: "c1", status: "deleted"}],
    }),
    "supervisor_c1",
  );
  const withReplacement = R.userIdForSubscriptionInvoice({
    companyUID: "c1",
    candidates: [
      {uid: "gone", role: "supervisor", companyUID: "c1", status: "deleted"},
      {uid: "live", role: "supervisor", companyUID: "c1", status: "active"},
    ],
  });
  assert.equal(withReplacement, "live");
  assert.equal(
    R.userIdForSubscriptionInvoice({
      companyUID: "c1",
      candidates: [{uid: "off", role: "supervisor", companyUID: "c1", isActive: false}],
    }),
    "supervisor_c1",
  );
});

test("deterministic pick: lowest uid when multiple live supervisors", () => {
  const id = R.userIdForSubscriptionInvoice({
    companyUID: "c1",
    candidates: [
      {uid: "sup_z", role: "supervisor", companyUID: "c1"},
      {uid: "sup_a", role: "supervisor", companyUID: "c1"},
      {uid: "sup_m", role: "company_supervisor", companyUID: "c1"},
    ],
  });
  assert.equal(id, "sup_a");
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
