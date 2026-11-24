/**
 * TAS-49: a user can no longer put someone else's phone or email on their own
 * users doc (rules match people to their records and notifications by them).
 * Staff change them through the updateOwnStaffContact callable.
 * Every deny must come from a rule, not the 1000-expression budget.
 * Fake data only.
 *
 * npm run test:rules:tas49
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertDeniedByRule} = require("./_rules_testing");
const {doc, setDoc, updateDoc, serverTimestamp} = require("firebase/firestore");

const ORG = "seed-fake-tas49-org";
const CO = "seed-fake-tas49-co";

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas49",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/hr-a"), {
      role: "hr", organizationUID: ORG, companyUID: CO, phoneNumber: "01000000001", email: "hr-a@fake.test", fake: true,
    });
    await setDoc(doc(db, "users/orgadmin"), {role: "organization-admin", organizationUID: ORG, fake: true});
    await setDoc(doc(db, "users/sa"), {role: "super-admin", phoneNumber: "01000000009", fake: true});
  });
});

after(async () => env && env.cleanup());

const as = (uid) => env.authenticatedContext(uid).firestore();

describe("own users doc", () => {
  test("staff cannot change its own phone, phone alias or email", async () => {
    await assertDeniedByRule(updateDoc(doc(as("hr-a"), "users/hr-a"), {phoneNumber: "01099999999"}));
    await assertDeniedByRule(updateDoc(doc(as("hr-a"), "users/hr-a"), {phone: "01099999999"}));
    await assertDeniedByRule(updateDoc(doc(as("hr-a"), "users/hr-a"), {email: "victim@fake.test"}));
  });
  test("staff still edits its own name (profile screen)", async () => {
    await assertSucceeds(setDoc(doc(as("hr-a"), "users/hr-a"), {
      displayName: "Fake HR", fullName: "Fake HR", name: "Fake HR", updatedAt: serverTimestamp(),
    }, {merge: true}));
  });
  test("a self-created users doc cannot carry a phone or email", async () => {
    await assertDeniedByRule(setDoc(doc(as("newbie"), "users/newbie"), {uid: "newbie", role: "delegate", phoneNumber: "01000000001"}));
    await assertDeniedByRule(setDoc(doc(as("newbie2"), "users/newbie2"), {uid: "newbie2", role: "", email: "hr-a@fake.test"}));
  });
  test("super admin keeps editing its own doc", async () => {
    await assertSucceeds(updateDoc(doc(as("sa"), "users/sa"), {phoneNumber: "01000000008"}));
  });
});
