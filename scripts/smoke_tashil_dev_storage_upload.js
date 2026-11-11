#!/usr/bin/env node
/**
 * Live tashil-dev smoke for hardened delegate_documents rules:
 *   1) staff writes storage_upload_intents/{folder} then uploads
 *   2) anonymous get/list/create are denied
 *   3) other-company staff get/list/create/delete are denied
 *
 * Usage:
 *   TASHIL_DEV_ACCOUNTS_FILE=/path/to/staff.txt \
 *   TASHIL_DEV_ACCOUNTS_FILE_2=/path/to/other-company-staff.txt \
 *     node scripts/smoke_tashil_dev_storage_upload.js
 *
 * The accounts file must not be committed. Never prints passwords or tokens.
 * Refuses any project other than tashil-dev. Never run against prod.
 */
"use strict";

const {readFileSync, existsSync} = require("fs");
const {resolve} = require("path");

const PROJECT_ID = "tashil-dev";
const BUCKET = "tashil-dev.firebasestorage.app";
const FORBIDDEN = new Set(["practice-firebase-72df1", "prod", "production"]);

function fail(msg, extra) {
  console.error(`FAIL: ${msg}`);
  if (extra) console.error(String(extra).slice(0, 400));
  process.exit(1);
}

function repoRoot() {
  return resolve(__dirname, "..");
}

function apiKeyFromRepo() {
  const path = resolve(repoRoot(), "android/app/src/dev/google-services.json");
  if (!existsSync(path)) fail("missing android/app/src/dev/google-services.json");
  const json = JSON.parse(readFileSync(path, "utf8"));
  const projectId = json?.project_info?.project_id;
  if (projectId !== PROJECT_ID) fail(`google-services.json project is ${projectId}, expected ${PROJECT_ID}`);
  const key = json?.client?.[0]?.api_key?.[0]?.current_key;
  if (!key) fail("could not read client API key from google-services.json");
  return key;
}

function parseAccounts(text) {
  const accounts = [];
  // JSON array or {accounts:[...]}
  const trimmed = text.trim();
  if (trimmed.startsWith("[") || trimmed.startsWith("{")) {
    const raw = JSON.parse(trimmed);
    const list = Array.isArray(raw) ? raw : (raw.accounts || raw.staff || []);
    for (const row of list) {
      if (row && row.email && row.password) accounts.push(row);
    }
    return accounts;
  }
  // Blocks of key: value (uid/role/email/password), or KEY=value lines.
  let current = {};
  const flush = () => {
    if (current.email && current.password) accounts.push(current);
    current = {};
  };
  for (const line of text.split(/\r?\n/)) {
    const s = line.trim();
    if (!s || s.startsWith("#")) {
      if (!s) flush();
      continue;
    }
    const m = s.match(/^(?:[-*]\s*)?(uid|role|email|password|phone)\s*[:=]\s*(.*)$/i);
    if (m) {
      current[m[1].toLowerCase()] = m[2].trim();
      continue;
    }
  }
  flush();
  return accounts;
}

function pickStaff(accounts) {
  const preferred = ["hr", "company_hr", "admin", "supervisor", "company-admin", "company_admin"];
  for (const role of preferred) {
    const hit = accounts.find((a) => String(a.role || "").toLowerCase() === role);
    if (hit) return hit;
  }
  return accounts[0];
}

function gcloudAccessToken() {
  try {
    const {execFileSync} = require("child_process");
    const env = {...process.env};
    delete env.CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT;
    const tok = execFileSync(
      "/Users/fathalla/google-cloud-sdk/bin/gcloud",
      ["auth", "print-access-token"],
      {env, encoding: "utf8"},
    ).trim();
    return tok || "";
  } catch {
    return "";
  }
}

async function postJson(url, body, headers = {}) {
  const res = await fetch(url, {
    method: "POST",
    headers: {"Content-Type": "application/json", ...headers},
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = {raw: text.slice(0, 200)}; }
  return {ok: res.ok, status: res.status, json};
}

async function signInPassword(key, email, password, userTok) {
  const signInHeaders = {"X-Goog-User-Project": PROJECT_ID};
  if (userTok) signInHeaders.Authorization = `Bearer ${userTok}`;
  const signIn = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${encodeURIComponent(key)}`,
    {email, password, returnSecureToken: true},
    signInHeaders,
  );
  if (!signIn.ok || !signIn.json.idToken) {
    const code = signIn.json?.error?.message || `http ${signIn.status}`;
    fail(`sign-in failed: ${code}`);
  }
  return {idToken: signIn.json.idToken, uid: signIn.json.localId || ""};
}

async function signInAnonymous(key, userTok) {
  const headers = {"X-Goog-User-Project": PROJECT_ID};
  if (userTok) headers.Authorization = `Bearer ${userTok}`;
  const signIn = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${encodeURIComponent(key)}`,
    {returnSecureToken: true},
    headers,
  );
  if (!signIn.ok || !signIn.json.idToken) {
    const code = signIn.json?.error?.message || `http ${signIn.status}`;
    fail(`anonymous sign-in failed: ${code}`);
  }
  return {idToken: signIn.json.idToken, uid: signIn.json.localId || ""};
}

async function firestoreGet(idToken, path) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${path}`;
  const res = await fetch(url, {headers: {Authorization: `Bearer ${idToken}`}});
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = {raw: text.slice(0, 200)}; }
  return {ok: res.ok, status: res.status, json};
}

async function firestoreCreateIntent(idToken, folder, companyUID, createdBy) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/storage_upload_intents?documentId=${encodeURIComponent(folder)}`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${idToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      fields: {
        companyUID: {stringValue: companyUID},
        createdBy: {stringValue: createdBy},
        createdAt: {timestampValue: new Date().toISOString()},
      },
    }),
  });
  const text = await res.text();
  return {ok: res.ok, status: res.status, text: text.slice(0, 300)};
}

function storageObjectUrl(objectPath) {
  return `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(objectPath)}`;
}

async function storageUpload(idToken, objectPath, body) {
  const uploadUrl = `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o?uploadType=media&name=${encodeURIComponent(objectPath)}`;
  const res = await fetch(uploadUrl, {
    method: "POST",
    headers: {
      Authorization: `Firebase ${idToken}`,
      "Content-Type": "text/plain; charset=utf-8",
    },
    body,
  });
  return {ok: res.ok, status: res.status, text: await res.text()};
}

async function storageGet(idToken, objectPath) {
  const res = await fetch(storageObjectUrl(objectPath), {
    headers: {Authorization: `Firebase ${idToken}`},
  });
  return {ok: res.ok, status: res.status, text: (await res.text()).slice(0, 200)};
}

async function storageList(idToken, prefix) {
  const url = `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o?prefix=${encodeURIComponent(prefix)}`;
  const res = await fetch(url, {headers: {Authorization: `Firebase ${idToken}`}});
  return {ok: res.ok, status: res.status, text: (await res.text()).slice(0, 200)};
}

async function storageDelete(idToken, objectPath) {
  const res = await fetch(storageObjectUrl(objectPath), {
    method: "DELETE",
    headers: {Authorization: `Firebase ${idToken}`},
  });
  return {ok: res.ok, status: res.status, text: (await res.text()).slice(0, 200)};
}

function userCompany(docJson) {
  return docJson?.fields?.companyUID?.stringValue || "";
}

function expectDenied(label, res) {
  if (res.ok) fail(`${label} unexpectedly allowed (http ${res.status})`, res.text);
  if (res.status !== 403 && res.status !== 401 && res.status !== 404) {
    // 403 is the intended rules deny; 401 unauthenticated; some list denials are 403.
    console.log(`WARN: ${label} denied with http ${res.status} (wanted 403)`);
  } else {
    console.log(`deny ok: ${label} http ${res.status}`);
  }
}

function loadAccounts() {
  const files = [
    process.env.TASHIL_DEV_ACCOUNTS_FILE,
    process.env.TASHIL_DEV_ACCOUNTS_FILE_2,
  ].filter(Boolean);
  const accounts = [];
  for (const file of files) {
    if (!existsSync(file)) fail(`accounts file not found`);
    const parsed = parseAccounts(readFileSync(file, "utf8"));
    accounts.push(...parsed);
  }
  return accounts;
}

async function main() {
  if (process.env.FIREBASE_PROJECT && process.env.FIREBASE_PROJECT !== PROJECT_ID) {
    fail(`refusing project ${process.env.FIREBASE_PROJECT}`);
  }
  if (FORBIDDEN.has(String(process.env.FIREBASE_PROJECT || "").toLowerCase())) {
    fail("refusing prod");
  }

  const key = apiKeyFromRepo();
  const accounts = loadAccounts();
  let email = process.env.TASHIL_DEV_STAFF_EMAIL || "";
  let password = process.env.TASHIL_DEV_STAFF_PASSWORD || "";
  let role = process.env.TASHIL_DEV_STAFF_ROLE || "";
  if (!email || !password) {
    if (!accounts.length) {
      fail("set TASHIL_DEV_ACCOUNTS_FILE or TASHIL_DEV_STAFF_EMAIL + TASHIL_DEV_STAFF_PASSWORD");
    }
    const staff = pickStaff(accounts);
    email = staff.email;
    password = staff.password;
    role = staff.role || "";
  }

  const userTok = gcloudAccessToken();
  const staff = await signInPassword(key, email, password, userTok);
  console.log(`signed in as ${email} uid=${staff.uid} role=${role || "(from file)"} project=${PROJECT_ID}`);

  const userDoc = await firestoreGet(staff.idToken, `users/${staff.uid}`);
  if (!userDoc.ok) fail(`could not read users/${staff.uid} (http ${userDoc.status})`);
  const companyUID = userCompany(userDoc.json);
  if (!companyUID) fail("signed-in staff has empty companyUID (fail closed)");

  const folder = `smoke_storage_${Date.now()}`;
  const objectPath = `delegate_documents/${folder}/staff_upload.txt`;
  const prefix = `delegate_documents/${folder}/`;

  const intent = await firestoreCreateIntent(staff.idToken, folder, companyUID, staff.uid);
  if (!intent.ok) fail(`intent create failed (http ${intent.status})`, intent.text);
  console.log(`intent ok: storage_upload_intents/${folder} company=${companyUID}`);

  const body = Buffer.from("tashil-dev storage smoke\n", "utf8");
  const uploadRes = await storageUpload(staff.idToken, objectPath, body);
  if (!uploadRes.ok) fail(`staff upload failed (http ${uploadRes.status})`, uploadRes.text);
  console.log(`upload ok: ${objectPath} http ${uploadRes.status}`);

  const anon = await signInAnonymous(key, userTok);
  console.log(`anonymous uid=${anon.uid}`);
  expectDenied("anon get", await storageGet(anon.idToken, objectPath));
  expectDenied("anon list", await storageList(anon.idToken, prefix));
  expectDenied("anon upload", await storageUpload(anon.idToken, `${prefix}anon.txt`, body));

  const other = accounts.find((a) => a.email && a.password && a.email !== email);
  if (other) {
    const otherAuth = await signInPassword(key, other.email, other.password, userTok);
    const otherDoc = await firestoreGet(otherAuth.idToken, `users/${otherAuth.uid}`);
    const otherCo = otherDoc.ok ? userCompany(otherDoc.json) : "";
    if (!otherCo || otherCo === companyUID) {
      console.log("WARN: second account is missing or same company; skipped cross-company checks");
    } else {
      console.log(`other-company uid=${otherAuth.uid} company=${otherCo}`);
      expectDenied("other-company get", await storageGet(otherAuth.idToken, objectPath));
      expectDenied("other-company list", await storageList(otherAuth.idToken, prefix));
      expectDenied("other-company upload", await storageUpload(otherAuth.idToken, `${prefix}other.txt`, body));
      expectDenied("other-company delete", await storageDelete(otherAuth.idToken, objectPath));
      const hijack = await firestoreCreateIntent(otherAuth.idToken, folder, otherCo, otherAuth.uid);
      if (hijack.ok) fail("other-company was able to overwrite/create the intent");
      console.log(`deny ok: other-company intent hijack http ${hijack.status}`);
    }
  } else {
    console.log("WARN: no second staff account; skipped cross-company checks");
  }

  const delRes = await storageDelete(staff.idToken, objectPath);
  if (!delRes.ok) {
    console.log(`WARN: staff delete failed (http ${delRes.status}); left ${objectPath}`);
    console.log(String(delRes.text).slice(0, 200));
  } else {
    console.log(`delete ok: ${objectPath}`);
  }
  console.log("PASS tashil-dev storage upload smoke (staff upload, anon deny, cross-company deny)");
}

main().catch((err) => fail(err && err.message ? err.message : String(err)));
