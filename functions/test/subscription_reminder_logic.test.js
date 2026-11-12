const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/subscription_logic");
const R = require("../lib/subscription_reminder_logic");

test("subscriptionReminderAlertDoc uses Tashil Arabic style", () => {
  const h1 = L.periodFor(2027, 1);
  const h2 = L.periodFor(2027, 2);
  const doc = R.subscriptionReminderAlertDoc({
    supervisorUid: "sup1",
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
