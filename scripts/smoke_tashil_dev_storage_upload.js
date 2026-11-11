#!/usr/bin/env node
/**
 * Live tashil-dev smoke: sign in as a fake staff user and upload a tiny
 * file under delegate_documents/{newFolder}/... then delete it.
 *
 * Proves Cloud Storage rules stay within the 2 unique Firestore-document
 * access limit (the emulator does not enforce this).
 *
 * Usage:
 *   TASHIL_DEV_ACCOUNTS_FILE=/path/to/accounts.txt \
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

async function main() {
  if (process.env.FIREBASE_PROJECT && process.env.FIREBASE_PROJECT !== PROJECT_ID) {
    fail(`refusing project ${process.env.FIREBASE_PROJECT}`);
  }
  if (FORBIDDEN.has(String(process.env.FIREBASE_PROJECT || "").toLowerCase())) {
    fail("refusing prod");
  }

  const key = apiKeyFromRepo();
  const file = process.env.TASHIL_DEV_ACCOUNTS_FILE;
  let email = process.env.TASHIL_DEV_STAFF_EMAIL || "";
  let password = process.env.TASHIL_DEV_STAFF_PASSWORD || "";
  let role = process.env.TASHIL_DEV_STAFF_ROLE || "";
  if (file) {
    if (!existsSync(file)) fail(`accounts file not found`);
    const accounts = parseAccounts(readFileSync(file, "utf8"));
    if (!accounts.length) fail("no email/password accounts in file");
    const staff = pickStaff(accounts);
    email = email || staff.email;
    password = password || staff.password;
    role = role || staff.role || "";
  }
  if (!email || !password) {
    fail("set TASHIL_DEV_ACCOUNTS_FILE or TASHIL_DEV_STAFF_EMAIL + TASHIL_DEV_STAFF_PASSWORD");
  }

  const signIn = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${encodeURIComponent(key)}`,
    {email, password, returnSecureToken: true},
    {"X-Goog-User-Project": PROJECT_ID},
  );
  if (!signIn.ok || !signIn.json.idToken) {
    const code = signIn.json?.error?.message || `http ${signIn.status}`;
    fail(`sign-in failed: ${code}`);
  }
  const idToken = signIn.json.idToken;
  const uid = signIn.json.localId || "(unknown)";
  console.log(`signed in as ${email} uid=${uid} role=${role || "(from file)"} project=${PROJECT_ID}`);

  const folder = `smoke_storage_${Date.now()}`;
  const objectPath = `delegate_documents/${folder}/staff_upload.txt`;
  const uploadUrl = `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o?name=${encodeURIComponent(objectPath)}`;
  const body = Buffer.from("tashil-dev storage smoke\n", "utf8");
  const uploadRes = await fetch(uploadUrl, {
    method: "POST",
    headers: {
      Authorization: `Firebase ${idToken}`,
      "Content-Type": "text/plain; charset=utf-8",
    },
    body,
  });
  const uploadText = await uploadRes.text();
  if (!uploadRes.ok) {
    fail(`upload unauthorized or failed (http ${uploadRes.status})`, uploadText);
  }
  console.log(`upload ok: ${objectPath} http ${uploadRes.status}`);

  const objectUrl = `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(objectPath)}`;
  const delRes = await fetch(objectUrl, {
    method: "DELETE",
    headers: {Authorization: `Firebase ${idToken}`},
  });
  if (!delRes.ok) {
    const t = await delRes.text();
    fail(`upload succeeded but delete failed (http ${delRes.status})`, t);
  }
  console.log(`delete ok: ${objectPath}`);
  console.log("PASS tashil-dev storage upload smoke");
}

main().catch((err) => fail(err && err.message ? err.message : String(err)));
