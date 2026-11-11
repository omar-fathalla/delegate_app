#!/usr/bin/env node
/**
 * Backfill storage_upload_intents on tashil-dev for every delegate uid
 * and remaining delegate_requests ids so same-company staff keep access
 * to web/legacy folders. Never overwrites an existing intent's company.
 * Multi-company conflicts are skipped and logged by folder id only (no PII).
 *
 * Usage:
 *   node scripts/backfill_tashil_dev_storage_intents.js
 *   DRY_RUN=1 node scripts/backfill_tashil_dev_storage_intents.js
 *
 * Refuses any project other than tashil-dev. Never run against prod.
 */
"use strict";

const {execFileSync} = require("child_process");

const PROJECT_ID = "tashil-dev";
const FORBIDDEN = new Set(["practice-firebase-72df1", "prod", "production"]);
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)`;
const DRY_RUN = process.env.DRY_RUN === "1" || process.env.DRY_RUN === "true";

function fail(msg, extra) {
  console.error(`FAIL: ${msg}`);
  if (extra) console.error(String(extra).slice(0, 400));
  process.exit(1);
}

function accessToken() {
  const env = {...process.env};
  delete env.CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT;
  try {
    const tok = execFileSync(
      "/Users/fathalla/google-cloud-sdk/bin/gcloud",
      ["auth", "print-access-token"],
      {env, encoding: "utf8"},
    ).trim();
    if (!tok) fail("empty gcloud access token");
    return tok;
  } catch (err) {
    fail("gcloud auth print-access-token failed", err && err.message);
  }
}

function headers(token) {
  return {
    Authorization: `Bearer ${token}`,
    "X-Goog-User-Project": PROJECT_ID,
    "Content-Type": "application/json",
  };
}

function strField(fields, key) {
  return (fields && fields[key] && fields[key].stringValue) || "";
}

function companyFromFieldsAndName(fields, name) {
  const fromData = strField(fields, "companyUID") || strField(fields, "companyId");
  if (fromData) return fromData;
  const parts = String(name || "").split("/");
  const i = parts.indexOf("companies");
  if (i >= 0 && parts[i + 1]) return parts[i + 1];
  return "";
}

function folderIdFromDelegate(fields, name) {
  const uid = strField(fields, "uid");
  if (uid) return uid;
  const parts = String(name || "").split("/");
  return parts[parts.length - 1] || "";
}

async function api(token, method, url, body) {
  const res = await fetch(url, {
    method,
    headers: headers(token),
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = {raw: text.slice(0, 300)}; }
  return {ok: res.ok, status: res.status, json, text};
}

async function listCollection(token, collection, pageToken) {
  const qs = new URLSearchParams({pageSize: "300"});
  if (pageToken) qs.set("pageToken", pageToken);
  const url = `${BASE}/documents/${collection}?${qs}`;
  const res = await api(token, "GET", url);
  if (!res.ok) fail(`list ${collection} failed (http ${res.status})`, res.text);
  return res.json;
}

async function listAll(token, collection) {
  const docs = [];
  let pageToken;
  do {
    const json = await listCollection(token, collection, pageToken);
    for (const doc of json.documents || []) docs.push(doc);
    pageToken = json.nextPageToken;
  } while (pageToken);
  return docs;
}

async function runQueryPage(token, structuredQuery) {
  const res = await api(token, "POST", `${BASE}/documents:runQuery`, {structuredQuery});
  if (!res.ok) fail(`runQuery failed (http ${res.status})`, res.text);
  return Array.isArray(res.json) ? res.json : [];
}

async function listDelegates(token) {
  const out = [];
  let cursor = null;
  for (;;) {
    const structuredQuery = {
      from: [{collectionId: "delegates", allDescendants: true}],
      select: {fields: [{fieldPath: "uid"}, {fieldPath: "companyUID"}, {fieldPath: "companyId"}]},
      limit: 300,
      orderBy: [{field: {fieldPath: "__name__"}, direction: "ASCENDING"}],
    };
    if (cursor) {
      structuredQuery.startAt = {values: [{referenceValue: cursor}], before: false};
    }
    const rows = await runQueryPage(token, structuredQuery);
    let last = null;
    let count = 0;
    for (const row of rows) {
      if (!row.document) continue;
      count += 1;
      last = row.document.name;
      out.push(row.document);
    }
    if (count < 300 || !last) break;
    if (last === cursor) break;
    cursor = last;
  }
  return out;
}

async function getIntent(token, folderId) {
  const url = `${BASE}/documents/storage_upload_intents/${encodeURIComponent(folderId)}`;
  const res = await api(token, "GET", url);
  if (res.status === 404) return null;
  if (!res.ok) fail(`get intent ${folderId} failed (http ${res.status})`, res.text);
  return res.json;
}

async function createIntent(token, folderId, companyUID) {
  if (DRY_RUN) return {ok: true, dryRun: true};
  const url = `${BASE}/documents/storage_upload_intents?documentId=${encodeURIComponent(folderId)}`;
  const res = await api(token, "POST", url, {
    fields: {
      companyUID: {stringValue: companyUID},
      createdBy: {stringValue: "backfill"},
      source: {stringValue: "backfill"},
      createdAt: {timestampValue: new Date().toISOString()},
    },
  });
  if (res.status === 409) return {ok: true, existed: true};
  if (!res.ok) return {ok: false, status: res.status, text: res.text};
  return {ok: true, created: true};
}

function collectTargets(delegates, requests) {
  const companies = new Map(); // folderId -> Set(company)
  const add = (folderId, company, source) => {
    const id = String(folderId || "").trim();
    const co = String(company || "").trim();
    if (!id || id.includes("/") || !co) return;
    if (!companies.has(id)) companies.set(id, {companies: new Set(), sources: new Set()});
    companies.get(id).companies.add(co);
    companies.get(id).sources.add(source);
  };
  for (const doc of delegates) {
    add(folderIdFromDelegate(doc.fields, doc.name), companyFromFieldsAndName(doc.fields, doc.name), "delegate");
  }
  for (const doc of requests) {
    const id = String(doc.name || "").split("/").pop() || "";
    add(id, companyFromFieldsAndName(doc.fields, doc.name), "request");
  }
  return companies;
}

async function main() {
  const forced = process.env.FIREBASE_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || PROJECT_ID;
  if (FORBIDDEN.has(String(forced).toLowerCase()) || forced !== PROJECT_ID) {
    fail(`refusing project ${forced}`);
  }
  const token = accessToken();
  console.log(`backfill start project=${PROJECT_ID} dryRun=${DRY_RUN ? "1" : "0"}`);

  const [delegates, requests, existing] = await Promise.all([
    listDelegates(token),
    listAll(token, "delegate_requests"),
    listAll(token, "storage_upload_intents"),
  ]);
  console.log(`scanned delegates=${delegates.length} requests=${requests.length} existingIntents=${existing.length}`);

  const existingById = new Map();
  for (const doc of existing) {
    const id = String(doc.name || "").split("/").pop() || "";
    existingById.set(id, strField(doc.fields, "companyUID") || strField(doc.fields, "companyId"));
  }

  const targets = collectTargets(delegates, requests);
  let created = 0;
  let reused = 0;
  let skippedConflict = 0;
  let skippedExistingMismatch = 0;
  let failed = 0;

  for (const [folderId, info] of targets) {
    if (info.companies.size !== 1) {
      skippedConflict += 1;
      console.log(`SKIP conflict folder=${folderId} companies=${info.companies.size}`);
      continue;
    }
    const companyUID = [...info.companies][0];
    const existingCo = existingById.get(folderId);
    if (existingCo) {
      if (existingCo !== companyUID) {
        skippedExistingMismatch += 1;
        console.log(`SKIP existing-mismatch folder=${folderId}`);
      } else {
        reused += 1;
      }
      continue;
    }
    const res = await createIntent(token, folderId, companyUID);
    if (!res.ok) {
      failed += 1;
      console.log(`FAIL create folder=${folderId} http=${res.status}`);
      continue;
    }
    created += 1;
  }

  console.log(
    `backfill done created=${created} alreadyPresent=${reused} ` +
    `conflictSkip=${skippedConflict} existingMismatchSkip=${skippedExistingMismatch} failed=${failed} dryRun=${DRY_RUN ? "1" : "0"}`,
  );
  if (failed) process.exit(1);
}

main().catch((err) => fail(err && err.message ? err.message : String(err)));
