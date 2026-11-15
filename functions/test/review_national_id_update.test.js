const {describe, it, beforeEach, test} = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/delegate_profile_edit_logic");
const {MemoryFirestore, FieldValue} = require("./helpers/memory_firestore");

const NEW_ID = "29901010101011";
const OLD_ID = "28809080808088";
const DELEGATE_UID = "d1";
const DELEGATE_PATH = "organizations/o1/companies/c1/delegates/d1";

function plan(approve, userExists) {
  return L.planNationalIdReviewDocumentUpdates({
    approve,
    newId: NEW_ID,
    userExists,
  });
}

async function applyPlannedDelegateAndUser(db, sync) {
  if (sync.updateDelegateAndRequestFields) {
    await db.doc(DELEGATE_PATH).update({
      ...sync.updateDelegateAndRequestFields,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  if (sync.updateUserFields) {
    await db.doc(`users/${DELEGATE_UID}`).update({
      ...sync.updateUserFields,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
}

describe("reviewNationalIdUpdate user + delegate sync (TA-57)", () => {
  let db;

  beforeEach(async () => {
    db = new MemoryFirestore();
    await db.doc(DELEGATE_PATH).set({
      uid: DELEGATE_UID,
      companyUID: "c1",
      status: "active",
      nationalId: OLD_ID,
      nationalityID: OLD_ID,
    });
    await db.doc(`users/${DELEGATE_UID}`).set({
      uid: DELEGATE_UID,
      role: "delegate",
      nationalId: OLD_ID,
      nationalityID: OLD_ID,
    });
  });

  it("approve updates delegate and users when user doc exists", async () => {
    const sync = plan(true, true);
    assert.ok(sync.updateDelegateAndRequestFields);
    assert.ok(sync.updateUserFields);
    assert.deepEqual(sync.updateDelegateAndRequestFields, sync.updateUserFields);

    await applyPlannedDelegateAndUser(db, sync);

    const delegate = (await db.doc(DELEGATE_PATH).get()).data();
    const user = (await db.doc(`users/${DELEGATE_UID}`).get()).data();
    assert.equal(delegate.nationalId, NEW_ID);
    assert.equal(delegate.nationalityID, NEW_ID);
    assert.equal(user.nationalId, NEW_ID);
    assert.equal(user.nationalityID, NEW_ID);
  });

  it("approve updates delegate only when users doc is missing", async () => {
    await db.doc(`users/${DELEGATE_UID}`).update({uid: DELEGATE_UID});
    const sync = plan(true, false);
    assert.ok(sync.updateDelegateAndRequestFields);
    assert.equal(sync.updateUserFields, null);

    await applyPlannedDelegateAndUser(db, sync);

    const delegate = (await db.doc(DELEGATE_PATH).get()).data();
    assert.equal(delegate.nationalId, NEW_ID);
    assert.equal(delegate.nationalityID, NEW_ID);
  });

  it("reject updates neither delegate nor users", async () => {
    const sync = plan(false, true);
    assert.equal(sync.updateDelegateAndRequestFields, null);
    assert.equal(sync.updateUserFields, null);

    await applyPlannedDelegateAndUser(db, sync);

    const delegate = (await db.doc(DELEGATE_PATH).get()).data();
    const user = (await db.doc(`users/${DELEGATE_UID}`).get()).data();
    assert.equal(delegate.nationalId, OLD_ID);
    assert.equal(delegate.nationalityID, OLD_ID);
    assert.equal(user.nationalId, OLD_ID);
    assert.equal(user.nationalityID, OLD_ID);
  });
});

test("nationalIdFieldsForApprovedReview mirrors both field spellings", () => {
  assert.deepEqual(L.nationalIdFieldsForApprovedReview(NEW_ID), {
    nationalId: NEW_ID,
    nationalityID: NEW_ID,
  });
  assert.equal(L.nationalIdFieldsForApprovedReview(""), null);
});