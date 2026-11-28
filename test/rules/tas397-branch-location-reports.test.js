/**
 * TAS-397: «مكان الفرع غلط» reports. The delegate writes its own report
 * only; the company supervisor (staff account) of that company forwards or
 * rejects it; the chain admin / global staff close a forwarded one; nobody
 * edits the delegate's fields, deletes a report, or moves a branch through
 * it. A delegate with position supervisor reviews nothing (user decision
 * 28 Nov). Fake data only.
 *
 * npm run test:rules:tas397-branch-reports
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertFails} = require("./_rules_testing");
const {
  doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, collection, query, where,
  serverTimestamp,
} = require("firebase/firestore");

const ORG = "seed-fake-tas397-org";
const ORG2 = "seed-fake-tas397-org2";
const CO = "seed-fake-tas397-co";
const CO2 = "seed-fake-tas397-co2";
const BR = "seed-fake-tas397-branch";
const C = "branch_location_reports";

const staff = {
  "sup": {role: "supervisor", organizationUID: ORG, companyUID: CO},
  "coadmin": {role: "company-admin", organizationUID: ORG, companyUID: CO},
  "sup2": {role: "supervisor", organizationUID: ORG, companyUID: CO2},
  "hr": {role: "hr", organizationUID: ORG, companyUID: CO},
  "orgadmin": {role: "organization-admin", organizationUID: ORG},
  "orgadmin2": {role: "organization-admin", organizationUID: ORG2},
  "sa": {role: "super-admin"},
};

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas397",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, u] of Object.entries(staff)) {
      await setDoc(doc(db, `users/${uid}`), {...u, fake: true});
    }
    await setDoc(doc(db, `branches/${BR}`), {
      branchName: "فرع تجريبي", organizationUID: ORG, latitude: 30, longitude: 31,
      geofenceRadius: 100, fake: true,
    });
    await setDoc(doc(db, `organizations/${ORG}/branches/${BR}`), {
      branchName: "فرع تجريبي", latitude: 30, longitude: 31, geofenceRadius: 100, fake: true,
    });
  });
});

after(async () => env && env.cleanup());

// Delegate tokens as delegateLoginV2 issues them. `uidOverride` models a
// login whose Auth uid differs from the delegate id (claim only).
const delegateDb = (id, {co = CO, org = ORG, uidOverride} = {}) =>
  env.authenticatedContext(uidOverride || id, {
    role: "delegate", delegateId: id, companyId: co, orgId: org,
  }).firestore();
const staffDb = (uid) => env.authenticatedContext(uid).firestore();

const report = (delegateId, extra = {}) => ({
  delegateId,
  delegateName: "مندوب تجريبي",
  companyUID: CO,
  organizationUID: ORG,
  branchId: BR,
  branchName: "فرع تجريبي",
  branchLat: 30,
  branchLng: 31,
  branchRadius: 100,
  lat: 30.04,
  lng: 31.2,
  accuracy: 12,
  isMocked: false,
  distanceMeters: 4200,
  note: "أنا واقف جوه الفرع",
  status: "open",
  createdAt: serverTimestamp(),
  ...extra,
});

const seed = (id, data) => env.withSecurityRulesDisabled(async (ctx) => {
  await setDoc(doc(ctx.firestore(), `${C}/${id}`), {...data, createdAt: new Date()});
});

const seedReport = (delegateId, status, extra = {}) => {
  const {createdAt: _c, ...rest} = report(delegateId);
  return seed(`${delegateId}_${BR}`, {...rest, status, ...extra});
};

describe("TAS-397: the delegate's report", () => {
  test("a delegate reports for itself (uid = id)", async () => {
    await assertSucceeds(setDoc(doc(delegateDb("d1"), `${C}/d1_${BR}`), report("d1")));
  });

  test("a delegate reports for itself by the delegateId claim only", async () => {
    await assertSucceeds(setDoc(doc(delegateDb("d2", {uidOverride: "dlg_hash_d2"}), `${C}/d2_${BR}`), report("d2")));
  });

  test("not for a colleague", async () => {
    await assertFails(setDoc(doc(delegateDb("d3"), `${C}/d9_${BR}`), report("d9")));
  });

  test("the id must be {delegateId}_{branchId}", async () => {
    await assertFails(setDoc(doc(delegateDb("d4"), `${C}/random-id`), report("d4")));
  });

  test("not for another company or chain than its token", async () => {
    await assertFails(setDoc(doc(delegateDb("d5"), `${C}/d5_${BR}`), report("d5", {companyUID: CO2})));
    await assertFails(setDoc(doc(delegateDb("d6"), `${C}/d6_${BR}`), report("d6", {organizationUID: ORG2})));
  });

  test("only status open, no extra or review fields", async () => {
    await assertFails(setDoc(doc(delegateDb("d7"), `${C}/d7_${BR}`), report("d7", {status: "forwarded"})));
    await assertFails(setDoc(doc(delegateDb("d7"), `${C}/d7_${BR}`), report("d7", {reviewedBy: "d7"})));
    await assertFails(setDoc(doc(delegateDb("d7"), `${C}/d7_${BR}`), report("d7", {note: "x".repeat(501)})));
  });

  test("a staff token cannot file one", async () => {
    await assertFails(setDoc(doc(staffDb("sup"), `${C}/sup_${BR}`), report("sup")));
  });

  test("a second report for the same branch while open or forwarded is refused", async () => {
    await seedReport("d10", "open");
    await assertFails(setDoc(doc(delegateDb("d10"), `${C}/d10_${BR}`), report("d10")));
    await seedReport("d11", "forwarded");
    await assertFails(setDoc(doc(delegateDb("d11"), `${C}/d11_${BR}`), report("d11")));
  });

  test("a closed report (rejected / fixed) can be filed again", async () => {
    await seedReport("d12", "rejected", {rejectReason: "x"});
    await assertSucceeds(setDoc(doc(delegateDb("d12"), `${C}/d12_${BR}`), report("d12")));
    await seedReport("d13", "fixed");
    await assertSucceeds(setDoc(doc(delegateDb("d13"), `${C}/d13_${BR}`), report("d13")));
  });

  test("the delegate cannot change the status or the location afterwards", async () => {
    await seedReport("d14", "open");
    const ref = doc(delegateDb("d14"), `${C}/d14_${BR}`);
    await assertFails(updateDoc(ref, {status: "forwarded"}));
    await assertFails(updateDoc(ref, {lat: 1}));
  });

  test("the delegate reads its own report, never a colleague's", async () => {
    await seedReport("d15", "open");
    await assertSucceeds(getDoc(doc(delegateDb("d15"), `${C}/d15_${BR}`)));
    await assertFails(getDoc(doc(delegateDb("d16"), `${C}/d15_${BR}`)));
  });

  test("a delegate with position supervisor reads nothing of its company", async () => {
    // The token of a supervisor-delegate is a delegate token (role
    // delegate): no list of the company's reports.
    await seedReport("d17", "open");
    await assertFails(getDoc(doc(delegateDb("dsup"), `${C}/d17_${BR}`)));
    await assertFails(getDocs(query(collection(delegateDb("dsup"), C), where("companyUID", "==", CO))));
  });

  test("nobody deletes a report", async () => {
    await seedReport("d18", "open");
    await assertFails(deleteDoc(doc(delegateDb("d18"), `${C}/d18_${BR}`)));
    await assertFails(deleteDoc(doc(staffDb("sup"), `${C}/d18_${BR}`)));
    await assertFails(deleteDoc(doc(staffDb("sa"), `${C}/d18_${BR}`)));
  });
});

describe("TAS-397: the company supervisor", () => {
  test("reads its company's reports (doc and list)", async () => {
    await seedReport("d20", "open");
    await assertSucceeds(getDoc(doc(staffDb("sup"), `${C}/d20_${BR}`)));
    await assertSucceeds(getDocs(query(collection(staffDb("sup"), C), where("companyUID", "==", CO))));
    await assertSucceeds(getDoc(doc(staffDb("coadmin"), `${C}/d20_${BR}`)));
  });

  test("another company's supervisor, HR and another chain cannot read", async () => {
    await seedReport("d21", "open");
    await assertFails(getDoc(doc(staffDb("sup2"), `${C}/d21_${BR}`)));
    await assertFails(getDocs(query(collection(staffDb("sup2"), C), where("companyUID", "==", CO))));
    await assertFails(getDoc(doc(staffDb("hr"), `${C}/d21_${BR}`)));
    await assertFails(getDoc(doc(staffDb("orgadmin2"), `${C}/d21_${BR}`)));
  });

  test("the chain admin does not read an open report (not forwarded yet)", async () => {
    await seedReport("d22", "open");
    await assertFails(getDoc(doc(staffDb("orgadmin"), `${C}/d22_${BR}`)));
  });

  test("forwards an open report", async () => {
    await seedReport("d23", "open");
    await assertSucceeds(updateDoc(doc(staffDb("sup"), `${C}/d23_${BR}`), {
      status: "forwarded", reviewedBy: "sup", reviewedByName: "مشرف", reviewedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }));
  });

  test("rejects only with a reason", async () => {
    await seedReport("d24", "open");
    const ref = doc(staffDb("sup"), `${C}/d24_${BR}`);
    await assertFails(updateDoc(ref, {status: "rejected", reviewedBy: "sup", reviewedAt: serverTimestamp()}));
    await assertSucceeds(updateDoc(ref, {
      status: "rejected", rejectReason: "الإحداثيات صح، إنت بعيد عن الفرع",
      reviewedBy: "sup", reviewedAt: serverTimestamp(),
    }));
  });

  test("cannot touch the delegate's fields, sign as someone else, or close it as fixed", async () => {
    await seedReport("d25", "open");
    const ref = doc(staffDb("sup"), `${C}/d25_${BR}`);
    await assertFails(updateDoc(ref, {status: "forwarded", reviewedBy: "sup", reviewedAt: serverTimestamp(), lat: 1}));
    await assertFails(updateDoc(ref, {status: "forwarded", reviewedBy: "coadmin", reviewedAt: serverTimestamp()}));
    await assertFails(updateDoc(ref, {status: "fixed", fixedBy: "sup", fixedAt: serverTimestamp()}));
  });

  test("another company's supervisor cannot decide", async () => {
    await seedReport("d26", "open");
    await assertFails(updateDoc(doc(staffDb("sup2"), `${C}/d26_${BR}`), {
      status: "forwarded", reviewedBy: "sup2", reviewedAt: serverTimestamp(),
    }));
  });
});

describe("TAS-397: chain admin and global staff", () => {
  test("the chain admin reads forwarded reports of its chain (doc and list)", async () => {
    await seedReport("d30", "forwarded");
    await assertSucceeds(getDoc(doc(staffDb("orgadmin"), `${C}/d30_${BR}`)));
    await assertSucceeds(getDocs(query(collection(staffDb("orgadmin"), C),
      where("organizationUID", "==", ORG), where("status", "==", "forwarded"))));
  });

  test("the chain admin closes a forwarded report as fixed; another chain cannot", async () => {
    await seedReport("d31", "forwarded");
    await assertFails(updateDoc(doc(staffDb("orgadmin2"), `${C}/d31_${BR}`), {
      status: "fixed", fixedBy: "orgadmin2", fixedAt: serverTimestamp(),
    }));
    await assertSucceeds(updateDoc(doc(staffDb("orgadmin"), `${C}/d31_${BR}`), {
      status: "fixed", fixedBy: "orgadmin", fixedByName: "أدمن", fixedAt: serverTimestamp(),
      fixNote: "اتعدّلت الإحداثيات",
    }));
  });

  test("the chain admin cannot skip the supervisor (open -> fixed)", async () => {
    await seedReport("d32", "open");
    await assertFails(updateDoc(doc(staffDb("orgadmin"), `${C}/d32_${BR}`), {
      status: "fixed", fixedBy: "orgadmin", fixedAt: serverTimestamp(),
    }));
  });

  test("global staff read every report and close a forwarded one (also rejected with a reason)", async () => {
    await seedReport("d33", "open");
    await assertSucceeds(getDoc(doc(staffDb("sa"), `${C}/d33_${BR}`)));
    await seedReport("d34", "forwarded");
    const ref = doc(staffDb("sa"), `${C}/d34_${BR}`);
    await assertFails(updateDoc(ref, {status: "rejected", fixedBy: "sa", fixedAt: serverTimestamp()}));
    await assertSucceeds(updateDoc(ref, {
      status: "rejected", rejectReason: "الفرع مكانه صح", fixedBy: "sa", fixedAt: serverTimestamp(),
    }));
  });
});

describe("TAS-397: a report never moves a branch", () => {
  test("delegates and company supervisors still cannot write branches", async () => {
    await assertFails(updateDoc(doc(delegateDb("d40"), `branches/${BR}`), {latitude: 30.04, longitude: 31.2}));
    await assertFails(updateDoc(doc(delegateDb("d40"), `organizations/${ORG}/branches/${BR}`), {latitude: 30.04}));
    await assertFails(updateDoc(doc(staffDb("sup"), `branches/${BR}`), {latitude: 30.04, longitude: 31.2}));
    await assertFails(updateDoc(doc(staffDb("sup"), `organizations/${ORG}/branches/${BR}`), {latitude: 30.04}));
  });
});
