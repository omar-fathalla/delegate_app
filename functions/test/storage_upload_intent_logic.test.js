"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/storage_upload_intent_logic");

test("new registration is reserved for the caller's company", () => {
  const d = L.decideEnsureIntent({
    authenticated: true, anonymous: false, role: "hr",
    callerCompany: "co_a", requestedCompany: "co_a",
    ownerCompany: null, lockedByIntent: false,
  });
  assert.deepEqual(d, {ok: true, action: "create", companyUID: "co_a"});
});

test("staff cannot plant another company's label on a new folder", () => {
  const d = L.decideEnsureIntent({
    authenticated: true, anonymous: false, role: "hr",
    callerCompany: "co_b", requestedCompany: "co_a",
    ownerCompany: null, lockedByIntent: false,
  });
  assert.equal(d.ok, false);
  assert.equal(d.reason, "company_mismatch");
});

test("staff cannot claim an existing other-company delegate folder", () => {
  const d = L.decideEnsureIntent({
    authenticated: true, anonymous: false, role: "hr",
    callerCompany: "co_b", requestedCompany: "co_b",
    ownerCompany: "co_a", lockedByIntent: false,
  });
  assert.equal(d.ok, false);
  assert.equal(d.reason, "folder_other_company");
});

test("same-company staff create an intent for an existing owner with no intent yet", () => {
  const d = L.decideEnsureIntent({
    authenticated: true, anonymous: false, role: "supervisor",
    callerCompany: "co_a", requestedCompany: "co_a",
    ownerCompany: "co_a", lockedByIntent: false,
  });
  assert.deepEqual(d, {ok: true, action: "create", companyUID: "co_a"});
});

test("existing intent is reused and the company cannot be changed", () => {
  const d = L.decideEnsureIntent({
    authenticated: true, anonymous: false, role: "admin",
    callerCompany: "co_a", requestedCompany: "co_zzz",
    ownerCompany: "co_a", lockedByIntent: true,
  });
  assert.deepEqual(d, {ok: true, action: "reuse", companyUID: "co_a"});
});

test("anonymous and non-staff are rejected", () => {
  assert.equal(L.decideEnsureIntent({
    authenticated: true, anonymous: true, role: "hr",
    callerCompany: "co_a", requestedCompany: "co_a",
    ownerCompany: null, lockedByIntent: false,
  }).reason, "sign_in_required");
  assert.equal(L.decideEnsureIntent({
    authenticated: true, anonymous: false, role: "delegate",
    callerCompany: "co_a", requestedCompany: "co_a",
    ownerCompany: null, lockedByIntent: false,
  }).reason, "caller_not_staff");
  assert.equal(L.decideEnsureIntent({
    authenticated: true, anonymous: false, role: "accountant",
    callerCompany: "co_a", requestedCompany: "co_a",
    ownerCompany: null, lockedByIntent: false,
  }).reason, "caller_not_staff");
});

test("conflicting owner companies fail closed", () => {
  const r = L.resolveOwningCompany([
    {source: "delegate", companyUID: "co_a"},
    {source: "delegate", companyUID: "co_b"},
  ]);
  assert.equal(r.ok, false);
  assert.equal(r.reason, "company_conflict");
});

test("an existing intent locks the company", () => {
  const r = L.resolveOwningCompany([
    {source: "intent", companyUID: "co_a"},
    {source: "request", companyUID: "co_a"},
  ]);
  assert.deepEqual(r, {ok: true, companyUID: "co_a", lockedByIntent: true});
});

test("folder id must be a single path segment", () => {
  assert.equal(L.isValidFolderId("abc"), true);
  assert.equal(L.isValidFolderId("a/b"), false);
  assert.equal(L.isValidFolderId(""), false);
  assert.equal(L.isValidFolderId("."), false);
  assert.equal(L.isValidFolderId(".."), false);
});

test("inactive status strings are detected", () => {
  assert.equal(L.isInactiveStatus("inactive"), true);
  assert.equal(L.isInactiveStatus("disabled"), true);
  assert.equal(L.isInactiveStatus("active"), false);
  assert.equal(L.isInactiveStatus(""), false);
});
