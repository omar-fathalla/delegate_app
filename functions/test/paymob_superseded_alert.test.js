"use strict";

const {describe, it, beforeEach} = require("node:test");
const assert = require("node:assert/strict");
const path = require("path");
const {MemoryFirestore} = require("./helpers/memory_firestore");

const alerts = require(path.join(__dirname, "../lib/paymob_superseded_alert.js"));

describe("paymob superseded admin alert", () => {
  let db;
  beforeEach(() => {
    db = new MemoryFirestore();
  });

  it("writes admin_alerts, notifications, and FCM for privileged staff", async () => {
    await db.doc("users/sa1").set({role: "super-admin"});
    await db.doc("users/ts1").set({role: "technical_support"});
    await db.doc("fcm_tokens/sa1").set({token: "tok1"});
    await db.doc("fcm_tokens/ts1").set({token: "tok2"});
    const fcmSends = [];
    const result = await alerts.notifyPaymobSupersededPaymentRefund(db, {
      requestId: "ren1",
      attemptId: "1700000000001_oldabcd12",
      txId: "82001",
      amountCents: 41667,
      currency: "EGP",
      companyUID: "co1",
      organizationUID: "org1",
      messaging: {
        send: async (msg) => {
          fcmSends.push(msg);
          return "id";
        },
      },
    });
    assert.equal(result.adminAlert, true);
    assert.equal(result.notifications, 2);
    assert.equal(result.fcmSent, 2);
    const notifs = await db.collection("notifications").get();
    assert.equal(notifs.size, 2);
    assert.equal(notifs.docs[0].get("type"), alerts.PAYMOB_SUPERSEDED_NOTIFICATION_TYPE);
    assert.equal(notifs.docs[0].get("needs_refund"), true);
    assert.equal((await db.collection("admin_alerts").doc("82001").get()).get("requestId"), "ren1");
    assert.match(String(fcmSends[0].notification.title), /استرجاع/);
  });
});