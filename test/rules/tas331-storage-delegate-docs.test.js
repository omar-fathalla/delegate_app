/**
 * TAS-331: delegate documents store Storage paths (profileImagePath,
 * documents[].documentPath, ...). Whoever reads the delegate doc in
 * Firestore should read the file by path; storage must never be wider.
 *
 * Same method as tas332-storage-read-parity.test.js: each principal reads
 * the Firestore doc and the object. KNOWN_GAP lists the readers storage.rules
 * cannot reach yet (documented in storage.rules and USER-ROLES-LOGIC.md 5.13;
 * the app falls back to the legacy URL while write_legacy_storage_urls is on).
 */
"use strict";
const {describe, test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment} = require("./_rules_testing");
const {doc, setDoc, getDoc} = require("firebase/firestore");
const {ref, uploadBytes, getBytes} = require("firebase/storage");

function splitHost(envName, fallback) {
  const raw = process.env[envName] || fallback;
  const [host, port] = raw.split(":");
  return {host, port: Number(port)};
}

const bytes = Uint8Array.from(Buffer.from("tas331 fixture\n"));

const STAFF = {
  superA: {role: "super_admin"},
  techA: {role: "technical_support"},
  hrA: {role: "hr", companyUID: "coA", organizationUID: "o1"},
  supA: {role: "admin", companyUID: "coA", organizationUID: "o1"},
  accA: {role: "accountant", companyUID: "coA", organizationUID: "o1"},
  bmA: {role: "branches_marketing", companyUID: "coA", organizationUID: "o1"},
  mkA: {role: "marketing", companyUID: "coA", organizationUID: "o1"},
  orgAdm: {role: "organization_admin", companyUID: "", organizationUID: "o1"},
  hrA2: {role: "hr", companyUID: "coA2", organizationUID: "o1"},
  accA2: {role: "accountant", companyUID: "coA2", organizationUID: "o1"},
  hrB: {role: "hr", companyUID: "coB", organizationUID: "o2"},
};

const DELEGATES = {
  owner: {uid: "dlgT", claims: {delegateId: "dlgT", companyId: "coA", orgId: "o1"}},
  supCoA: {uid: "supD", claims: {delegateId: "supD", companyId: "coA", orgId: "o1"}},
  plainCoA: {uid: "plainD", claims: {delegateId: "plainD", companyId: "coA", orgId: "o1"}},
  supCoB: {uid: "supB", claims: {delegateId: "supB", companyId: "coB", orgId: "o2"}},
};

const PRINCIPALS = [...Object.keys(STAFF), ...Object.keys(DELEGATES)];

const FIELDS = {
  "delegates.profileImagePath / documents[].documentPath": {
    doc: "organizations/o1/companies/coA/delegates/dlgT",
    obj: "delegate_documents/dlgT/personalPhoto_1.jpg",
  },
  "delegate_requests.receiptImagePath": {
    doc: "delegate_requests/dlgT",
    obj: "delegate_subscription_receipts/dlgT/receipt.jpg",
  },
};

// Firestore allows, storage cannot tell yet (see storage.rules TAS-331).
const KNOWN_GAP = new Set([
  "delegates.profileImagePath / documents[].documentPath|orgAdm",
  "delegates.profileImagePath / documents[].documentPath|mkA",
  "delegate_requests.receiptImagePath|orgAdm",
]);

describe("TAS-331 storage read parity for delegate document paths", () => {
  let env;
  const fsHost = splitHost("FIRESTORE_EMULATOR_HOST", "127.0.0.1:8080");
  const stHost = splitHost("FIREBASE_STORAGE_EMULATOR_HOST", "127.0.0.1:9199");
  const matrix = {};

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: "demo-tas331-storage",
      firestore: {host: fsHost.host, port: fsHost.port,
        rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
      storage: {host: stHost.host, port: stHost.port,
        rules: readFileSync(resolve(__dirname, "../../storage.rules"), "utf8")},
    });
    await env.clearFirestore();
    await env.clearStorage();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (const [uid, data] of Object.entries(STAFF)) await setDoc(doc(db, `users/${uid}`), data);
      await setDoc(doc(db, "organizations/o1"), {name: "o1"});
      await setDoc(doc(db, "organizations/o2"), {name: "o2"});
      await setDoc(doc(db, "organizations/o1/companies/coA"), {name: "coA"});
      await setDoc(doc(db, "organizations/o1/companies/coA2"), {name: "coA2"});
      await setDoc(doc(db, "organizations/o2/companies/coB"), {name: "coB"});
      const base = {organizationUID: "o1", companyUID: "coA", status: "active"};
      await setDoc(doc(db, "organizations/o1/companies/coA/delegates/dlgT"),
        {...base, uid: "dlgT", position: "delegate", profileImagePath: FIELDS[Object.keys(FIELDS)[0]].obj});
      await setDoc(doc(db, "organizations/o1/companies/coA/delegates/supD"), {...base, uid: "supD", position: "supervisor"});
      await setDoc(doc(db, "organizations/o1/companies/coA/delegates/plainD"), {...base, uid: "plainD", position: "delegate"});
      await setDoc(doc(db, "organizations/o2/companies/coB/delegates/supB"),
        {organizationUID: "o2", companyUID: "coB", status: "active", uid: "supB", position: "supervisor"});
      await setDoc(doc(db, "delegate_requests/dlgT"), {organizationUID: "o1", companyUID: "coA",
        status: "pending", requestType: "new_delegate", supervisorUid: "supD", receiptImagePath: "x"});
      await setDoc(doc(db, "storage_upload_intents/dlgT"), {companyUID: "coA"});
      for (const f of Object.values(FIELDS)) await uploadBytes(ref(ctx.storage(), f.obj), bytes);
    });
  });

  after(async () => {
    if (env) {
      // eslint-disable-next-line no-console
      console.log("\nTAS-331 matrix (F=Firestore read, S=Storage read):\n" +
        Object.entries(matrix).map(([field, row]) => `${field}\n  ${Object.entries(row)
          .map(([p, r]) => `${p}:${r.fs ? "F" : "-"}${r.st ? "S" : "-"}`).join(" ")}`).join("\n"));
      await env.cleanup();
    }
  });

  function ctxFor(name) {
    if (STAFF[name]) return env.authenticatedContext(name, {firebase: {sign_in_provider: "password"}});
    const d = DELEGATES[name];
    return env.authenticatedContext(d.uid, {firebase: {sign_in_provider: "custom"}, role: "delegate", ...d.claims});
  }

  async function allowed(p) {
    try {
      await p;
      return true;
    } catch (e) {
      return false;
    }
  }

  for (const [field, f] of Object.entries(FIELDS)) {
    test(`${field}: storage read == Firestore read (known gaps listed)`, async () => {
      matrix[field] = {};
      const gaps = [];
      const wider = [];
      for (const p of PRINCIPALS) {
        const ctx = ctxFor(p);
        const fs = await allowed(getDoc(doc(ctx.firestore(), f.doc)));
        const st = await allowed(getBytes(ref(ctx.storage(), f.obj)));
        matrix[field][p] = {fs, st};
        if (fs && !st && !KNOWN_GAP.has(`${field}|${p}`)) gaps.push(p);
        if (st && !fs) wider.push(p);
      }
      assert.deepEqual(wider, [], `${field}: storage wider than Firestore for ${wider.join(", ")}`);
      assert.deepEqual(gaps, [], `${field}: Firestore allows but storage denies ${gaps.join(", ")}`);
    });
  }

  test("a supervisor of another company cannot read the folder", async () => {
    const st = await allowed(getBytes(ref(ctxFor("supCoB").storage(), FIELDS[Object.keys(FIELDS)[0]].obj)));
    assert.equal(st, false);
  });
});
