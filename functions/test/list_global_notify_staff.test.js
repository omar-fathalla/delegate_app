"use strict";

const {describe, it, beforeEach} = require("node:test");
const assert = require("node:assert/strict");
const path = require("path");
const {MemoryFirestore} = require("./helpers/memory_firestore");

describe("listGlobalNotifyStaff", () => {
  let db;
  let mod;

  beforeEach(async () => {
    db = new MemoryFirestore();
    mod = require(path.join(__dirname, "../lib/list_global_notify_staff.js"));
    await db.doc("users/sa1").set({
      role: "super-admin",
      phoneNumber: "01011111111",
      password: "must-not-leak",
    });
    await db.doc("users/ts1").set({role: "technical_support", phone: "01022222222"});
    await db.doc("users/ts2").set({role: "tech_support", phone: "01033333333"});
    await db.doc("users/sa-off").set({
      role: "superAdmin",
      status: "suspended",
      phoneNumber: "01044444444",
    });
    await db.doc("users/ts-del").set({
      role: "techsupport",
      isActive: false,
      phone: "01055555555",
    });
  });

  it("returns minimal active rows only (incl. tech_support spellings)", async () => {
    const list = await mod.listGlobalNotifyStaffRows(db);
    assert.deepEqual(list.map((u) => u.uid).sort(), ["sa1", "ts1", "ts2"]);
    for (const row of list) {
      assert.ok(row.uid);
      assert.ok(row.role);
      assert.equal("password" in row, false);
      assert.equal("email" in row, false);
    }
  });

  it("companyNotifyCallerAllowed allows supervisor with company", () => {
    assert.equal(mod.companyNotifyCallerAllowed({role: "supervisor", companyUID: "c1"}), true);
    assert.equal(mod.companyNotifyCallerAllowed({role: "hr", companyId: "c1"}), true);
  });

  it("companyNotifyCallerAllowed denies missing company or wrong role", () => {
    assert.equal(mod.companyNotifyCallerAllowed({role: "supervisor"}), false);
    assert.equal(mod.companyNotifyCallerAllowed({role: "marketing", companyUID: "c1"}), false);
    assert.equal(mod.companyNotifyCallerAllowed({role: "organization-admin", companyUID: "c1"}), false);
  });

  it("GLOBAL_NOTIFY_STAFF_CAP is set", () => {
    assert.equal(mod.GLOBAL_NOTIFY_STAFF_CAP, 50);
  });

  it("excludes isDeleted staff", async () => {
    await db.doc("users/ts-del2").set({
      role: "tech_support",
      isDeleted: true,
      phone: "01066666666",
    });
    const list = await mod.listGlobalNotifyStaffRows(db);
    assert.equal(list.some((u) => u.uid === "ts-del2"), false);
  });

  it("sorts by uid before applying cap", async () => {
    for (let i = 0; i < 55; i++) {
      const id = `cap${String(i).padStart(2, "0")}`;
      await db.doc(`users/${id}`).set({
        role: "super-admin",
        phoneNumber: `0109${String(i).padStart(6, "0")}`,
      });
    }
    const list = await mod.listGlobalNotifyStaffRows(db);
    assert.equal(list.length, 50);
    const uids = list.map((u) => u.uid);
    assert.deepEqual(uids, [...uids].sort());
  });
});