/**
 * TAS-112: the delegate phone change goes only through the callables
 * (requestDelegatePhoneChange / confirmDelegatePhoneChange). The rules keep
 * phoneNumber / nationalityID closed for the delegate itself, and the
 * pending-change docs are server-only. Fake data only.
 *
 * npm run test:rules:tas112
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertDeniedByRule} = require("./_rules_testing");
const {doc, getDoc, setDoc, updateDoc} = require("firebase/firestore");

const PATH = "organizations/o1/companies/c1/delegates/d1";
const TOKEN = {
  role: "delegate", delegateId: "d1", delegateIds: ["d1"], orgId: "o1", companyId: "c1",
  phones: ["01000000001"], firebase: {sign_in_provider: "custom"},
};

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas112",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, PATH), {
      phoneNumber: "01000000001", nationalityID: "29001010000001", position: "promoter",
      organizationUID: "o1", companyUID: "c1", status: "active", fake: true,
    });
    await setDoc(doc(db, "delegate_phone_changes/d1"), {newPhone: "01000000002", status: "pending", fake: true});
  });
});
after(async () => env && env.cleanup());

const asDelegate = () => env.authenticatedContext("d1", TOKEN).firestore();

describe("TAS-112 delegate phone change", () => {
  test("the delegate still reads its own document", () =>
    assertSucceeds(getDoc(doc(asDelegate(), PATH))));
  test("the delegate cannot write its phone directly", () =>
    assertDeniedByRule(updateDoc(doc(asDelegate(), PATH), {phoneNumber: "01000000002"})));
  test("the delegate cannot write its national ID directly", () =>
    assertDeniedByRule(updateDoc(doc(asDelegate(), PATH), {nationalityID: "29001010000009"})));
  test("pending-change docs are server-only", async () => {
    await assertDeniedByRule(getDoc(doc(asDelegate(), "delegate_phone_changes/d1")));
    await assertDeniedByRule(setDoc(doc(asDelegate(), "delegate_phone_changes/d1"),
      {newPhone: "01000000003", status: "pending"}));
  });
});
