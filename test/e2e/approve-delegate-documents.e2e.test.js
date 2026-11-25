/**
 * TAS-336: approveDelegateDocuments against the Firestore emulator (real admin).
 * npm run test:e2e:approve-docs
 * Fake data only.
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("../../functions/node_modules/firebase-admin");

let fn;
let db;
const ctx = (uid, role) => ({
  auth: {uid, token: {...(role ? {role} : {}), firebase: {sign_in_provider: "password"}}},
  app: {appId: "fake"},
  rawRequest: {headers: {}},
});
const delPath = (org, co, uid) => `organizations/${org}/companies/${co}/delegates/${uid}`;

async function code(promise) {
  try {
    return {ok: true, data: await promise};
  } catch (e) {
    return {ok: false, code: e.code, reason: e.details?.reason ?? String(e.message || "")};
  }
}

const KEYS = [
  ["personalPhoto", "p0"], ["nationalityId", "f0"], ["paymentReceipt", "r0"],
  ["electronicPaymentReceipt", "r0"], ["electronic_payment_receipt", "r0"],
  ["personalPhoto", "p0"], ["paymentReceipt", "r0"], ["electronicPaymentReceipt", "r0"],
];
const pendingDocs = (n) => KEYS.slice(0, n).map(([k, u]) => ({
  documentKey: k, documentStatus: "pending", documentURL: u,
  ...(k === "nationalityId" ? {secondaryURL: "b0"} : {}), uploadedAt: "2026-11-01",
}));

async function seed(rid, {orgs = ["o1"], docs = 5, req = {}, docOver = {}} = {}) {
  await db.doc(`delegate_requests/${rid}`).set({
    status: "pending", requestType: "new_delegate", supervisorUid: "sup", companyUID: "c1",
    organizationUID: orgs[0], organizationUIDs: orgs, profileImageUrl: "p0",
    nationalIdFrontUrl: "f0", nationalIdBackUrl: "b0", receiptImageUrl: "r0",
    orgCompanyCheck: "ok", ...req,
  });
  for (const o of orgs) {
    await db.doc(delPath(o, "c1", rid)).set({
      uid: rid, status: "pending", companyUID: "c1", organizationUID: o,
      fullName: "Fake Delegate", documents: pendingDocs(docs), ...docOver,
    });
  }
}

const call = (data, c) => fn.approveDelegateDocuments.run(data, c);

test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "run under the Firestore emulator");
  fn = require("../../functions/lib/index.js");
  db = admin.firestore();
  await db.doc("users/sup").set({role: "supervisor", organizationUID: "o1", companyUID: "c1"});
  // The users doc says tech support, but the token has no claim.
  await db.doc("users/noclaim").set({role: "technical_support"});
  await db.doc("users/ts").set({role: "technical_support", fullName: "Fake TS"});
});

for (const n of [5, 8]) {
  test(`tech support approves ${n} pending documents in one call`, async () => {
    const rid = `r-${n}`;
    await seed(rid, {orgs: ["o1", "o2"], docs: n});
    const r = await call({requestId: rid, organizationUIDs: ["o1", "o2"]}, ctx("ts", "technical_support"));
    assert.deepEqual(r, {ok: true, alreadyApproved: false, activated: 2, flipped: n * 2});
    const q = (await db.doc(`delegate_requests/${rid}`).get()).data();
    assert.equal(q.status, "approved");
    assert.equal(q.reviewedBy, "Fake TS");
    for (const o of ["o1", "o2"]) {
      const d = (await db.doc(delPath(o, "c1", rid)).get()).data();
      assert.equal(d.status, "active");
      assert.equal(d.approvedRequestId, rid);
      assert.equal(d.documents.length, n);
      assert.ok(d.documents.every((e) => e.documentStatus === "approved" && e.reviewedBy === "Fake TS"));
      assert.equal(d.fullName, "Fake Delegate");
    }
  });
}

test("super-admin (claim) may call it too", async () => {
  await seed("r-sa", {docs: 6});
  const r = await call({requestId: "r-sa", organizationUIDs: ["o1"], reviewerName: "SA"}, ctx("sa", "super-admin"));
  assert.equal(r.ok, true);
  assert.equal((await db.doc("delegate_requests/r-sa").get()).data().reviewedBy, "SA");
});

test("wrong role or no claim: denied, nothing written", async () => {
  await seed("r-role");
  for (const c of [ctx("sup2", "supervisor"), ctx("oa", "organization-admin"), ctx("noclaim", null)]) {
    const r = await code(call({requestId: "r-role", organizationUIDs: ["o1"]}, c));
    assert.equal(r.ok, false);
    assert.equal(r.code, "permission-denied");
    assert.equal(r.reason, "not_approver");
  }
  assert.equal((await db.doc("delegate_requests/r-role").get()).data().status, "pending");
  assert.equal((await db.doc(delPath("o1", "c1", "r-role")).get()).data().status, "pending");
});

test("unauthenticated / anonymous: denied", async () => {
  await seed("r-anon");
  const anon = {auth: {uid: "a", token: {role: "super-admin", firebase: {sign_in_provider: "anonymous"}}}};
  assert.equal((await code(call({requestId: "r-anon", organizationUIDs: ["o1"]}, anon))).code, "unauthenticated");
  assert.equal((await code(call({requestId: "r-anon", organizationUIDs: ["o1"]}, {}))).code, "unauthenticated");
});

test("other company / chain outside the request: denied, nothing written", async () => {
  await seed("r-co", {orgs: ["o1"]});
  // A doc under the same path id but for another company.
  await db.doc(delPath("o1", "c1", "r-co")).update({companyUID: "c2"});
  const r1 = await code(call({requestId: "r-co", organizationUIDs: ["o1"]}, ctx("ts", "technical_support")));
  assert.equal(r1.reason, "delegate_out_of_scope");
  await seed("r-org", {orgs: ["o1"]});
  await db.doc(delPath("o9", "c1", "r-org")).set({status: "pending", companyUID: "c1", organizationUID: "o9", documents: []});
  const r2 = await code(call({requestId: "r-org", organizationUIDs: ["o1", "o9"]}, ctx("ts", "technical_support")));
  assert.equal(r2.code, "permission-denied");
  assert.equal(r2.reason, "org_not_in_request");
  assert.equal((await db.doc("delegate_requests/r-org").get()).data().status, "pending");
  assert.equal((await db.doc(delPath("o1", "c1", "r-org")).get()).data().status, "pending");
});

test("tech support cannot approve its own request", async () => {
  await seed("r-own", {req: {supervisorUid: "ts"}});
  const r = await code(call({requestId: "r-own", organizationUIDs: ["o1"]}, ctx("ts", "technical_support")));
  assert.equal(r.reason, "own_request");
});

test("URL mismatch on one entry: atomic deny", async () => {
  await seed("r-url", {orgs: ["o1", "o2"]});
  const ref = db.doc(delPath("o2", "c1", "r-url"));
  const d = (await ref.get()).data();
  d.documents[2].documentURL = "foreign";
  await ref.set(d);
  const r = await code(call({requestId: "r-url", organizationUIDs: ["o1", "o2"]}, ctx("ts", "technical_support")));
  assert.equal(r.reason, "document_url_mismatch");
  assert.equal((await db.doc(delPath("o1", "c1", "r-url")).get()).data().status, "pending");
  assert.equal((await db.doc("delegate_requests/r-url").get()).data().status, "pending");
});

test("unpaid Paymob request: denied", async () => {
  await seed("r-pay", {req: {paymentMethod: "paymob", paymentStatus: "pending"}});
  const r = await code(call({requestId: "r-pay", organizationUIDs: ["o1"]}, ctx("ts", "technical_support")));
  assert.equal(r.reason, "payment_not_settled");
});

test("replay after success: ok, alreadyApproved, nothing rewritten", async () => {
  await seed("r-replay", {docs: 5});
  const c = ctx("ts", "technical_support");
  await call({requestId: "r-replay", organizationUIDs: ["o1"]}, c);
  const before = (await db.doc(delPath("o1", "c1", "r-replay")).get()).updateTime;
  const r = await call({requestId: "r-replay", organizationUIDs: ["o1"]}, c);
  assert.deepEqual(r, {ok: true, alreadyApproved: true, activated: 0, flipped: 0});
  const after = (await db.doc(delPath("o1", "c1", "r-replay")).get()).updateTime;
  assert.ok(before.isEqual(after));
});

test("request approved by someone else, doc not bound: request_not_pending", async () => {
  await seed("r-done");
  await db.doc("delegate_requests/r-done").update({status: "approved"});
  const r = await code(call({requestId: "r-done", organizationUIDs: ["o1"]}, ctx("ts", "technical_support")));
  assert.equal(r.reason, "request_not_pending");
});

test("missing delegate doc: not-found, nothing written", async () => {
  await seed("r-miss", {orgs: ["o1", "o2"]});
  await db.doc(delPath("o2", "c1", "r-miss")).delete();
  const r = await code(call({requestId: "r-miss", organizationUIDs: ["o1", "o2"]}, ctx("ts", "technical_support")));
  assert.equal(r.code, "not-found");
  assert.equal((await db.doc(delPath("o1", "c1", "r-miss")).get()).data().status, "pending");
});
