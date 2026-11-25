/**
 * TAS-48: delegate_tracking server verdict fields (verified*, statusMismatch,
 * scopeMismatch) are written by the onDelegateTrackingWritten trigger only.
 * The delegate and staff cannot create or change them; the writes the app
 * already does (old builds included) keep working. Fake data only.
 *
 * npm run test:rules:tas48
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {
  initializeTestEnvironment, assertSucceeds, assertDeniedByRule, assertBudgetHeadroom,
} = require("./_rules_testing");
const {doc, setDoc, updateDoc, deleteField, serverTimestamp} = require("firebase/firestore");

const RULES = readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8");
const ORG = "seed-fake-tas48-org";
const CO = "seed-fake-tas48-co";
const DEL = "seed-fake-tas48-del";
const DELEGATE = {
  role: "delegate", delegateId: DEL, delegateIds: [DEL], orgId: ORG, companyId: CO,
  firebase: {sign_in_provider: "custom"},
};
const STAFF = {
  "sa": {role: "super-admin"},
  "hr": {role: "hr", organizationUID: ORG, companyUID: CO},
  "cadmin": {role: "company-admin", organizationUID: ORG, companyUID: CO},
};
const SERVER_FIELDS = {
  verifiedStatus: "inside", verifiedDistanceMeters: 1, verifiedBranchLat: 30,
  verifiedBranchLng: 31, verifiedBranchRadius: 100, verifiedReason: "ok",
  verifiedAt: new Date("2026-11-25T08:00:00Z"), statusMismatch: false, scopeMismatch: false,
};
// What the app writes on check-in (attendance_remote_data_source.dart).
const CHECK_IN = {
  delegateId: DEL, delegateName: "fake", companyId: CO, companyUID: CO,
  organizationId: ORG, organizationUID: ORG, branchId: "b1", branchName: "fake",
  branchLat: 30.0444, branchLng: 31.2357, geofenceRadius: 100,
  currentStatus: "inside", currentDistanceMeters: 3, lastLatitude: 30.0444, lastLongitude: 31.2357,
  isOnline: true,
};
const PATH = `delegate_tracking/${DEL}`;

let env;
const fs = (uid) => uid === DEL ?
  env.authenticatedContext(DEL, DELEGATE).firestore() :
  env.authenticatedContext(uid, {firebase: {sign_in_provider: "password"}}).firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas48",
    firestore: {rules: RULES},
  });
});
after(async () => env && env.cleanup());

async function seed(withVerdict) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, u] of Object.entries(STAFF)) await setDoc(doc(db, `users/${uid}`), {...u, fake: true});
    await setDoc(doc(db, `organizations/${ORG}/companies/${CO}/delegates/${DEL}`), {
      uid: DEL, organizationUID: ORG, companyUID: CO, status: "active", fullName: "fake",
    });
    if (withVerdict) {
      await setDoc(doc(db, PATH), {...CHECK_IN, ...SERVER_FIELDS, statusMismatch: true, verifiedStatus: "outside"});
    }
  });
}

describe("create (no doc yet)", () => {
  beforeEach(() => seed(false));

  test("delegate check-in without server fields is allowed", async () => {
    await assertSucceeds(setDoc(doc(fs(DEL), PATH), {...CHECK_IN, lastUpdated: serverTimestamp()}, {merge: true}));
  });

  for (const [k, v] of Object.entries(SERVER_FIELDS)) {
    test(`delegate cannot create with ${k}`, async () => {
      await assertDeniedByRule(setDoc(doc(fs(DEL), PATH), {...CHECK_IN, [k]: v}, {merge: true}));
    });
  }

  test("HR cannot create with a server verdict", async () => {
    await assertDeniedByRule(setDoc(doc(fs("hr"), PATH), {...CHECK_IN, verifiedStatus: "inside"}, {merge: true}));
  });
});

describe("update (doc already carries the server verdict)", () => {
  beforeEach(() => seed(true));

  test("delegate position update (old and new builds) is allowed", async () => {
    await assertSucceeds(updateDoc(doc(fs(DEL), PATH), {
      currentStatus: "inside", currentDistanceMeters: 2, lastLatitude: 30.05, lastLongitude: 31.24,
      batteryLevel: 50, lastUpdated: serverTimestamp(),
    }));
  });

  test("delegate check-in merge over an existing verdict is allowed", async () => {
    await assertSucceeds(setDoc(doc(fs(DEL), PATH), {...CHECK_IN, lastUpdated: serverTimestamp()}, {merge: true}));
  });

  test("delegate check-out is allowed", async () => {
    await assertSucceeds(updateDoc(doc(fs(DEL), PATH), {
      currentStatus: "checked_out", isTrackingEnabled: false, checkOutTime: serverTimestamp(),
    }));
  });

  test("supervisor tracking toggle (HR, merge) is allowed", async () => {
    await assertSucceeds(setDoc(doc(fs("hr"), PATH), {
      isTrackingEnabled: false, trackingUpdatedBy: "hr", trackingUpdatedAt: serverTimestamp(),
    }, {merge: true}));
  });

  test("delegate cannot clear the mismatch flag or rewrite the verdict", async () => {
    await assertDeniedByRule(updateDoc(doc(fs(DEL), PATH), {statusMismatch: false}));
    await assertDeniedByRule(updateDoc(doc(fs(DEL), PATH), {verifiedStatus: "inside"}));
    await assertDeniedByRule(updateDoc(doc(fs(DEL), PATH), {verifiedDistanceMeters: 0, lastLatitude: 1}));
    await assertDeniedByRule(updateDoc(doc(fs(DEL), PATH), {scopeMismatch: deleteField()}));
    await assertDeniedByRule(updateDoc(doc(fs(DEL), PATH), {verifiedAt: serverTimestamp()}));
  });

  test("staff cannot change the verdict either", async () => {
    for (const uid of ["hr", "cadmin", "sa"]) {
      await assertDeniedByRule(updateDoc(doc(fs(uid), PATH), {statusMismatch: false}));
    }
  });
});

describe("budget headroom (TAS-105)", () => {
  test("delegate position update keeps 150 spare expressions", async () => {
    await assertBudgetHeadroom({
      rules: RULES,
      line: "allow create, update: if signedIn() && (trackingServerKeysUntouched() ? (",
      pad: Number(process.env.RULES_BUDGET_PAD_TRACKING || 150),
      projectId: "demo-tas48-headroom",
      seed: async (db) => {
        await db.doc(PATH).set({...CHECK_IN, ...SERVER_FIELDS});
      },
      request: (e) => e.authenticatedContext(DEL, DELEGATE).firestore().doc(PATH).update({
        currentStatus: "outside", currentDistanceMeters: 400, lastLatitude: 30.05, lastLongitude: 31.24,
      }),
    });
  });
});
