"use strict";

const {describe, it, beforeEach} = require("node:test");
const assert = require("node:assert/strict");
const path = require("path");
const {MemoryFirestore} = require("./helpers/memory_firestore");

describe("listGlobalNotifyStaff", () => {
  let db;
  let rows;

  beforeEach(async () => {
    db = new MemoryFirestore();
    await db.doc("users/sa1").set({
      role: "super-admin",
      phoneNumber: "01011111111",
      password: "must-not-leak",
    });
    await db.doc("users/ts1").set({role: "technical_support", phone: "01022222222"});
    const mod = require(path.join(__dirname, "../lib/list_global_notify_staff.js"));
    rows = mod.listGlobalNotifyStaffRows;
  });

  it("returns minimal rows only", async () => {
    const list = await rows(db);
    assert.equal(list.length, 2);
    for (const row of list) {
      assert.ok(row.uid);
      assert.ok(row.role);
      assert.equal("password" in row, false);
      assert.equal("email" in row, false);
    }
    assert.deepEqual(list.map((u) => u.uid).sort(), ["sa1", "ts1"]);
  });
});