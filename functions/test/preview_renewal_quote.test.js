"use strict";

/**
 * previewRenewalQuote must honor the selected period. An empty periodCode
 * falls back to the current cycle only — that is not a substitute for
 * sending the selected advance cycle.
 */
const {describe, it, beforeEach} = require("node:test");
const assert = require("node:assert/strict");
const path = require("path");
const {MemoryFirestore} = require("./helpers/memory_firestore");

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "test-project";
process.env.HOLDS_AUTHORITY_MODE = process.env.HOLDS_AUTHORITY_MODE || "shadow";

const jobs = require(path.join(__dirname, "../lib/subscription_jobs.js"));

const FEB = new Date("2027-02-10T10:00:00.000Z"); // current 2027_H1, 5 months, 416.67
const DEC = new Date("2026-12-15T10:00:00.000Z"); // current 2026_H2; advance window for 2027_H1

async function seedDelegates(db, uids = ["d1"]) {
  await db.doc("users/sup1").set({
    role: "super-admin",
    organizationUID: "org1",
    companyUID: "co1",
  });
  for (const uid of uids) {
    await db.collection("delegate_requests").doc(uid).set({
      requestType: "new_delegate",
      status: "approved",
      supervisorUid: "sup1",
      companyUID: "co1",
      organizationUID: "org1",
    });
    await db.doc(`organizations/org1/companies/co1/delegates/${uid}`).set({
      uid,
      fullName: uid,
      status: "active",
    });
  }
}

describe("previewRenewalQuote period selection (F8)", () => {
  let db;
  beforeEach(async () => {
    db = new MemoryFirestore();
    await seedDelegates(db);
  });

  it("quotes the current period when that period is sent", async () => {
    const quote = await jobs.previewRenewalQuote(db, {
      companyUID: "co1",
      organizationUID: "org1",
      uids: ["d1"],
      periodCode: "2027_H1",
      at: FEB,
    });
    assert.equal(quote.periodCode, "2027_H1");
    assert.equal(quote.amountCents, 41667);
    assert.equal(quote.remainingMonths, 5);
  });

  it("empty periodCode falls back to the current cycle, not the next", async () => {
    const quote = await jobs.previewRenewalQuote(db, {
      companyUID: "co1",
      organizationUID: "org1",
      uids: ["d1"],
      periodCode: "",
      at: FEB,
    });
    assert.equal(quote.periodCode, "2027_H1");
    assert.equal(quote.amountCents, 41667);
  });

  it("quotes the next cycle when advance is open and that period is sent", async () => {
    await db.doc("config/subscriptions").set({
      advanceRenewalEnabled: true,
      advanceRenewalDays: 30,
    });
    const quote = await jobs.previewRenewalQuote(db, {
      companyUID: "co1",
      organizationUID: "org1",
      uids: ["d1"],
      periodCode: "2027_H1",
      at: DEC,
    });
    assert.equal(quote.periodCode, "2027_H1");
    assert.equal(quote.amountCents, 50000);
    assert.equal(quote.remainingMonths, 6);
  });

  it("empty periodCode during an open advance window still quotes the current cycle", async () => {
    await db.doc("config/subscriptions").set({
      advanceRenewalEnabled: true,
      advanceRenewalDays: 30,
    });
    // Dec 2026 current cycle is still in the 2026 free promotion (no
    // tashil-dev bypass here), so the current-period fallback is free,
    // not a 2027_H1 advance quote of 500.
    await assert.rejects(
      () => jobs.previewRenewalQuote(db, {
        companyUID: "co1",
        organizationUID: "org1",
        uids: ["d1"],
        periodCode: "",
        at: DEC,
      }),
      (e) => e.reason === "free_period",
    );
  });

  it("rejects a genuine period mismatch (previous cycle, or next while advance is closed)", async () => {
    await assert.rejects(
      () => jobs.previewRenewalQuote(db, {
        companyUID: "co1",
        organizationUID: "org1",
        uids: ["d1"],
        periodCode: "2026_H2",
        at: FEB,
      }),
      (e) => e.reason === "period_mismatch",
    );
    await assert.rejects(
      () => jobs.previewRenewalQuote(db, {
        companyUID: "co1",
        organizationUID: "org1",
        uids: ["d1"],
        periodCode: "2027_H2",
        at: FEB,
      }),
      (e) => e.reason === "period_mismatch",
    );
  });
});
