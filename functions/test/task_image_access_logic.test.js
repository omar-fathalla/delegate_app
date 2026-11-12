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

test("finalize should strip tokens on new and legacy task image paths, including orphans", () => {
  assert.equal(L.shouldStripTaskImageDownloadToken("task_images/coA/sup1/task_sup1_1.jpg"), true);
  assert.equal(L.shouldStripTaskImageDownloadToken("organizations/o1/task_images/sup1/uuid.jpg"), true);
  assert.equal(L.shouldStripTaskImageDownloadToken("delegate_documents/folderA/x.jpg"), false);
  assert.equal(L.shouldStripTaskImageDownloadToken("task_images/coA/sup1/task_sup1_2_1.jpg"), false);
});

test("a held recipient already in the send-time grant can still read", () => {
  const path = "task_images/coA/sup1/task_sup1_1.jpg";
  const grant = {
    imagePath: path,
    createdBy: "sup1",
    readerUids: ["sup1", "dlgA"],
    companyUID: "coA",
  };
  const r = L.decideAuthorizedTaskImageRead({
    callerUid: "dlgA",
    requestedPath: path,
    taskImagePath: path,
    taskCompanyId: "coA",
    createdBy: "sup1",
    grant,
    fallbackRecipientIds: [], // live notify set would have dropped the held user
  });
  assert.deepEqual(r, {ok: true});
});

test("title-only or non-image edits do not affect path authorization", () => {
  const path = "task_images/coA/sup1/task_sup1_1.jpg";
  const r = L.decideAuthorizedTaskImageRead({
    callerUid: "dlgA",
    requestedPath: path,
    taskImagePath: path,
    taskCompanyId: "coA",
    createdBy: "sup1",
    grant: {imagePath: path, createdBy: "sup1", readerUids: ["dlgA"], companyUID: "coA"},
    fallbackRecipientIds: ["dlgA"],
  });
  assert.deepEqual(r, {ok: true});
});

test("taskImagePathsFromTask prefers the list and falls back to imagePath, capped at 3", () => {
  assert.deepEqual(L.taskImagePathsFromTask({
    imagePath: "task_images/coA/sup1/task_sup1_1.jpg",
  }), ["task_images/coA/sup1/task_sup1_1.jpg"]);
  assert.deepEqual(L.taskImagePathsFromTask({
    imagePath: "task_images/coA/sup1/task_sup1_1.jpg",
    imagePaths: [
      "task_images/coA/sup1/task_sup1_2.jpg",
      "task_images/coA/sup1/task_sup1_3.jpg",
    ],
  }), [
    "task_images/coA/sup1/task_sup1_2.jpg",
    "task_images/coA/sup1/task_sup1_3.jpg",
  ]);
  const many = L.taskImagePathsFromTask({
    imagePaths: [
      "task_images/coA/sup1/task_sup1_1.jpg",
      "task_images/coA/sup1/task_sup1_2.jpg",
      "task_images/coA/sup1/task_sup1_3.jpg",
      "task_images/coA/sup1/task_sup1_4.jpg",
    ],
  });
  assert.equal(many.length, 3);
  assert.equal(L.MAX_TASK_IMAGES, 3);
});

test("a recipient can read the second image on a multi-image task; a path not on the task is denied", () => {
  const paths = [
    "task_images/coA/sup1/task_sup1_1.jpg",
    "task_images/coA/sup1/task_sup1_2.jpg",
  ];
  const grant2 = {
    imagePath: paths[1],
    createdBy: "sup1",
    readerUids: ["sup1", "dlgA"],
    companyUID: "coA",
  };
  const ok = L.decideAuthorizedTaskImageRead({
    callerUid: "dlgA",
    requestedPath: paths[1],
    taskImagePath: paths[0],
    taskImagePaths: paths,
    taskCompanyId: "coA",
    createdBy: "sup1",
    grant: grant2,
    fallbackRecipientIds: [],
  });
  assert.deepEqual(ok, {ok: true});
  const denied = L.decideAuthorizedTaskImageRead({
    callerUid: "dlgA",
    requestedPath: "task_images/coA/sup1/task_sup1_9.jpg",
    taskImagePath: paths[0],
    taskImagePaths: paths,
    taskCompanyId: "coA",
    createdBy: "sup1",
    grant: grant2,
    fallbackRecipientIds: ["dlgA"],
  });
  assert.equal(denied.ok, false);
  assert.equal(denied.reason, "path_mismatch");
});

test("legacy single imagePath still authorizes without an imagePaths list", () => {
  const path = "task_images/coA/sup1/task_sup1_1.jpg";
  const r = L.decideAuthorizedTaskImageRead({
    callerUid: "dlgA",
    requestedPath: path,
    taskImagePath: path,
    taskCompanyId: "coA",
    createdBy: "sup1",
    grant: {imagePath: path, createdBy: "sup1", readerUids: ["dlgA"], companyUID: "coA"},
    fallbackRecipientIds: [],
  });
  assert.deepEqual(r, {ok: true});
});
