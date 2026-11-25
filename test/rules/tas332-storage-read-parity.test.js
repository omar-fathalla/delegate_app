/**
 * TAS-332: storage.rules read access for the TAS-42 path fields must match
 * who can read the Firestore doc that stores the path (no wider).
 *
 * The app (TAS-42) resolves the stored Storage path with getDownloadURL at
 * display time. If storage.rules deny a role that can read the doc, that role
 * loses the file as soon as `write_legacy_storage_urls` is turned off.
 *
 * Each case reads the Firestore doc AND the Storage object with the same
 * principal, then checks:
 *   - storage allowed  => Firestore allowed   (never wider)
 *   - Firestore allowed => storage allowed    (no gap), except the cases in
 *     KNOWN_WIDER (storage wider than Firestore, pre-existing, documented).
 */
"use strict";
const {describe, test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, isBudgetDenial} = require("./_rules_testing");
const {doc, setDoc, getDoc} = require("firebase/firestore");
const {ref, uploadBytes, getBytes} = require("firebase/storage");

function splitHost(envName, fallback) {
  const raw = process.env[envName] || fallback;
  const [host, port] = raw.split(":");
  return {host, port: Number(port)};
}

const bytes = Uint8Array.from(Buffer.from("tas332 fixture\n"));

// Staff principals (users/{uid} docs). No users doc for delegate tokens.
const STAFF = {
  superA: {role: "super_admin"},
  techA: {role: "technical_support"},
  hrA: {role: "hr", companyUID: "coA", organizationUID: "o1"},
  supA: {role: "admin", companyUID: "coA", organizationUID: "o1"},
  accA: {role: "accountant", companyUID: "coA", organizationUID: "o1"},
  mkA: {role: "marketing", companyUID: "coA", organizationUID: "o1"},
  bmA: {role: "branches_marketing", companyUID: "coA", organizationUID: "o1"},
  orgAdm: {role: "organization_admin", companyUID: "", organizationUID: "o1"},
  orgAdmDash: {role: "org-admin", companyUID: "", organizationUID: "o1"},
  mkOrg: {role: "marketing_promotion", companyUID: "", organizationUID: "o1"},
  bmOrg: {role: "branches_marketing_manager", companyUID: "", organizationUID: "o1"},
  mkCoA2: {role: "marketing", companyUID: "coA2", organizationUID: "o1"},
  hrA2: {role: "hr", companyUID: "coA2", organizationUID: "o1"},
  hrB: {role: "hr", companyUID: "coB", organizationUID: "o2"},
  orgAdmO2: {role: "organization_admin", companyUID: "", organizationUID: "o2"},
};

// Delegate custom-token claims. dlgM signs in as authM but its delegate doc
// id is dlgM (delegateId claim), like a delegate in several companies.
const DELEGATES = {
  dlgA: {uid: "dlgA", claims: {delegateId: "dlgA", companyId: "coA", orgId: "o1"}},
  dlgB: {uid: "dlgB", claims: {delegateId: "dlgB", companyId: "coA", orgId: "o1"}},
  dlgM: {uid: "authM", claims: {delegateId: "dlgM", delegateIds: ["dlgM"], companyId: "coA", orgId: "o1"}},
  dlgOrgIds: {uid: "dlgX", claims: {delegateId: "dlgX", companyId: "coB", orgId: "o2", orgIds: ["o2", "o1"], companyIds: ["coB"]}},
  dlgOther: {uid: "dlgOther", claims: {delegateId: "dlgOther", companyId: "coB", orgId: "o2"}},
};

const PRINCIPALS = [...Object.keys(STAFF), ...Object.keys(DELEGATES)];

// field -> Firestore doc path + Storage object path (+ upload metadata).
const FIELDS = {
  "captured_photos.photoPath": {
    doc: "organizations/o1/companies/coA/photo_permissions/p1/captured_photos/ph1",
    data: {companyUID: "coA", organizationUID: "o1", delegateUID: "dlgA"},
    obj: "organizations/o1/companies/coA/permissions/p1/photo_dlgA_1.jpg",
    meta: {customMetadata: {userId: "dlgA"}},
  },
  "feedbacks.screenshotPath": {
    doc: "feedbacks/f1",
    data: {userId: "dlgA", companyUID: "coA", organizationUID: "o1"},
    obj: "feedback_screenshots/feedback_dlgA_1.jpg",
    meta: {customMetadata: {userId: "dlgA"}},
  },
  "leave_requests.attachmentPath": {
    doc: "leave_requests/l1",
    data: {delegateUid: "dlgA", companyUID: "coA", organizationUID: "o1", status: "pending"},
    obj: "leave_attachments/coA/dlgA/1_sick.jpg",
  },
  "leave_requests.attachmentPath (delegateId claim)": {
    doc: "leave_requests/l2",
    data: {delegateUid: "dlgM", companyUID: "coA", organizationUID: "o1", status: "pending"},
    obj: "leave_attachments/coA/dlgM/1_sick.jpg",
  },
  "penalties.evidenceFiles[].filePath": {
    doc: "penalties/pen1",
    data: {
      targetDelegateId: "dlgA", delegateUid: "dlgA",
      companyUID: "coA", companyId: "coA", organizationUID: "o1", organizationId: "o1",
    },
    obj: "penalties/coA/evidence/pen1/1_a.jpg",
  },
  "penalties.evidenceFiles[].filePath (delegateId claim)": {
    doc: "penalties/pen2",
    data: {
      targetDelegateId: "dlgM", delegateUid: "dlgM",
      companyUID: "coA", companyId: "coA", organizationUID: "o1", organizationId: "o1",
    },
    obj: "penalties/coA/evidence/pen2/1_a.jpg",
  },
  "private_label_audits.productPhotoPath/pricePhotoPath": {
    doc: "organizations/o1/private_label_audits/a1",
    data: {organizationUID: "o1", companyUID: "coA", delegateUid: "dlgA"},
    obj: "organizations/o1/private_label/2026-11/a1_product.jpg",
  },
  "private_label_products.imagePath": {
    doc: "organizations/o1/private_label_products/pr1",
    data: {organizationUID: "o1", name: "x"},
    obj: "organizations/o1/private_label_products/pr1.jpg",
  },
};

// Storage wider than Firestore, kept on purpose (pre-existing, see TAS-332):
// feedback screenshots have no company in the path or metadata, so any named
// staff reads them (the rule comment calls this the residual).
const KNOWN_WIDER = new Set([
  "feedbacks.screenshotPath|hrB",
  "feedbacks.screenshotPath|orgAdmO2",
  "feedbacks.screenshotPath|mkA",
  "feedbacks.screenshotPath|mkCoA2",
  "feedbacks.screenshotPath|hrA2",
  "feedbacks.screenshotPath|mkOrg",
  "feedbacks.screenshotPath|bmOrg",
  "feedbacks.screenshotPath|orgAdmDash",
]);

// true / false, or "budget" when Firestore ran out of its 1000-expression
// budget: the rule's intent is then unknown, so that cell is reported but not
// compared (TAS-105 tracks those denials).
// Cells where Firestore hits the budget on a single get: the storage result
// must follow what the firestore.rules condition says (read by hand).
const BUDGET_INTENT = {
  "captured_photos.photoPath": {hrB: false, orgAdmO2: false, dlgM: true, dlgOrgIds: true, dlgOther: false},
  "leave_requests.attachmentPath": {
    mkA: true, bmA: true, orgAdmDash: true, mkOrg: true, mkCoA2: true,
    bmOrg: false, hrA2: false, hrB: false, orgAdmO2: false,
  },
};
BUDGET_INTENT["leave_requests.attachmentPath (delegateId claim)"] = BUDGET_INTENT["leave_requests.attachmentPath"];

async function allowed(promise) {
  try {
    await promise;
    return true;
  } catch (e) {
    if (isBudgetDenial(e)) return "budget";
    const code = String((e && e.code) || "");
    const msg = String((e && e.message) || "");
    if (/permission|unauthorized/i.test(code + " " + msg)) return false;
    throw e;
  }
}

describe("TAS-332 storage read parity with Firestore", () => {
  let env;
  const fsHost = splitHost("FIRESTORE_EMULATOR_HOST", "127.0.0.1:8080");
  const stHost = splitHost("FIREBASE_STORAGE_EMULATOR_HOST", "127.0.0.1:9199");
  const matrix = {};

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: "demo-tas332",
      firestore: {
        host: fsHost.host,
        port: fsHost.port,
        rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8"),
      },
      storage: {
        host: stHost.host,
        port: stHost.port,
        rules: readFileSync(resolve(__dirname, "../../storage.rules"), "utf8"),
      },
    });
    await env.clearFirestore();
    await env.clearStorage();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (const [uid, data] of Object.entries(STAFF)) {
        await setDoc(doc(db, `users/${uid}`), data);
      }
      await setDoc(doc(db, "organizations/o1"), {name: "o1"});
      await setDoc(doc(db, "organizations/o2"), {name: "o2"});
      await setDoc(doc(db, "organizations/o1/companies/coA"), {name: "coA"});
      await setDoc(doc(db, "organizations/o1/companies/coA2"), {name: "coA2"});
      await setDoc(doc(db, "organizations/o2/companies/coB"), {name: "coB"});
      for (const f of Object.values(FIELDS)) {
        await setDoc(doc(db, f.doc), f.data);
        await uploadBytes(ref(ctx.storage(), f.obj), bytes, f.meta);
      }
    });
  });

  after(async () => {
    if (env) {
      // eslint-disable-next-line no-console
      console.log("\nTAS-332 matrix (F=Firestore read, B=Firestore budget deny, S=Storage read):\n" +
        Object.entries(matrix).map(([field, row]) => `${field}\n  ${Object.entries(row)
          .map(([p, r]) => `${p}:${r.fs === "budget" ? "B" : r.fs ? "F" : "-"}${r.st ? "S" : "-"}`).join(" ")}`).join("\n"));
      await env.cleanup();
    }
  });

  function ctxFor(name) {
    if (STAFF[name]) {
      return env.authenticatedContext(name, {firebase: {sign_in_provider: "password"}});
    }
    const d = DELEGATES[name];
    return env.authenticatedContext(d.uid, {
      firebase: {sign_in_provider: "custom"},
      role: "delegate",
      ...d.claims,
    });
  }

  for (const [field, f] of Object.entries(FIELDS)) {
    test(`${field}: storage read == Firestore read for every role`, async () => {
      matrix[field] = {};
      const gaps = [];
      const wider = [];
      for (const p of PRINCIPALS) {
        const ctx = ctxFor(p);
        const fs = await allowed(getDoc(doc(ctx.firestore(), f.doc)));
        const st = await allowed(getBytes(ref(ctx.storage(), f.obj)));
        matrix[field][p] = {fs, st};
        assert.notEqual(st, "budget");
        if (fs === "budget") {
          const intent = (BUDGET_INTENT[field] || {})[p];
          if (intent !== undefined) assert.equal(st, intent, `${field}|${p}: budget cell, expected storage ${intent}`);
          continue;
        }
        if (fs && !st) gaps.push(p);
        if (st && !fs && !KNOWN_WIDER.has(`${field}|${p}`)) wider.push(p);
      }
      assert.deepEqual(wider, [], `${field}: storage wider than Firestore for ${wider.join(", ")}`);
      assert.deepEqual(gaps, [], `${field}: Firestore allows but storage denies ${gaps.join(", ")}`);
    });
  }

  test("org-wide staff of another chain cannot reach a company by forging the org segment", async () => {
    // orgAdmO2 names its own org with a company that is not under it.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), "organizations/o2/companies/coA/permissions/p1/photo_dlgA_2.jpg"), bytes);
    });
    const st = await allowed(getBytes(ref(ctxFor("orgAdmO2").storage(), "organizations/o2/companies/coA/permissions/p1/photo_dlgA_2.jpg")));
    assert.equal(st, false);
    const dlg = await allowed(getBytes(ref(ctxFor("dlgOther").storage(), "organizations/o2/companies/coA/permissions/p1/photo_dlgA_2.jpg")));
    assert.equal(dlg, false);
  });

  test("a delegate cannot read another company's penalty evidence by naming its own penalty id", async () => {
    // pen1 targets dlgA in coA; the same id under coB must not open for dlgA.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), "penalties/coB/evidence/pen1/x.jpg"), bytes);
    });
    const st = await allowed(getBytes(ref(ctxFor("dlgA").storage(), "penalties/coB/evidence/pen1/x.jpg")));
    assert.equal(st, false);
  });

  test("reads only: new delegate/org read paths do not open writes", async () => {
    assert.equal(await allowed(uploadBytes(ref(ctxFor("dlgA").storage(), "organizations/o1/private_label_products/new.jpg"), bytes)), false);
    assert.equal(await allowed(uploadBytes(ref(ctxFor("dlgA").storage(), "penalties/coA/evidence/pen1/new.jpg"), bytes)), false);
    assert.equal(await allowed(uploadBytes(ref(ctxFor("accA").storage(), "leave_attachments/coA/dlgA/new.jpg"), bytes)), false);
    assert.equal(await allowed(uploadBytes(ref(ctxFor("orgAdm").storage(), "leave_attachments/coA/dlgA/new.jpg"), bytes)), false);
  });
});
