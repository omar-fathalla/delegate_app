/**
 * TAS-369: a delegate writes captured photos for itself only, and a late
 * upload is accepted until 48 h after the permission's last day. Fake data.
 *
 * npm run test:rules:tas369-photos
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertFails} = require("./_rules_testing");
const {doc, setDoc, Timestamp, serverTimestamp} = require("firebase/firestore");

const ORG = "seed-fake-tas369-org";
const CO = "seed-fake-tas369-co";
const H = 3600 * 1000;
const perm = (id) => `organizations/${ORG}/companies/${CO}/photo_permissions/${id}`;
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas369",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const now = Date.now();
    // endDate is the permission's last day (inclusive).
    await setDoc(doc(db, perm("active")), {status: "approved", startDate: Timestamp.fromMillis(now - 48 * H),
      endDate: Timestamp.fromMillis(now + 24 * H)});
    await setDoc(doc(db, perm("ended-1d")), {status: "approved", startDate: Timestamp.fromMillis(now - 96 * H),
      endDate: Timestamp.fromMillis(now - 30 * H)});
    await setDoc(doc(db, perm("ended-5d")), {status: "approved", startDate: Timestamp.fromMillis(now - 200 * H),
      endDate: Timestamp.fromMillis(now - 120 * H)});
    await setDoc(doc(db, perm("no-dates")), {status: "approved"});
  });
});

after(async () => env && env.cleanup());

const asDel = (uid) => env.authenticatedContext(uid, {role: "delegate", orgId: ORG, companyId: CO, delegateId: uid})
  .firestore();
const photo = (p, id, extra = {}) => doc(asDel("del-1"), `${perm(p)}/captured_photos/${id}`);
const data = (extra = {}) => ({delegateUID: "del-1", companyUID: CO, organizationUID: ORG,
  capturedAt: serverTimestamp(), ...extra});

describe("captured_photos create (TAS-369)", () => {
  test("own photo on an active permission", async () => {
    await assertSucceeds(setDoc(photo("active", "p1"), data({deviceCapturedAt: Timestamp.now()})));
  });
  test("a photo under a colleague's name is refused", async () => {
    await assertFails(setDoc(photo("active", "p2"), data({delegateUID: "del-2"})));
  });
  test("late upload within 48 h after the last day, taken during the permission", async () => {
    const shot = Timestamp.fromMillis(Date.now() - 32 * H);
    await assertSucceeds(setDoc(photo("ended-1d", "p3"), data({deviceCapturedAt: shot})));
  });
  test("late upload with a capture time after the permission is refused", async () => {
    await assertFails(setDoc(photo("ended-1d", "p4"), data({deviceCapturedAt: Timestamp.now()})));
  });
  test("upload more than 48 h after the last day is refused", async () => {
    await assertFails(setDoc(photo("ended-5d", "p5"), data({deviceCapturedAt: Timestamp.fromMillis(Date.now() - 130 * H)})));
  });
  test("old permission without dates and an old client without deviceCapturedAt still pass", async () => {
    await assertSucceeds(setDoc(photo("no-dates", "p6"), data()));
    await assertSucceeds(setDoc(photo("active", "p7"), data()));
  });
});
