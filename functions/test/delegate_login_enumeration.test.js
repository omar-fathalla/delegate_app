// TAS-29: an unknown phone and a wrong national ID look the same, and the
// login callable is limited per caller IP.
const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../src/delegate_login.ts"), "utf8");

test("delegateLoginV2 never returns a not_found reason", () => {
  assert.doesNotMatch(src, /reason:\s*"not_found"/);
  assert.match(src, /decision\.outcome === "not_found" \|\| decision\.outcome === "bad_credentials"/);
});

test("delegateLoginV2 checks the caller IP window before handling the login", () => {
  const call = src.indexOf("enforceLoginIpWindow(callerIp(");
  const handle = src.indexOf("return await handleDelegateLogin(data)");
  assert.ok(call >= 0 && handle > call);
});
