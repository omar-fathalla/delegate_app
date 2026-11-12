"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/task_image_access_logic");

test("parses a new company-scoped owned filename and rejects N1-r mismatches", () => {
  const p = L.parseTaskImagePath("task_images/coA/sup1/task_sup1_171000.jpg");
  assert.deepEqual(p, {
    kind: "new", companyUID: "coA", uploaderUid: "sup1", fileName: "task_sup1_171000.jpg",
  });
  assert.equal(L.parseTaskImagePath("task_images/coA/sup1/task_sup2_171000.jpg"), null);
  assert.equal(L.parseTaskImagePath("task_images/coA/sup1/task_sup1_2_171000.jpg"), null);
  assert.equal(L.parseTaskImagePath("organizations/o1/task_images/sup1/random.jpg").kind, "legacy");
  assert.equal(L.parseTaskImagePath("organizations/o1/companies/coA/task_images/x.jpg"), null);
});

test("sender and intended recipients may read; others are denied", () => {
  const path = "task_images/coA/sup1/task_sup1_1.jpg";
  const base = {
    createdBy: "sup1",
    recipientIds: ["dlgA", "dlgB"],
    requestedPath: path,
    taskImagePath: path,
    taskCompanyId: "coA",
  };
  assert.deepEqual(L.canReadTaskImage({...base, callerUid: "sup1"}), {ok: true});
  assert.deepEqual(L.canReadTaskImage({...base, callerUid: "dlgA"}), {ok: true});
  assert.equal(L.canReadTaskImage({...base, callerUid: "dlgC"}).reason, "not_allowed");
  assert.equal(L.canReadTaskImage({...base, callerUid: "hrA"}).reason, "not_allowed");
  assert.equal(L.canReadTaskImage({...base, callerUid: "sup2"}).reason, "not_allowed");
  assert.equal(L.canReadTaskImage({
    ...base, callerUid: "dlgA", taskCompanyId: "coB",
  }).reason, "company_mismatch");
  assert.equal(L.canReadTaskImage({
    ...base, callerUid: "dlgA", requestedPath: "task_images/coA/sup1/task_sup1_other.jpg",
  }).reason, "path_mismatch");
});

test("legacy path is still recipient-scoped and ignores a public URL", () => {
  const path = "organizations/o1/task_images/sup1/uuid.jpg";
  const r = L.canReadTaskImage({
    callerUid: "dlgA",
    createdBy: "sup1",
    recipientIds: ["dlgA"],
    requestedPath: path,
    taskImagePath: path,
    taskCompanyId: "coA",
  });
  assert.deepEqual(r, {ok: true});
  assert.equal(L.canReadTaskImage({
    callerUid: "dlgOtherCo",
    createdBy: "sup1",
    recipientIds: ["dlgA"],
    requestedPath: path,
    taskImagePath: path,
    taskCompanyId: "coA",
  }).reason, "not_allowed");
});

test("unsent preview is only for the uploader on the new path", () => {
  const path = "task_images/coA/sup1/task_sup1_1.jpg";
  assert.deepEqual(L.canPreviewUnsentTaskImage({callerUid: "sup1", requestedPath: path}), {ok: true});
  assert.equal(L.canPreviewUnsentTaskImage({callerUid: "dlgA", requestedPath: path}).reason, "not_allowed");
  assert.equal(L.canPreviewUnsentTaskImage({
    callerUid: "sup1",
    requestedPath: "organizations/o1/task_images/sup1/uuid.jpg",
  }).reason, "invalid_path");
});

test("grant reader list always includes the sender and de-duplicates", () => {
  assert.deepEqual(L.grantReaderUids("sup1", ["dlgA", "sup1", "dlgA"]), ["sup1", "dlgA"]);
});
