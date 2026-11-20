/**
 * Interim prod hardening: firestore/interim-prod-hardening.rules
 * vs the deployed prod ruleset 44ad81d0 (test/rules/fixtures/prod-44ad81d0.rules).
 *
 * Emulator only (demo-* projects). Nothing here talks to a real project.
 * Every case runs against BOTH rulesets. The only allowed difference is an
 * unauthenticated request on users, attendance_logs (root + org-scoped),
 * leave_requests and delegate_tracking (+ breadcrumbs), which must now be denied.
 */
const {describe, test, before, after} = require("node:test");
const assert = require("node:assert");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment} = require("./_rules_testing");

const read = (p) => readFileSync(resolve(__dirname, p), "utf8");
const HARDENED = new Set(["users", "attendance_logs", "org_attendance_logs",
  "leave_requests", "delegate_tracking", "breadcrumbs"]);

const DOCS = {
  users: "users/u-admin",
  attendance_logs: "attendance_logs/a1",
  org_attendance_logs: "organizations/o1/attendance_logs/a1",
  leave_requests: "leave_requests/l1",
  delegate_tracking: "delegate_tracking/d1",
  breadcrumbs: "delegate_tracking/d1/breadcrumbs/b1",
  delegates_nested: "organizations/o1/companies/c1/delegates/d1",
  organizations: "organizations/o1",
  companies: "organizations/o1/companies/c1",
  branches: "branches/b1",
  invites: "invites/i1",
  penalties: "penalties/p1",
  notifications: "notifications/n1",
  device_unbind_requests: "device_unbind_requests/r1",
  security_audit_logs: "security_audit_logs/s1",
  monthly_collections: "monthly_collections/m1",
  user_wallets: "user_wallets/w1",
  attendance: "attendance/x1",
  tasks: "organizations/o1/tasks/t1",
  app_updates: "app_updates/v1",
  unknown_collection: "zzz_unknown/z1",
};

async function seed(env) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc("users/u-admin").set({role: "company-admin", organizationUID: "o1", companyUID: "c1"});
    for (const p of Object.values(DOCS)) {
      if (p !== "users/u-admin") await db.doc(p).set({organizationUID: "o1", companyUID: "c1", phoneNumber: "010"});
    }
  });
}

async function outcome(fn) {
  try { await fn(); return "allow"; } catch (e) { return "deny"; }
}

const CONTEXTS = {
  unauth: (env) => env.unauthenticatedContext(),
  anonymous: (env) => env.authenticatedContext("anon-1", {firebase: {sign_in_provider: "anonymous"}}),
  staff: (env) => env.authenticatedContext("u-admin"),
};

async function matrix(env) {
  const out = {};
  for (const [cName, mk] of Object.entries(CONTEXTS)) {
    const db = mk(env).firestore();
    for (const [name, p] of Object.entries(DOCS)) {
      const col = p.split("/").slice(0, -1).join("/");
      out[`${cName} get ${name}`] = await outcome(() => db.doc(p).get());
      out[`${cName} list ${name}`] = await outcome(() => db.collection(col).get());
      out[`${cName} update ${name}`] = await outcome(() => db.doc(p).set({touched: true}, {merge: true}));
    }
    out[`${cName} cg delegates`] = await outcome(() => db.collectionGroup("delegates").where("phoneNumber", "==", "010").get());
  }
  return out;
}

describe("interim prod hardening vs 44ad81d0", () => {
  let base; let hard; let resBase; let resHard;
  before(async () => {
    base = await initializeTestEnvironment({projectId: "demo-interim-base", firestore: {rules: read("fixtures/prod-44ad81d0.rules")}});
    hard = await initializeTestEnvironment({projectId: "demo-interim-hard", firestore: {rules: read("../../firestore/interim-prod-hardening.rules")}});
    await seed(base); await seed(hard);
    resBase = await matrix(base);
    await seed(base);
    resHard = await matrix(hard);
  });
  after(async () => { await base?.cleanup(); await hard?.cleanup(); });

  test("unauthenticated get/list/write on the hardened paths is denied", () => {
    for (const name of HARDENED) {
      for (const op of ["get", "list", "update"]) {
        assert.strictEqual(resHard[`unauth ${op} ${name}`], "deny", `unauth ${op} ${name}`);
      }
    }
    assert.strictEqual(resHard["unauth cg delegates"], "deny");
  });

  test("the 44ad81d0 baseline really was open on those paths (sanity)", () => {
    for (const name of HARDENED) assert.strictEqual(resBase[`unauth list ${name}`], "allow", name);
  });

  test("every other outcome is identical to 44ad81d0", () => {
    const diffs = [];
    for (const k of Object.keys(resBase)) {
      const [c, , name] = k.split(" ");
      const expectedChange = c === "unauth" && HARDENED.has(name);
      if (!expectedChange && resBase[k] !== resHard[k]) diffs.push(`${k}: ${resBase[k]} -> ${resHard[k]}`);
      if (expectedChange && resBase[k] === "allow") assert.strictEqual(resHard[k], "deny", k);
    }
    console.log(`compared ${Object.keys(resBase).length} cases; unexpected diffs: ${diffs.length}`);
    assert.deepStrictEqual(diffs, []);
  });

  test("anonymous and staff sessions keep access to the hardened paths", () => {
    for (const c of ["anonymous", "staff"]) {
      for (const name of HARDENED) {
        assert.strictEqual(resHard[`${c} get ${name}`], "allow", `${c} get ${name}`);
        assert.strictEqual(resHard[`${c} list ${name}`], "allow", `${c} list ${name}`);
      }
    }
  });
});
