const {describe, test} = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/task_proof_access_logic");

const path = "task_proof/coA/del1/proof_del1_171.jpg";

describe("task proof access", () => {
  test("parses owned N1-r paths and rejects collisions", () => {
    assert.deepEqual(L.parseTaskProofPath(path), {
      companyId: "coA",
      uploaderUid: "del1",
      fileName: "proof_del1_171.jpg",
    });
    assert.equal(L.parseTaskProofPath("task_proof/coA/del1/proof_del1_2_171.jpg"), null);
    assert.equal(L.parseTaskProofPath("task_proof/coA/del1/proof_del2_171.jpg"), null);
    assert.equal(L.parseTaskProofPath("task_images/coA/del1/task_del1_171.jpg"), null);
    assert.equal(L.shouldStripTaskProofDownloadToken(path), true);
    assert.equal(L.shouldStripTaskProofDownloadToken("task_images/coA/s/task_s_1.jpg"), false);
  });

  test("caps proof paths at 3 and drops invalid entries", () => {
    const paths = L.taskProofPathsFrom([
      path,
      "task_proof/coA/del1/proof_del1_172.jpg",
      "task_proof/coA/del1/proof_del1_173.jpg",
      "task_proof/coA/del1/proof_del1_174.jpg",
      "task_images/coA/del1/task_del1_1.jpg",
      "",
    ]);
    assert.equal(paths.length, 3);
    assert.equal(paths[2], "task_proof/coA/del1/proof_del1_173.jpg");
  });

  test("held or suspended uploaders cannot mint a new proof", () => {
    const base = {
      authenticated: true, anonymous: false, role: "delegate",
      callerUid: "del1", callerCompany: "coA", requestedCompany: "coA",
    };
    assert.deepEqual(L.canUploadTaskProof({...base, held: false, status: "active"}), {ok: true});
    assert.equal(L.canUploadTaskProof({...base, held: true, status: "active"}).reason, "caller_held");
    assert.equal(L.canUploadTaskProof({...base, held: false, status: "suspended"}).reason, "caller_held");
    assert.equal(L.canUploadTaskProof({
      ...base, held: false, status: "active", role: "hr",
    }).reason, "not_allowed");
    assert.equal(L.canUploadTaskProof({
      ...base, held: false, status: "active", role: "super-admin",
    }).reason, "not_allowed");
    assert.equal(L.canUploadTaskProof({
      authenticated: false, anonymous: false, role: "delegate",
      callerUid: "del1", callerCompany: "coA", requestedCompany: "coA",
      held: false, status: "active",
    }).reason, "sign_in_required");
  });

  test("read access matrix: uploader, sender, same-company supervisor only", () => {
    const base = {
      authenticated: true,
      anonymous: false,
      uploaderUid: "del1",
      taskCreatedBy: "sup1",
      taskCompanyId: "coA",
      requestedPath: path,
      proofPaths: [path],
      proofCompanyId: "coA",
    };
    assert.deepEqual(L.canReadTaskProof({
      ...base, callerUid: "del1", callerRole: "delegate", callerCompany: "coA",
    }), {ok: true});
    assert.deepEqual(L.canReadTaskProof({
      ...base, callerUid: "sup1", callerRole: "marketing", callerCompany: "coA",
    }), {ok: true});
    assert.deepEqual(L.canReadTaskProof({
      ...base, callerUid: "admin1", callerRole: "company-admin", callerCompany: "coA",
    }), {ok: true});
    assert.equal(L.canReadTaskProof({
      ...base, callerUid: "del2", callerRole: "delegate", callerCompany: "coA",
    }).reason, "not_allowed");
    assert.equal(L.canReadTaskProof({
      ...base, callerUid: "hr1", callerRole: "hr", callerCompany: "coA",
    }).reason, "not_allowed");
    assert.equal(L.canReadTaskProof({
      ...base, callerUid: "acc1", callerRole: "accountant", callerCompany: "coA",
    }).reason, "not_allowed");
    assert.equal(L.canReadTaskProof({
      ...base, callerUid: "mkt1", callerRole: "marketing", callerCompany: "coA",
    }).reason, "not_allowed");
    assert.equal(L.canReadTaskProof({
      ...base, callerUid: "adminB", callerRole: "company-admin", callerCompany: "coB",
    }).reason, "not_allowed");
    assert.equal(L.canReadTaskProof({
      ...base, callerUid: "tech1", callerRole: "technical_support", callerCompany: "coA",
    }).reason, "not_allowed");
    assert.equal(L.canReadTaskProof({
      ...base, callerUid: "root", callerRole: "super-admin", callerCompany: "coA",
    }).reason, "not_allowed");
    assert.equal(L.canReadTaskProof({
      ...base, callerUid: "", callerRole: "delegate", callerCompany: "coA",
      authenticated: false,
    }).reason, "sign_in_required");
    assert.equal(L.canReadTaskProof({
      ...base, callerUid: "del1", callerRole: "delegate", callerCompany: "coA",
      requestedPath: "task_proof/coA/del1/proof_del1_999.jpg",
    }).reason, "path_mismatch");
  });
});

describe("task proof write authorization (B1)", () => {
  const base = {
    callerUid: "dlgA",
    callerRole: "delegate",
    callerIds: [],
    callerCompanyIds: ["coA"],
    callerOrgIds: ["o1"],
    organizationId: "o1",
    task: {companyId: "coA", assignedTo: "dlgA", status: "inProgress"},
  };
  const ok = (over) => L.canWriteTaskProof({...base, ...over});

  test("assigned delegate may write; also via a delegateId claim", () => {
    assert.deepEqual(ok({}), {ok: true});
    assert.deepEqual(ok({callerUid: "auth-x", callerIds: ["dlgA"]}), {ok: true});
  });

  test("other-company / other-org HR is denied", () => {
    const r = ok({callerUid: "hrB", callerRole: "hr", callerCompanyIds: ["coB"], callerOrgIds: ["o2"]});
    assert.equal(r.ok, false);
    assert.equal(r.reason, "org_mismatch");
  });

  test("same-company accountant not assigned is denied", () => {
    assert.equal(ok({callerUid: "accA", callerRole: "accountant"}).reason, "not_assigned");
  });

  test("same-company accountant even if named as assignee is not an attach role", () => {
    const r = ok({callerUid: "accA", callerRole: "accountant",
      task: {companyId: "coA", assignedTo: "accA", status: "pending"}});
    assert.equal(r.reason, "not_allowed");
  });

  test("unassigned same-company marketing is denied on a single-assignee task", () => {
    assert.equal(ok({callerUid: "mpA", callerRole: "marketingPromotion"}).reason, "not_assigned");
  });

  test("cancelled task is denied even for the assignee", () => {
    assert.equal(ok({task: {companyId: "coA", assignedTo: "dlgA", status: "cancelled"}}).reason,
      "task_cancelled");
  });

  test("«الكل» accepts same-company field delegates only", () => {
    const all = {companyId: "coA", assignedTo: "all", status: "pending"};
    const allAr = {companyId: "coA", assignedTo: "الكل", status: "pending"};
    assert.deepEqual(ok({task: all}), {ok: true});
    assert.deepEqual(ok({task: allAr}), {ok: true});
    assert.equal(ok({task: all, callerRole: "marketing"}).ok, false);
    assert.equal(ok({task: all, callerRole: "branchesMarketingManager"}).ok, false);
    assert.equal(ok({task: all, callerRole: "marketingPromotion"}).ok, false);
    assert.equal(ok({task: all, callerRole: "hr"}).ok, false);
    assert.equal(ok({task: all, callerCompanyIds: ["coB"]}).reason, "company_mismatch");
  });

  test("sector tasks accept only the matching sector role", () => {
    const bm = {companyId: "coA", assignedTo: "all_branch_marketing", status: "pending"};
    const mp = {companyId: "coA", assignedTo: "all_marketing_promotion", status: "pending"};
    assert.deepEqual(ok({task: bm, callerRole: "branchesMarketingManager"}), {ok: true});
    assert.deepEqual(ok({task: bm, callerRole: "marketing"}), {ok: true});
    assert.equal(ok({task: bm, callerRole: "marketingPromotion"}).ok, false);
    assert.equal(ok({task: bm, callerRole: "delegate"}).ok, false);
    assert.deepEqual(ok({task: mp, callerRole: "marketing_promotion"}), {ok: true});
    assert.equal(ok({task: mp, callerRole: "marketing"}).ok, false);
    // Org-level sector staff (no company) in the same org.
    assert.deepEqual(ok({task: mp, callerRole: "marketingPromotion", callerCompanyIds: []}), {ok: true});
    assert.equal(ok({task: mp, callerRole: "marketingPromotion", callerCompanyIds: ["coB"]}).ok, false);
  });

  test("missing task / signed out", () => {
    assert.equal(ok({task: null}).reason, "task_not_found");
    assert.equal(ok({callerUid: ""}).reason, "sign_in_required");
  });

  test("display name comes from the profile, never the client", () => {
    assert.equal(L.proofDisplayNameFrom({displayName: "Shown", fullName: "Full"}), "Shown");
    assert.equal(L.proofDisplayNameFrom({firstName: "A", lastName: "B"}), "A B");
    assert.equal(L.proofDisplayNameFrom(null, {fullName: "Del Doc"}), "Del Doc");
    assert.equal(L.proofDisplayNameFrom({}, {name: "N"}), "N");
    assert.equal(L.proofDisplayNameFrom(null, null), "");
  });
});

describe("proof upload intent wiring (B1)", () => {
  const {readFileSync} = require("fs");
  const {resolve} = require("path");
  const src = readFileSync(resolve(__dirname, "../src/storage_upload_intent.ts"), "utf8");
  test("task_proof_image intents require a task and the B1 assignment check", () => {
    assert.match(src, /canWriteTaskProof\(/);
    assert.match(src, /"task_required"/);
    assert.match(src, /organizations\/\$\{taskOrg\}\/tasks\/\$\{taskId\}/);
  });
});
