/**
 * Backfill delegateSource / chainOrigin on nested delegate docs (Phase 1 item 1).
 *
 * Dry-run by default. Writes a JSON report (counts only in the console;
 * the file may include document paths and uids, never names, phones, or
 * national IDs). Pass --rollback on a dry-run to save the rollback file
 * *before* --apply. --apply also rewrites that file immediately before
 * any writes.
 *
 *   node scripts/backfill-delegate-source.js --project tashil-dev
 *   node scripts/backfill-delegate-source.js --project tashil-dev --rollback ./rollback.json
 *   node scripts/backfill-delegate-source.js --project tashil-dev --apply --rollback ./rollback.json
 *   node scripts/backfill-delegate-source.js --project tashil-dev --revert --run <runId>
 *   node scripts/backfill-delegate-source.js --project tashil-dev --revert --rollback ./rollback.json
 *
 * Never runs against practice-firebase-72df1 unless a later, explicit
 * written go passes --allow-prod-project=practice-firebase-72df1.
 * Requires `npm run build` in functions/ first (loads lib/delegate_source_logic).
 */
"use strict";

const fs = require("fs");
const path = require("path");
const {randomBytes} = require("crypto");
const {parseArgs: parseCommonArgs, assertTarget, PROD_PROJECTS} =
  require("./p0-common");

function loadLogic() {
  const compiled = path.join(__dirname, "../lib/delegate_source_logic.js");
  if (!fs.existsSync(compiled)) {
    throw new Error("Missing functions/lib/delegate_source_logic.js — run npm run build in functions/ first.");
  }
  return require("../lib/delegate_source_logic");
}

function parseArgs(argv) {
  const common = parseCommonArgs(argv);
  const out = {
    project: common.project,
    apply: common.apply,
    allowProd: common.allowProd,
    revert: false,
    runId: "",
    report: "",
    rollback: "",
    pageSize: 200,
  };
  const rest = common.rest;
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    if (a === "--revert") out.revert = true;
    else if (a === "--run") out.runId = rest[++i] || "";
    else if (a.startsWith("--run=")) out.runId = a.slice(6);
    else if (a === "--report") out.report = rest[++i] || "";
    else if (a.startsWith("--report=")) out.report = a.slice(9);
    else if (a === "--rollback") out.rollback = rest[++i] || "";
    else if (a.startsWith("--rollback=")) out.rollback = a.slice(11);
    else if (a === "--page-size") out.pageSize = Number(rest[++i]);
    else if (a === "--help" || a === "-h") {
      console.log("See file header for usage.");
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${a}`);
    }
  }
  return out;
}

function str(v) {
  return typeof v === "string" ? v.trim() : "";
}

function newRunId() {
  const t = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");
  return `dev-${t}-${randomBytes(3).toString("hex")}`;
}

function chainFromDoc(doc) {
  const data = doc.data() || {};
  return {
    path: doc.ref.path,
    uid: str(data.uid) || doc.id,
    organizationUID: str(data.organizationUID || data.organizationId),
    companyUID: str(data.companyUID || data.companyId),
    approvedRequestId: str(data.approvedRequestId),
    registeredVia: str(data.registeredVia),
    statusReason: str(data.statusReason),
    version: data.version,
    alreadyStamped: str(data.delegateSource) !== "",
    existingSource: data.delegateSource ?? null,
    existingOrigin: data.chainOrigin ?? null,
    existingBy: data.delegateSourceInferredBy ?? null,
    existingAt: data.delegateSourceAt ?? null,
    existingRunId: data.delegateSourceRunId ?? null,
  };
}

function emptyCounts() {
  return {
    docs: 0,
    alreadyStamped: 0,
    planned: 0,
    written: 0,
    skipped: 0,
    bySource: {web: 0, app: 0},
    byConfidence: {high: 0, low: 0, review: 0},
    byRule: {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
    byOrigin: {
      web_request: 0,
      app_new_delegate: 0,
      app_supervisor_copy: 0,
      app_add_organization: 0,
      unknown: 0,
    },
    disagreeWithNightlyApp: 0,
    unknownUids: [],
    lowConfidenceUids: [],
  };
}

async function loadAllDelegates(db, pageSize) {
  const out = [];
  let last = null;
  for (;;) {
    let q = db.collectionGroup("delegates").orderBy("__name__").limit(pageSize);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) out.push(doc);
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < pageSize) break;
  }
  return out;
}

async function loadRequest(db, uid, cache) {
  if (cache.has(uid)) return cache.get(uid);
  const snap = await db.collection("delegate_requests").doc(uid).get();
  let ev = null;
  if (snap.exists) {
    const d = snap.data() || {};
    ev = {
      id: snap.id,
      requestType: str(d.requestType),
      status: str(d.status),
      supervisorUid: str(d.supervisorUid),
      existingDelegateUid: str(d.existingDelegateUid),
      organizationUID: str(d.organizationUID),
    };
  }
  cache.set(uid, ev);
  return ev;
}

function addWebCreate(byUid, d, fallbackOrg, fallbackCompany) {
  const id = str(d.targetDelegateId);
  if (!id) return;
  const list = byUid.get(id) || [];
  list.push({
    targetDelegateId: id,
    organizationUID: str(d.organizationUID) || fallbackOrg || "",
    companyUID: str(d.companyUID) || fallbackCompany || "",
  });
  byUid.set(id, list);
}

// Path-based fallback: web creates live at
// organizations/{org}/companies/{company}/requests. This does not need
// the collection-group composite index.
async function loadWebCreatesFromNestedPaths(db, docs, uidSet) {
  const byUid = new Map();
  const seen = new Set();
  const pairs = [];
  for (const doc of docs) {
    const ev = chainFromDoc(doc);
    const org = ev.organizationUID;
    const company = ev.companyUID;
    if (!org || !company) continue;
    const key = `${org}/${company}`;
    if (seen.has(key)) continue;
    seen.add(key);
    pairs.push({org, company});
  }
  let ok = 0;
  let lastError = "";
  for (const {org, company} of pairs) {
    try {
      const snap = await db.collection(`organizations/${org}/companies/${company}/requests`)
        .where("actionType", "==", "create")
        .get();
      ok++;
      for (const doc of snap.docs) {
        const d = doc.data() || {};
        const id = str(d.targetDelegateId);
        if (id && uidSet.has(id)) addWebCreate(byUid, d, org, company);
      }
    } catch (e) {
      lastError = e.message;
      console.warn(`web requests nested query failed at ${org}/${company}:`, e.message);
    }
  }
  return {byUid, pairs: pairs.length, ok, lastError};
}

async function loadWebCreates(db, uids, docs) {
  const byUid = new Map();
  const unique = [...new Set(uids)];
  const uidSet = new Set(unique);
  try {
    for (let i = 0; i < unique.length; i += 10) {
      const batch = unique.slice(i, i + 10);
      const snap = await db.collectionGroup("requests")
        .where("actionType", "==", "create")
        .where("targetDelegateId", "in", batch)
        .get();
      for (const doc of snap.docs) {
        addWebCreate(byUid, doc.data() || {});
      }
    }
    return {byUid, webQueryOk: true, webQueryMode: "collection-group"};
  } catch (e) {
    console.warn("web requests collection-group query failed (missing index?):", e.message);
    const fallback = await loadWebCreatesFromNestedPaths(db, docs, uidSet);
    const used = fallback.ok > 0;
    return {
      byUid: fallback.byUid,
      webQueryOk: used,
      webQueryMode: used ? "nested-path-fallback" : "failed",
      webQueryError: e.message + (fallback.lastError ? `; fallback: ${fallback.lastError}` : ""),
    };
  }
}

async function loadAddOrgRequests(db, uids) {
  const set = new Set();
  try {
    for (let i = 0; i < uids.length; i += 10) {
      const batch = uids.slice(i, i + 10);
      const snap = await db.collection("delegate_requests")
        .where("requestType", "==", "add_organization")
        .where("existingDelegateUid", "in", batch)
        .limit(200)
        .get();
      for (const doc of snap.docs) {
        const id = str((doc.data() || {}).existingDelegateUid);
        if (id) set.add(id);
      }
    }
  } catch (e) {
    console.warn("add_organization request query failed:", e.message);
  }
  return set;
}

async function loadSupervisorOrgs(db, supervisorUids) {
  const map = new Map();
  const unique = [...new Set(supervisorUids.filter(Boolean))];
  for (const id of unique) {
    try {
      const snap = await db.collection("users").doc(id).get();
      map.set(id, str(snap.data()?.organizationUID));
    } catch (_) {
      map.set(id, "");
    }
  }
  return map;
}

function sanitizeReport(report) {
  // The report must not include names, phones, or national IDs.
  return report;
}

async function runBackfill(db, L, args) {
  const runId = newRunId();
  const counts = emptyCounts();
  const planned = [];
  const docs = await loadAllDelegates(db, args.pageSize);
  counts.docs = docs.length;

  const byUid = new Map();
  for (const doc of docs) {
    const ev = chainFromDoc(doc);
    const list = byUid.get(ev.uid) || [];
    list.push({doc, ev});
    byUid.set(ev.uid, list);
  }

  const uids = [...byUid.keys()];
  const reqCache = new Map();
  for (const uid of uids) {
    await loadRequest(db, uid, reqCache);
  }
  const {byUid: webByUid, webQueryOk, webQueryError, webQueryMode} = await loadWebCreates(db, uids, docs);
  const addOrgUids = await loadAddOrgRequests(db, uids);
  const supIds = [];
  for (const ev of reqCache.values()) {
    if (ev && ev.supervisorUid) supIds.push(ev.supervisorUid);
  }
  const supOrgs = await loadSupervisorOrgs(db, supIds);

  for (const [uid, items] of byUid) {
    const chainDocs = items.map((x) => x.ev);
    const appRequestById = reqCache.get(uid) || null;
    const person = L.inferPersonSource({
      uid,
      appRequestById,
      chainDocs,
      webCreates: webByUid.get(uid) || [],
    });
    const nightlyApp = !!(appRequestById &&
      require("../lib/subscription_logic").isAppAddedRegistration(
        appRequestById.id,
        appRequestById,
      ));
    // Nightly job only treats approved new_delegate as app. Pending (rule 2)
    // and low-confidence (rule 4) app stamps are listed as disagreements.
    if (person.source === "app" && !nightlyApp) counts.disagreeWithNightlyApp++;

    for (const {ev} of items) {
      if (ev.alreadyStamped) {
        counts.alreadyStamped++;
        counts.skipped++;
        continue;
      }
      const origin = L.inferChainOrigin({
        doc: ev,
        person,
        supervisorOrgId: appRequestById ? supOrgs.get(appRequestById.supervisorUid) : "",
        requestOrgId: appRequestById ? appRequestById.organizationUID : "",
        hasAddOrganizationRequest: addOrgUids.has(uid),
      });
      const fields = L.stampPayload(origin, person, "backfill", runId);
      planned.push({
        path: ev.path,
        uid,
        fields,
        rule: person.rule,
        confidence: person.confidence,
        previous: {
          delegateSource: ev.existingSource,
          chainOrigin: ev.existingOrigin,
          delegateSourceInferredBy: ev.existingBy,
          delegateSourceAt: ev.existingAt,
          delegateSourceRunId: ev.existingRunId,
        },
      });
      counts.planned++;
      counts.bySource[person.source]++;
      counts.byConfidence[person.confidence]++;
      counts.byRule[person.rule]++;
      counts.byOrigin[origin]++;
      if (person.confidence === "review" && !counts.unknownUids.includes(uid)) {
        counts.unknownUids.push(uid);
      }
      if (person.confidence === "low" && !counts.lowConfidenceUids.includes(uid)) {
        counts.lowConfidenceUids.push(uid);
      }
    }
  }

  const report = {
    project: args.project,
    mode: args.apply ? "apply" : "dry-run",
    runId,
    at: new Date().toISOString(),
    webQueryOk: webQueryOk !== false,
    webQueryMode: webQueryMode || null,
    webQueryError: webQueryError || null,
    counts: {
      docs: counts.docs,
      alreadyStamped: counts.alreadyStamped,
      planned: counts.planned,
      written: 0,
      skipped: counts.skipped,
      bySource: counts.bySource,
      byConfidence: counts.byConfidence,
      byRule: counts.byRule,
      byOrigin: counts.byOrigin,
      disagreeWithNightlyApp: counts.disagreeWithNightlyApp,
      unknownUidCount: counts.unknownUids.length,
      lowConfidenceUidCount: counts.lowConfidenceUids.length,
    },
    unknownUids: counts.unknownUids,
    lowConfidenceUids: counts.lowConfidenceUids,
  };

  const rollbackPath = args.rollback ||
    (args.apply ? path.join(process.cwd(), `delegate-source-rollback-${runId}.json`) : "");
  if (rollbackPath) {
    const rollback = {
      project: args.project,
      runId,
      at: new Date().toISOString(),
      entries: planned.map((p) => ({path: p.path, uid: p.uid, previous: p.previous, fields: p.fields})),
    };
    fs.writeFileSync(rollbackPath, JSON.stringify(rollback, null, 2));
    console.log(`wrote rollback file ${rollbackPath}`);
    report.rollbackFile = rollbackPath;
  }

  if (args.apply) {
    if (PROD_PROJECTS.has(args.project) && args.allowProd !== args.project) {
      throw new Error("Refusing to apply on prod without --allow-prod-project.");
    }

    let written = 0;
    for (let i = 0; i < planned.length; i += 400) {
      const batch = db.batch();
      const slice = planned.slice(i, i + 400);
      for (const p of slice) {
        batch.update(db.doc(p.path), {
          ...p.fields,
          delegateSourceAt: require("firebase-admin").firestore.FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      written += slice.length;
    }
    report.counts.written = written;
  }

  return {report, runId};
}

async function runRevert(db, args) {
  let entries = [];
  let runId = args.runId;
  if (args.rollback) {
    const raw = JSON.parse(fs.readFileSync(args.rollback, "utf8"));
    if (raw.project && raw.project !== args.project) {
      throw new Error(`Rollback file project ${raw.project} != ${args.project}`);
    }
    entries = raw.entries || [];
    runId = raw.runId || runId;
  } else if (runId) {
    const snap = await db.collectionGroup("delegates")
      .where("delegateSourceRunId", "==", runId)
      .get();
    entries = snap.docs.map((doc) => ({path: doc.ref.path, previous: null}));
  } else {
    throw new Error("--revert requires --run <runId> or --rollback <file>");
  }

  if (!args.apply) {
    return {
      report: {
        project: args.project,
        mode: "revert-dry-run",
        runId,
        at: new Date().toISOString(),
        counts: {planned: entries.length, written: 0},
      },
    };
  }

  const FieldValue = require("firebase-admin").firestore.FieldValue;
  let written = 0;
  for (let i = 0; i < entries.length; i += 400) {
    const batch = db.batch();
    const slice = entries.slice(i, i + 400);
    for (const e of slice) {
      const prev = e.previous || {};
      const hadSource = prev.delegateSource != null && prev.delegateSource !== "";
      if (!hadSource) {
        batch.update(db.doc(e.path), {
          delegateSource: FieldValue.delete(),
          chainOrigin: FieldValue.delete(),
          delegateSourceInferredBy: FieldValue.delete(),
          delegateSourceAt: FieldValue.delete(),
          delegateSourceRunId: FieldValue.delete(),
        });
      } else {
        batch.update(db.doc(e.path), {
          delegateSource: prev.delegateSource,
          chainOrigin: prev.chainOrigin,
          delegateSourceInferredBy: prev.delegateSourceInferredBy,
          delegateSourceAt: prev.delegateSourceAt,
          delegateSourceRunId: prev.delegateSourceRunId,
        });
      }
    }
    await batch.commit();
    written += slice.length;
  }
  return {
    report: {
      project: args.project,
      mode: "revert",
      runId,
      at: new Date().toISOString(),
      counts: {planned: entries.length, written},
    },
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const project = assertTarget(args);
  if (project !== "tashil-dev" && !/^demo-/.test(project)) {
    // Extra belt: this script is for tashil-dev (or emulators) unless a
    // later written go uses the p0 allow-prod escape hatch.
    if (!(PROD_PROJECTS.has(project) && args.allowProd === project)) {
      throw new Error(`Refusing project "${project}"`);
    }
  }
  args.project = project;

  const admin = require("firebase-admin");
  if (!admin.apps.length) {
    admin.initializeApp({
      projectId: project,
      serviceAccountId: project === "tashil-dev"
        ? "firebase-adminsdk-fbsvc@tashil-dev.iam.gserviceaccount.com"
        : undefined,
    });
  }
  const db = admin.firestore();
  const L = args.revert ? null : loadLogic();

  const result = args.revert ? await runRevert(db, args) : await runBackfill(db, L, args);
  const reportPath = args.report ||
    path.join(process.cwd(), `delegate-source-report-${result.report.runId || "revert"}.json`);
  fs.writeFileSync(reportPath, JSON.stringify(sanitizeReport(result.report), null, 2));
  console.log(`wrote report ${reportPath}`);
  console.log(JSON.stringify(result.report.counts, null, 2));
  console.log(`mode=${result.report.mode} runId=${result.report.runId || ""} project=${project}`);
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e.message || e);
    process.exit(1);
  });
}

module.exports = {parseArgs};
