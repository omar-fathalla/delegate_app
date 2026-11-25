// TAS-30: onTaskImageFinalize must not hard-code one project's bucket.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {test} = require("node:test");

const root = path.join(__dirname, "..");
const src = fs.readFileSync(path.join(root, "src/task_image_access.ts"), "utf8");

function env(file) {
  const out = {};
  for (const line of fs.readFileSync(path.join(root, file), "utf8").split("\n")) {
    const m = line.match(/^([A-Z_]+)=(.*)$/);
    if (m) out[m[1]] = m[2].trim();
  }
  return out;
}

test("trigger reads bucket and region from params", () => {
  assert.doesNotMatch(src, /bucket:\s*"/);
  assert.match(src, /bucket:\s*TASK_IMAGE_BUCKET/);
  assert.match(src, /region:\s*TASK_IMAGE_TRIGGER_REGION/);
});

test("each project's env points at its own default bucket", () => {
  const dev = env(".env.tashil-dev");
  assert.equal(dev.TASK_IMAGE_BUCKET, "tashil-dev.firebasestorage.app");
  assert.equal(dev.TASK_IMAGE_TRIGGER_REGION, "europe-west4");
  const prod = env(".env.practice-firebase-72df1");
  assert.equal(prod.TASK_IMAGE_BUCKET, "practice-firebase-72df1.firebasestorage.app");
  assert.equal(prod.TASK_IMAGE_TRIGGER_REGION, "us-central1");
});

test("the shared .env does not set a bucket for every project", () => {
  const shared = env(".env");
  assert.equal(shared.TASK_IMAGE_BUCKET, undefined);
});
