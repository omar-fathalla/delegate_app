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
