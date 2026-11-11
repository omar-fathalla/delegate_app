const test = require("node:test");
const assert = require("node:assert/strict");
const {shouldSkipStamp} = require("../lib/delegate_source_logic");

test("shouldSkipStamp: already stamped", () => {
  assert.equal(shouldSkipStamp({delegateSource: "app"}), true);
  assert.equal(shouldSkipStamp({delegateSource: "web"}), true);
});

test("shouldSkipStamp: honour revert marker so --revert is not re-stamped", () => {
  assert.equal(shouldSkipStamp({delegateSourceRevertRunId: "dev-run-1"}), true);
  assert.equal(shouldSkipStamp({
    delegateSource: "",
    delegateSourceRevertRunId: "dev-run-1",
  }), true);
});

test("shouldSkipStamp: unstamped docs without a revert marker are stamped", () => {
  assert.equal(shouldSkipStamp({}), false);
  assert.equal(shouldSkipStamp({uid: "d1", registeredVia: "mobile_app"}), false);
});
