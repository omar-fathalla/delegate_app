/**
 * Backfill denormalized fields onto attendance_logs check_in docs.
 *
 * Stamps (idempotent — skips fields already present; never overwrites):
 *   delegateName, phoneNumber, companyName, personalPhotoURL
 *   checkOutTime, checkOutDocId, checkOutLocation  (from matching check_out)
 *
 * Default is DRY-RUN. Only attendance_logs (never _testing).
 *
 *   node scripts/backfill-checkin-denorm.js --backup ~/Documents/...json
 *   node scripts/backfill-checkin-denorm.js --apply --i-understand-prod --backup ...
 */

"use strict";

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

function parseArgs(argv) {
  const out = {
    apply: false,
    org: null,
    from: null,
    to: null,
    collection: "attendance_logs",
    batchSize: 200,
    rateMs: 250,
    report: path.join(process.cwd(), "backfill-report.json"),
    pageSize: 500,
    allowProd: false,
    backup: null,
    maxUpdates: 20000,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--apply") out.apply = true;
    else if (a === "--i-understand-prod") out.allowProd = true;
    else if (a === "--org") out.org = argv[++i];
    else if (a === "--from") out.from = argv[++i];
    else if (a === "--to") out.to = argv[++i];
    else if (a === "--collection") out.collection = argv[++i];
    else if (a === "--batch-size") out.batchSize = Number(argv[++i]);
    else if (a === "--rate-ms") out.rateMs = Number(argv[++i]);
    else if (a === "--report") out.report = argv[++i];
    else if (a === "--page-size") out.pageSize = Number(argv[++i]);
    else if (a === "--backup") out.backup = argv[++i];
    else if (a === "--max-updates") out.maxUpdates = Number(argv[++i]);
    else if (a === "--help" || a === "-h") {
      console.log("See file header for usage.");
      process.exit(0);
    }
  }
  return out;
}

function parseDay(s, endExclusive) {
  if (!s) return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) throw new Error(`Bad date ${s}; expected YYYY-MM-DD`);
  const dt = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
  if (endExclusive) dt.setUTCDate(dt.getUTCDate() + 1);
  return admin.firestore.Timestamp.fromDate(dt);
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function str(v) {
  return typeof v === "string" ? v.trim() : "";
}

function isNonEmpty(v) {
  return str(v).length > 0;
}

function makeProfileResolver(db) {
  const cache = new Map();

  async function load(delegateId, orgId, companyIdHint) {
    const key = `${orgId || ""}|${delegateId}`;
    if (cache.has(key)) return cache.get(key);
    const empty = {name: "", phone: "", companyName: "", photo: "", companyId: companyIdHint || ""};
    if (!delegateId) {
      cache.set(key, empty);
      return empty;
    }
    const picks = [];
    if (orgId && companyIdHint) {
      picks.push(
        db.collection("organizations").doc(orgId)
          .collection("companies").doc(companyIdHint)
          .collection("delegates").doc(delegateId).get(),
      );
    }
    picks.push(db.collection("users").doc(delegateId).get());
    picks.push(db.collection("delegates").doc(delegateId).get());
    const snaps = await Promise.all(picks);
    let data = null;
    let companyId = companyIdHint || "";
    for (const snap of snaps) {
      if (snap.exists) {
        data = snap.data() || {};
        companyId = companyId || str(data.companyUID) || str(data.companyId) || "";
        break;
      }
    }
    if (!data) {
      cache.set(key, empty);
      return empty;
    }
    let companyName = str(data.companyName) || str(data.company_name);
    if (!companyName && orgId && companyId) {
      try {
        const cSnap = await db.collection("organizations").doc(orgId)
          .collection("companies").doc(companyId).get();
        if (cSnap.exists) {
          const c = cSnap.data() || {};
          companyName = str(c.name) || str(c.companyName) || str(c.title);
        }
      } catch (_) {/* ignore */}
    }
    const resolved = {
      name: str(data.fullName) || str(data.delegateName) || str(data.userName) ||
        [str(data.firstName), str(data.lastName)].filter(Boolean).join(" "),
      phone: str(data.phoneNumber) || str(data.phone) || str(data.mobile),
      companyName,
      photo: str(data.personalPhotoURL) || str(data.personalPhotoUrl) ||
        str(data.photoURL) || str(data.imageUrl),
      companyId,
    };
    cache.set(key, resolved);
    return resolved;
  }
  return {load, cache};
}

function neededProfilePatch(data, profile) {
  const patch = {};
  if (!isNonEmpty(data.delegateName) && isNonEmpty(profile.name)) patch.delegateName = profile.name;
  if (!isNonEmpty(data.phoneNumber) && isNonEmpty(profile.phone)) patch.phoneNumber = profile.phone;
  if (!isNonEmpty(data.companyName) && isNonEmpty(profile.companyName)) patch.companyName = profile.companyName;
  if (!isNonEmpty(data.personalPhotoURL) && isNonEmpty(profile.photo)) patch.personalPhotoURL = profile.photo;
  return patch;
}

function stripOverwrite(data, patch) {
  const out = {...patch};
  for (const k of Object.keys(out)) {
    const cur = data[k];
    if (k === "checkOutTime" && cur instanceof admin.firestore.Timestamp) delete out[k];
    else if (k === "checkOutLocation" && cur) delete out[k];
    else if (typeof cur === "string" && cur.trim().length > 0) delete out[k];
    else if (isNonEmpty(cur) && k === "checkOutDocId") delete out[k];
  }
  return out;
}

/** Stream all docs of a type with equality-only pagination. */
async function* streamByType(db, collection, type, pageSize, orgFilter) {
  let query = db.collection(collection).where("type", "==", type);
  if (orgFilter) query = query.where("organizationId", "==", orgFilter);
  query = query.limit(pageSize);
  let lastDoc = null;
  let pages = 0;
  for (;;) {
    const pageQuery = lastDoc ? query.startAfter(lastDoc) : query;
    const snap = await pageQuery.get();
    pages += 1;
    if (snap.empty) return;
    for (const doc of snap.docs) yield doc;
    lastDoc = snap.docs[snap.docs.length - 1];
    if (pages % 20 === 0) {
      console.error(`stream type=${type} pages=${pages} last=${lastDoc.id}`);
    }
    if (snap.size < pageSize) return;
  }
}

function inDateRange(data, fromTs, toTs) {
  if (!fromTs && !toTs) return true;
  const ts = data.timestamp;
  if (!ts || !ts.toMillis) return false;
  if (fromTs && ts.toMillis() < fromTs.toMillis()) return false;
  if (toTs && ts.toMillis() >= toTs.toMillis()) return false;
  return true;
}

/**
 * Build checkout lookup maps for the whole collection (one pass).
 * byRelatedId: relatedCheckInId -> {id, timestamp, location}
 * byDelegate: delegateId -> array of outs (sorted by ts)
 */
async function loadCheckoutIndexes(db, collection, pageSize, orgFilter, fromTs, toTs) {
  const byRelatedId = new Map();
  const byDelegate = new Map();
  let scanned = 0;
  for await (const doc of streamByType(db, collection, "check_out", pageSize, orgFilter)) {
    const d = doc.data() || {};
    if (fromTs || toTs) {
      const toExpanded = toTs
        ? admin.firestore.Timestamp.fromMillis(toTs.toMillis() + 36 * 3600 * 1000)
        : null;
      if (!inDateRange(d, fromTs, toExpanded)) continue;
    }
    scanned += 1;
    const delegateId = str(d.delegateId) || str(d.userId);
    const related = str(d.relatedCheckInId);
    const entry = {
      id: doc.id,
      timestamp: d.timestamp || null,
      location: d.location || null,
      branchName: str(d.branchName),
      organizationId: str(d.organizationId),
    };
    if (related) byRelatedId.set(related, entry);
    if (delegateId) {
      if (!byDelegate.has(delegateId)) byDelegate.set(delegateId, []);
      byDelegate.get(delegateId).push(entry);
    }
  }
  for (const arr of byDelegate.values()) {
    arr.sort((a, b) => {
      const am = a.timestamp ? a.timestamp.toMillis() : 0;
      const bm = b.timestamp ? b.timestamp.toMillis() : 0;
      return am - bm;
    });
  }
  console.error(`checkout index: scanned=${scanned} related=${byRelatedId.size} delegates=${byDelegate.size}`);
  return {byRelatedId, byDelegate, scanned};
}

function findCheckout(checkInId, data, indexes) {
  const related = indexes.byRelatedId.get(checkInId);
  if (related) return related;
  const delegateId = str(data.delegateId) || str(data.userId);
  const inTs = data.timestamp;
  if (!delegateId || !inTs) return null;
  const outs = indexes.byDelegate.get(delegateId) || [];
  const start = inTs.toMillis();
  const end = start + 36 * 3600 * 1000;
  const branch = str(data.branchName);
  let best = null;
  for (const o of outs) {
    if (!o.timestamp) continue;
    const m = o.timestamp.toMillis();
    if (m < start || m >= end) continue;
    if (branch && o.branchName && o.branchName !== branch) continue;
    best = o;
    break; // earliest after check-in
  }
  return best;
}

function neededCheckoutPatch(data, out) {
  if (!out) return {};
  const patch = {};
  if (!(data.checkOutTime instanceof admin.firestore.Timestamp) && out.timestamp) {
    patch.checkOutTime = out.timestamp;
  }
  if (!isNonEmpty(data.checkOutDocId)) patch.checkOutDocId = out.id;
  if (!data.checkOutLocation && out.location) patch.checkOutLocation = out.location;
  return patch;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const emulator = process.env.FIRESTORE_EMULATOR_HOST || "";

  if (opts.collection !== "attendance_logs") {
    console.error(`Refusing collection=${opts.collection} — only attendance_logs allowed.`);
    process.exit(2);
  }
  if (opts.apply && !emulator && !opts.allowProd) {
    console.error("Refusing --apply without emulator unless --i-understand-prod.");
    process.exit(2);
  }
  if (emulator && opts.allowProd) {
    console.error("Conflicting: emulator + --i-understand-prod.");
    process.exit(2);
  }

  if (admin.apps.length === 0) {
    admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "practice-firebase-72df1"});
  }
  const db = admin.firestore();
  db.settings({ignoreUndefinedProperties: true});

  const fromTs = parseDay(opts.from, false);
  const toTs = parseDay(opts.to, true);
  if ((opts.from && !opts.to) || (!opts.from && opts.to)) {
    throw new Error("Provide both --from and --to, or neither.");
  }

  const report = {
    startedAt: new Date().toISOString(),
    mode: opts.apply ? "apply" : "dry-run",
    emulator: emulator || null,
    projectId: process.env.GCLOUD_PROJECT || "practice-firebase-72df1",
    org: opts.org,
    from: opts.from,
    to: opts.to,
    collection: opts.collection,
    scanned: 0,
    checkIns: 0,
    checkOutsIndexed: 0,
    wouldUpdate: 0,
    updated: 0,
    skippedComplete: 0,
    profileFieldsStamped: 0,
    checkoutFieldsStamped: 0,
    fieldCounts: {
      delegateName: 0, phoneNumber: 0, companyName: 0, personalPhotoURL: 0,
      checkOutTime: 0, checkOutDocId: 0, checkOutLocation: 0,
    },
    orgs: {},
    minTimestamp: null,
    maxTimestamp: null,
    abortedOverLimit: false,
    errors: [],
    sampleUpdates: [],
    estimatedWrites: 0,
    estimatedCostUsd: 0,
    backupPath: opts.backup || null,
    backupDocs: 0,
  };

  console.error("Indexing check_out docs (read-only)…");
  const indexes = await loadCheckoutIndexes(
    db, opts.collection, opts.pageSize, opts.org, fromTs, toTs,
  );
  report.checkOutsIndexed = indexes.scanned;

  const resolver = makeProfileResolver(db);
  const backupDocs = [];
  let aborted = false;
  let batch = db.batch();
  let pending = 0;
  let writesCommitted = 0;

  async function flush() {
    if (!opts.apply || pending === 0) {
      pending = 0;
      batch = db.batch();
      return;
    }
    await batch.commit();
    writesCommitted += pending;
    console.error(`committed batch writes=${pending} total=${writesCommitted}`);
    pending = 0;
    batch = db.batch();
    if (opts.rateMs > 0) await sleep(opts.rateMs);
  }

  console.error("Scanning check_in docs…");
  for await (const doc of streamByType(db, opts.collection, "check_in", opts.pageSize, opts.org)) {
    report.scanned += 1;
    const data = doc.data() || {};
    if (data.type !== "check_in") continue;
    if (!inDateRange(data, fromTs, toTs)) continue;
    report.checkIns += 1;

    const orgId = str(data.organizationId) || str(data.organizationUID) || opts.org || "";
    const companyId = str(data.companyId) || str(data.companyUID);
    const delegateId = str(data.delegateId) || str(data.userId);

    let profilePatch = {};
    try {
      const profile = await resolver.load(delegateId, orgId, companyId);
      profilePatch = neededProfilePatch(data, profile);
    } catch (err) {
      report.errors.push({id: doc.id, stage: "profile", message: String(err.message || err)});
    }

    let checkoutPatch = {};
    const needsCheckout =
      !(data.checkOutTime instanceof admin.firestore.Timestamp) ||
      !isNonEmpty(data.checkOutDocId) ||
      !data.checkOutLocation;
    if (needsCheckout) {
      try {
        const out = findCheckout(doc.id, data, indexes);
        checkoutPatch = neededCheckoutPatch(data, out);
      } catch (err) {
        report.errors.push({id: doc.id, stage: "checkout", message: String(err.message || err)});
      }
    }

    let patch = stripOverwrite(data, {...profilePatch, ...checkoutPatch});
    if (Object.keys(patch).length === 0) {
      report.skippedComplete += 1;
      continue;
    }

    report.wouldUpdate += 1;
    report.profileFieldsStamped += Object.keys(profilePatch).length;
    report.checkoutFieldsStamped += Object.keys(checkoutPatch).length;
    for (const k of Object.keys(patch)) {
      if (report.fieldCounts[k] != null) report.fieldCounts[k] += 1;
    }
    if (orgId) report.orgs[orgId] = (report.orgs[orgId] || 0) + 1;
    if (data.timestamp && data.timestamp.toDate) {
      const iso = data.timestamp.toDate().toISOString();
      if (!report.minTimestamp || iso < report.minTimestamp) report.minTimestamp = iso;
      if (!report.maxTimestamp || iso > report.maxTimestamp) report.maxTimestamp = iso;
    }
    if (report.sampleUpdates.length < 25) {
      report.sampleUpdates.push({id: doc.id, fields: Object.keys(patch), orgId});
    }
    if (opts.backup) {
      // Serialize Timestamps for JSON backup
      const before = JSON.parse(JSON.stringify(data, (k, v) => {
        if (v && typeof v === "object" && typeof v.toDate === "function") {
          return {__timestamp: v.toDate().toISOString()};
        }
        return v;
      }));
      const wouldPatch = JSON.parse(JSON.stringify(patch, (k, v) => {
        if (v && typeof v === "object" && typeof v.toDate === "function") {
          return {__timestamp: v.toDate().toISOString()};
        }
        return v;
      }));
      backupDocs.push({id: doc.id, path: doc.ref.path, before, wouldPatch});
    }

    if (report.wouldUpdate > opts.maxUpdates) {
      report.abortedOverLimit = true;
      aborted = true;
      console.error(`ABORT: wouldUpdate > max-updates=${opts.maxUpdates}`);
      break;
    }

    if (opts.apply) {
      batch.update(doc.ref, patch);
      pending += 1;
      report.updated += 1;
      if (pending >= opts.batchSize) await flush();
    }

    if (report.checkIns % 1000 === 0) {
      console.error(
        `progress checkIns=${report.checkIns} wouldUpdate=${report.wouldUpdate} skipped=${report.skippedComplete}`,
      );
    }
  }

  if (!aborted) await flush();
  else if (opts.apply && pending > 0) {
    console.error(`Discarding uncommitted batch after abort (${pending}).`);
    pending = 0;
  }

  if (opts.backup) {
    const payload = {
      exportedAt: new Date().toISOString(),
      collection: opts.collection,
      mode: report.mode,
      count: backupDocs.length,
      docs: backupDocs,
    };
    fs.mkdirSync(path.dirname(opts.backup), {recursive: true});
    fs.writeFileSync(opts.backup, JSON.stringify(payload));
    report.backupDocs = backupDocs.length;
    console.error(`Backup written: ${opts.backup} (${backupDocs.length} docs)`);
  }

  report.estimatedWrites = report.wouldUpdate;
  report.estimatedCostUsd = Number(((report.wouldUpdate / 100000) * 0.18).toFixed(6));
  report.writesCommitted = writesCommitted;
  report.finishedAt = new Date().toISOString();
  report.profilesCached = resolver.cache.size;
  report.orgCount = Object.keys(report.orgs).length;

  const json = JSON.stringify(report, null, 2);
  fs.writeFileSync(opts.report, json);
  console.log(json);
  console.log(`\nReport written to ${opts.report}`);
  if (report.abortedOverLimit) process.exit(3);
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = {
  parseArgs,
  neededProfilePatch,
  neededCheckoutPatch,
  stripOverwrite,
  makeProfileResolver,
};
