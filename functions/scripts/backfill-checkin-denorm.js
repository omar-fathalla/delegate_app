/**
 * Backfill denormalized fields onto attendance_logs check_in docs.
 *
 * Stamps (idempotent — skips fields already present):
 *   delegateName, phoneNumber, companyName, personalPhotoURL
 *   checkOutTime, checkOutDocId, checkOutLocation  (from matching check_out)
 *
 * Default is DRY-RUN (no writes). Never point at production unless an operator
 * explicitly passes --apply after reviewing the report. Emulator-first.
 *
 * Usage (from functions/):
 *   # Emulator (required for tests):
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
 *     node scripts/backfill-checkin-denorm.js \
 *       --org PiioBFgxaHAeuRdjlDgj \
 *       --from 2026-10-01 --to 2026-10-28
 *
 *   # Apply on emulator only:
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
 *     node scripts/backfill-checkin-denorm.js --apply --org ... --from ... --to ...
 *
 * Flags:
 *   --apply              Commit writes (default: dry-run)
 *   --org <id>           Restrict to organizationId
 *   --from YYYY-MM-DD    Inclusive start (UTC day)
 *   --to YYYY-MM-DD      Exclusive end (UTC day) — required with --from
 *   --collection <name>  Default attendance_logs
 *   --batch-size <n>     Writes per commit (default 200)
 *   --rate-ms <n>        Sleep between batches (default 250)
 *   --report <path>      Write JSON report (default stdout + ./backfill-report.json)
 *   --page-size <n>      Query page size (default 400)
 *
 * Safety: refuses --apply when FIRESTORE_EMULATOR_HOST is unset unless
 * --i-understand-prod is also passed (still not used by our workflow).
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
    pageSize: 400,
    allowProd: false,
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
  const y = Number(m[1]);
  const mo = Number(m[2]) - 1;
  const d = Number(m[3]);
  const dt = new Date(Date.UTC(y, mo, d));
  if (endExclusive) dt.setUTCDate(dt.getUTCDate() + 1);
  return admin.firestore.Timestamp.fromDate(dt);
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function str(v) {
  if (typeof v !== "string") return "";
  return v.trim();
}

function isNonEmpty(v) {
  return str(v).length > 0;
}

/**
 * Resolve profile fields for a delegate. Cached per process.
 */
function makeProfileResolver(db) {
  const cache = new Map(); // delegateId -> {name, phone, companyName, photo, companyId}

  async function load(delegateId, orgId, companyIdHint) {
    const key = `${orgId || ""}|${delegateId}`;
    if (cache.has(key)) return cache.get(key);

    const empty = {
      name: "",
      phone: "",
      companyName: "",
      photo: "",
      companyId: companyIdHint || "",
    };
    if (!delegateId) {
      cache.set(key, empty);
      return empty;
    }

    const picks = [];
    if (orgId && companyIdHint) {
      picks.push(
        db
          .collection("organizations")
          .doc(orgId)
          .collection("companies")
          .doc(companyIdHint)
          .collection("delegates")
          .doc(delegateId)
          .get(),
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
        companyId =
          companyId ||
          str(data.companyUID) ||
          str(data.companyId) ||
          str(data.company_uid) ||
          "";
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
        const cSnap = await db
          .collection("organizations")
          .doc(orgId)
          .collection("companies")
          .doc(companyId)
          .get();
        if (cSnap.exists) {
          const c = cSnap.data() || {};
          companyName = str(c.name) || str(c.companyName) || str(c.title);
        }
      } catch (_) {
        /* ignore */
      }
    }

    const resolved = {
      name:
        str(data.fullName) ||
        str(data.delegateName) ||
        str(data.userName) ||
        [str(data.firstName), str(data.lastName)].filter(Boolean).join(" "),
      phone: str(data.phoneNumber) || str(data.phone) || str(data.mobile),
      companyName,
      photo:
        str(data.personalPhotoURL) ||
        str(data.personalPhotoUrl) ||
        str(data.photoURL) ||
        str(data.imageUrl),
      companyId,
    };
    cache.set(key, resolved);
    return resolved;
  }

  return {load, cache};
}

/**
 * Find the best matching check_out for a check_in.
 * Prefer relatedCheckInId reverse lookup via querying outs for the delegate
 * in a window after check-in.
 */
async function findMatchingCheckOut(db, collection, checkIn) {
  const data = checkIn.data() || {};
  const delegateId = str(data.delegateId) || str(data.userId);
  const orgId = str(data.organizationId) || str(data.organizationUID);
  const inTs = data.timestamp;
  if (!delegateId || !inTs) return null;

  // Window: from check-in to +36h (covers overnight shifts)
  const start = inTs;
  const endDate = inTs.toDate();
  endDate.setHours(endDate.getHours() + 36);
  const end = admin.firestore.Timestamp.fromDate(endDate);

  let q = db
    .collection(collection)
    .where("type", "==", "check_out")
    .where("delegateId", "==", delegateId)
    .where("timestamp", ">=", start)
    .where("timestamp", "<", end)
    .orderBy("timestamp", "asc")
    .limit(10);

  if (orgId) q = q.where("organizationId", "==", orgId);

  let snap;
  try {
    snap = await q.get();
  } catch (err) {
    // Fallback without orderBy if composite index missing on emulator
    let q2 = db
      .collection(collection)
      .where("type", "==", "check_out")
      .where("delegateId", "==", delegateId)
      .limit(25);
    if (orgId) q2 = q2.where("organizationId", "==", orgId);
    snap = await q2.get();
  }

  const branch = str(data.branchName);
  let best = null;
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    const ts = d.timestamp;
    if (!ts || ts.toMillis() < inTs.toMillis() || ts.toMillis() >= end.toMillis()) {
      continue;
    }
    if (str(d.relatedCheckInId) === checkIn.id) {
      return doc;
    }
    if (branch && str(d.branchName) && str(d.branchName) !== branch) continue;
    if (!best) best = doc;
  }
  return best;
}

function neededProfilePatch(data, profile) {
  const patch = {};
  if (!isNonEmpty(data.delegateName) && isNonEmpty(profile.name)) {
    patch.delegateName = profile.name;
  }
  if (!isNonEmpty(data.phoneNumber) && isNonEmpty(profile.phone)) {
    patch.phoneNumber = profile.phone;
  }
  if (!isNonEmpty(data.companyName) && isNonEmpty(profile.companyName)) {
    patch.companyName = profile.companyName;
  }
  if (!isNonEmpty(data.personalPhotoURL) && isNonEmpty(profile.photo)) {
    patch.personalPhotoURL = profile.photo;
  }
  return patch;
}

function neededCheckoutPatch(data, outDoc) {
  if (!outDoc) return {};
  const out = outDoc.data() || {};
  const patch = {};
  if (!(data.checkOutTime instanceof admin.firestore.Timestamp) && out.timestamp) {
    patch.checkOutTime = out.timestamp;
  }
  if (!isNonEmpty(data.checkOutDocId)) {
    patch.checkOutDocId = outDoc.id;
  }
  if (!data.checkOutLocation && out.location) {
    patch.checkOutLocation = out.location;
  }
  return patch;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const emulator = process.env.FIRESTORE_EMULATOR_HOST || "";

  if (opts.apply && !emulator && !opts.allowProd) {
    console.error(
      "Refusing --apply without FIRESTORE_EMULATOR_HOST. " +
        "Pass --i-understand-prod only for an intentional production run.",
    );
    process.exit(2);
  }

  if (admin.apps.length === 0) {
    admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "practice-firebase-72df1"});
  }
  const db = admin.firestore();
  db.settings({ignoreUndefinedProperties: true});

  const fromTs = parseDay(opts.from, false);
  const toTs = parseDay(opts.to, true); // exclusive end of --to day
  if ((opts.from && !opts.to) || (!opts.from && opts.to)) {
    throw new Error("Provide both --from and --to, or neither.");
  }

  const report = {
    startedAt: new Date().toISOString(),
    mode: opts.apply ? "apply" : "dry-run",
    emulator: emulator || null,
    org: opts.org,
    from: opts.from,
    to: opts.to,
    collection: opts.collection,
    scanned: 0,
    checkIns: 0,
    wouldUpdate: 0,
    updated: 0,
    skippedComplete: 0,
    profileFieldsStamped: 0,
    checkoutFieldsStamped: 0,
    errors: [],
    sampleUpdates: [],
    estimatedWrites: 0,
    estimatedCostUsd: 0,
  };

  const resolver = makeProfileResolver(db);

  let query = db.collection(opts.collection).where("type", "==", "check_in");
  if (opts.org) query = query.where("organizationId", "==", opts.org);
  if (fromTs) query = query.where("timestamp", ">=", fromTs);
  if (toTs) query = query.where("timestamp", "<", toTs);
  query = query.orderBy("timestamp", "asc").limit(opts.pageSize);

  let lastDoc = null;
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
    pending = 0;
    batch = db.batch();
    if (opts.rateMs > 0) await sleep(opts.rateMs);
  }

  for (;;) {
    let pageQuery = query;
    if (lastDoc) pageQuery = query.startAfter(lastDoc);
    let snap;
    try {
      snap = await pageQuery.get();
    } catch (err) {
      // Emulator / missing composite: fall back to broader scan + filter
      console.warn("Paged query failed, falling back:", err.message);
      let fallback = db.collection(opts.collection).where("type", "==", "check_in");
      if (opts.org) fallback = fallback.where("organizationId", "==", opts.org);
      snap = await fallback.limit(opts.pageSize).get();
      // one-shot fallback
      lastDoc = "DONE";
    }

    if (snap.empty) break;

    for (const doc of snap.docs) {
      report.scanned += 1;
      const data = doc.data() || {};
      if (data.type !== "check_in") continue;
      if (fromTs && data.timestamp && data.timestamp.toMillis() < fromTs.toMillis()) continue;
      if (toTs && data.timestamp && data.timestamp.toMillis() >= toTs.toMillis()) continue;
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
          const outDoc = await findMatchingCheckOut(db, opts.collection, doc);
          checkoutPatch = neededCheckoutPatch(data, outDoc);
        } catch (err) {
          report.errors.push({id: doc.id, stage: "checkout", message: String(err.message || err)});
        }
      }

      const patch = {...profilePatch, ...checkoutPatch};
      if (Object.keys(patch).length === 0) {
        report.skippedComplete += 1;
        continue;
      }

      report.wouldUpdate += 1;
      report.profileFieldsStamped += Object.keys(profilePatch).length;
      report.checkoutFieldsStamped += Object.keys(checkoutPatch).length;
      if (report.sampleUpdates.length < 25) {
        report.sampleUpdates.push({id: doc.id, fields: Object.keys(patch)});
      }

      if (opts.apply) {
        batch.update(doc.ref, patch);
        pending += 1;
        report.updated += 1;
        if (pending >= opts.batchSize) await flush();
      }
    }

    if (lastDoc === "DONE") break;
    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.size < opts.pageSize) break;
  }

  await flush();

  // Cost estimate: Firestore billed writes ~$0.18 / 100k (approx; us-central1)
  report.estimatedWrites = report.wouldUpdate;
  report.estimatedCostUsd = Number(((report.wouldUpdate / 100000) * 0.18).toFixed(6));
  report.writesCommitted = writesCommitted;
  report.finishedAt = new Date().toISOString();
  report.profilesCached = resolver.cache.size;

  const json = JSON.stringify(report, null, 2);
  fs.writeFileSync(opts.report, json);
  console.log(json);
  console.log(`\nReport written to ${opts.report}`);
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
  makeProfileResolver,
  findMatchingCheckOut,
};
