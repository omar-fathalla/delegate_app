/**
 * SA / technical support document replace is server-only (privileged callable).
 * npm run test:rules:privileged-reupload
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails} = require("@firebase/rules-unit-testing");
const {doc, updateDoc} = require("firebase/firestore");

const PATH = "organizations/o1/companies/c1/delegates/d1";
const PHOTO_APPROVED = {
  documentKey: "personalPhoto",
  documentStatus: "approved",
  documentURL: "https://cdn.example/p0.jpg",
  uploadedAt: "2026-01-01",
  reviewedBy: "sa",
  reviewedAt: "2026-01-01",
};
const PHOTO_PENDING = {
  documentKey: "personalPhoto",
  documentStatus: "pending",
  documentURL: "https://cdn.example/p0.jpg",
  uploadedAt: "2026-01-01",
};
const PENDING = {
  uid: "d1",
  organizationUID: "o1",
  companyUID: "c1",
  status: "pending",
  phoneNumber: "01011111111",
  profileImageUrl: "https://cdn.example/p0.jpg",
  documents: [PHOTO_PENDING],
};
const ACTIVE = {
  uid: "d1",
  organizationUID: "o1",
  companyUID: "c1",
  status: "active",
  phoneNumber: "01011111111",
  profileImageUrl: "https://cdn.example/p0.jpg",
  personalPhotoURL: "https://cdn.example/p0.jpg",
  photoURL: "https://cdn.example/p0.jpg",
  documents: [PHOTO_APPROVED],
};

function privilegedClientReupload(staffUid) {
  const url = "https://cdn.example/p-new.jpg";
  return {
    updatedAt: "t",
    profileImageUrl: url,
    personalPhotoURL: url,
    photoURL: url,
    documents: [{
      documentKey: "personalPhoto",
      documentStatus: "approved",
      documentURL: url,
      uploadedAt: "2026-11-15",
      reviewedBy: staffUid,
      reviewedAt: "2026-11-15",
    }],
  };
}

describe("privileged staff doc reupload client deny", () => {
  let env;
  const as = (uid) => env.authenticatedContext(uid).firestore();

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: "demo-privileged-reupload-rules",
      firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
    });
  });
  after(async () => env.cleanup());

  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc("users/sa").set({role: "super-admin"});
      await db.doc("users/ts").set({role: "technical_support", organizationUID: "o1"});
      await db.doc("organizations/o1/companies/c1").set({name: "C1"});
      await db.doc(PATH).set(ACTIVE);
    });
  });

  for (const uid of ["ts", "sa"]) {
    test(`DENY ${uid} client privileged approved photo re-upload`, () =>
      assertFails(updateDoc(doc(as(uid), PATH), privilegedClientReupload(uid))));
  }

  test("DENY sa client approves pending document (server callable only)", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(PATH).set(PENDING);
    });
    await assertFails(updateDoc(doc(as("sa"), PATH), {
      updatedAt: "t",
      documents: [{
        ...PHOTO_PENDING,
        documentStatus: "approved",
        reviewedBy: "sa",
        reviewedAt: "2026-11-15",
      }],
    }));
  });

  test("DENY ts client approves pending document", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(PATH).set(PENDING);
    });
    await assertFails(updateDoc(doc(as("ts"), PATH), {
      updatedAt: "t",
      documents: [{
        ...PHOTO_PENDING,
        documentStatus: "approved",
        reviewedBy: "ts",
        reviewedAt: "2026-11-15",
      }],
    }));
  });
});