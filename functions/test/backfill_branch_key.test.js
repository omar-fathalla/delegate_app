const test = require("node:test");
const assert = require("node:assert/strict");
const {branchKey, branchKeyPatch, parseArgs, assertSafe, run} =
  require("../scripts/backfill_branch_key");

test("branchKey matches the Dart normalizer", () => {
  assert.equal(branchKey("  أبو   يوسف "), "ابو يوسف");
  assert.equal(branchKey("إبراهيمية"), "ابراهيميه");
  assert.equal(branchKey("مستشفى الكبرى"), "مستشفي الكبري");
  assert.equal(branchKey("Branch ALPHA"), "branch alpha");
  assert.equal(branchKey(null), "");
});

test("patch skips keyed docs and docs without branchName", () => {
  assert.deepEqual(branchKeyPatch({branchName: "سموحة"}), {branchKey: "سموحه"});
  assert.equal(branchKeyPatch({branchName: "سموحة", branchKey: "x"}), null);
  assert.equal(branchKeyPatch({branchName: "  "}), null);
  assert.equal(branchKeyPatch({}), null);
});

test("dry-run is the default and commit needs explicit prod ack", () => {
  assert.equal(parseArgs([]).commit, false);
  assert.equal(parseArgs(["--commit", "--dry-run"]).commit, false);
  assert.throws(() => assertSafe(parseArgs(["--commit"]), ""), /i-understand-prod/);
  assert.doesNotThrow(() => assertSafe(parseArgs([]), ""));
  assert.doesNotThrow(() => assertSafe(parseArgs(["--commit"]), "127.0.0.1:8080"));
  assert.throws(() => assertSafe(parseArgs(["--collection", "users"]), ""), /Refusing/);
});

function fakeDb(docs) {
  const writes = [];
  const sorted = [...docs].sort((a, b) => (a.id < b.id ? -1 : 1));
  const query = (after, lim) => ({
    limit: (n) => query(after, n),
    startAfter: (id) => query(id, lim),
    orderBy: () => query(after, lim),
    get: async () => {
      const rows = sorted.filter((d) => after == null || d.id > after).slice(0, lim);
      return {
        empty: rows.length === 0,
        size: rows.length,
        docs: rows.map((d) => ({id: d.id, ref: d.id, data: () => d.data})),
      };
    },
  });
  return {
    writes,
    collection: () => query(null, 500),
    batch: () => {
      const pending = [];
      return {update: (ref, p) => pending.push([ref, p]), commit: async () => writes.push(...pending)};
    },
  };
}
const fakeAdmin = {firestore: {FieldPath: {documentId: () => "__name__"}}};

test("dry-run run() counts but never writes", async () => {
  const db = fakeDb([
    {id: "a", data: {branchName: "سموحة"}},
    {id: "b", data: {branchName: "سموحه", branchKey: "سموحه"}},
    {id: "c", data: {}},
  ]);
  const r = await run(db, fakeAdmin, {...parseArgs([]), pageSize: 2, checkpoint: null}, () => {});
  assert.equal(r.scanned, 3);
  assert.equal(r.wouldUpdate, 1);
  assert.equal(r.alreadyKeyed, 1);
  assert.equal(r.noBranchName, 1);
  assert.equal(r.updated, 0);
  assert.equal(db.writes.length, 0);
});

test("repeat dry-runs rescan everything; checkpoint cleared on completion", async () => {
  const os = require("os");
  const fs = require("fs");
  const path = require("path");
  const cp = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "bk-")), "cp.json");
  const docs = [
    {id: "a", data: {branchName: "سموحة"}},
    {id: "b", data: {branchName: "رشدي"}},
    {id: "c", data: {branchName: "ميامي"}},
  ];
  const opts = {...parseArgs([]), pageSize: 2, checkpoint: cp, report: null};
  assert.equal(opts.resume, false, "dry-run does not resume by default");
  const r1 = await run(fakeDb(docs), fakeAdmin, opts, () => {});
  const r2 = await run(fakeDb(docs), fakeAdmin, opts, () => {});
  assert.equal(r1.wouldUpdate, 3);
  assert.equal(r2.wouldUpdate, 3);
  assert.equal(fs.existsSync(cp), false);
  // Interrupted commit (maxPages) keeps the checkpoint and resumes.
  const commitOpts = {...parseArgs(["--commit"]), pageSize: 2, maxPages: 1, checkpoint: cp, report: null};
  assert.equal(commitOpts.resume, true);
  assert.equal(parseArgs(["--commit", "--no-resume"]).resume, false);
  const db = fakeDb(docs);
  await run(db, fakeAdmin, commitOpts, () => {});
  assert.equal(fs.existsSync(cp), true);
  await run(db, fakeAdmin, {...commitOpts, maxPages: Infinity}, () => {});
  assert.deepEqual(db.writes.map((w) => w[0]).sort(), ["a", "b", "c"]);
  assert.equal(fs.existsSync(cp), false);
});
