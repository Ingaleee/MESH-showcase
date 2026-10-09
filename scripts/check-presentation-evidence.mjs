import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { resolve, relative, isAbsolute } from "node:path";

const root = process.cwd();
const folder = "docs/evidence/presentation-oct09";
const json = async (path) => JSON.parse(await readFile(resolve(root, path), "utf8"));
const manifest = await json(`${folder}/manifest.json`);
assert.equal(manifest.schema_version, 1);
assert.equal(manifest.clean_run_id, 37909616516);
assert.equal(manifest.recorded_revision, "fa40e9778ab8453aafff5fc8180c12fb8769aa99");
assert.equal(manifest.accepted_application_revision, "3d849af84c9afd8885f57ae7f6390c2d540361e4");
assert.equal(manifest.downloaded_artifact_id, 11606064166);
assert.equal(
  manifest.downloaded_artifact_sha256,
  "ce25a2349fd260eb4d0f8b1da1c6461404c4346d3f65b0814fb0d8c1d8664969",
);
const paths = new Set();
for (const entry of manifest.files) {
  assert.ok(!paths.has(entry.path), "Duplicate manifest entry");
  paths.add(entry.path);
  const path = resolve(root, entry.path);
  const local = relative(root, path);
  assert.ok(!isAbsolute(local) && !local.startsWith(".."), "Evidence path leaves repository");
  assert.ok(
    entry.path.startsWith(`${folder}/`) || entry.path.startsWith("docs/presentation/assets/"),
  );
  const bytes = await readFile(path);
  assert.equal(bytes.length, entry.bytes, entry.path);
  assert.equal(createHash("sha256").update(bytes).digest("hex"), entry.sha256, entry.path);
}
const capture = await json(`${folder}/capture.json`);
assert.equal(capture.revision, manifest.recorded_revision);
assert.equal(capture.source_application_revision, manifest.accepted_application_revision);
assert.ok(capture.duration_seconds >= 60 && capture.duration_seconds <= 90);
assert.equal(capture.no_mocked_api_or_state, true);
assert.equal(capture.unknown_observed, true);
assert.equal(capture.action_code, "lookup_only");
assert.equal(capture.remote_state_queried_by_diagnostic, false);
assert.equal(capture.original_operation_id, capture.recovered_operation_id);
assert.equal(capture.publish_requests_delta, 1);
assert.equal(capture.remote_effects_for_operation, 1);
const context = await json(`${folder}/clean-demo/context.json`);
assert.equal(context.revision, manifest.recorded_revision);
assert.equal(context.run_id, String(manifest.clean_run_id));
assert.equal(context.command, "npm run demo");
const summary = await json(`${folder}/clean-demo/summary.json`);
const stages = await json(`${folder}/clean-demo/stages.json`);
assert.equal(summary.success, true);
assert.deepEqual(stages, summary.stages);
assert.equal(stages.length, 17);
assert.ok(stages.every((stage) => stage.exit_code === 0 && stage.elapsed_seconds >= 0));
assert.equal((await json(`${folder}/clean-demo/readiness.json`)).status, "ready");
const browser = await json(`${folder}/clean-demo/playwright.json`);
assert.deepEqual(browser.errors, []);
assert.deepEqual(
  [browser.stats.expected, browser.stats.skipped, browser.stats.unexpected, browser.stats.flaky],
  [4, 0, 0, 0],
);
const partner = await json(`${folder}/clean-demo/partner.json`);
assert.equal(partner.success, true);
assert.equal(partner.remote_publish_requests, 3);
assert.deepEqual(
  partner.downloads.map((item) => item.phase),
  ["normal_release", "lost_response", "rollback"],
);
assert.ok(partner.downloads.every((item) => item.private_authenticated_download && item.bytes > 0));
const gallery = await json(`${folder}/gallery-capture.json`);
assert.equal(gallery.no_mocked_api_or_state, true);
assert.ok(gallery.screens.find((item) => item.name === "creators" && item.visible_images_decoded));
const site = await json(`${folder}/site-check.json`);
assert.equal(site.video_playback_progress_verified, true);
assert.deepEqual(site.seek_positions_seconds, [15, 40, 50]);
assert.equal(site.decoded_images, 11);
assert.equal(site.caption_cues, 9);
assert.deepEqual(site.http_errors, []);
assert.ok(site.viewports.every((item) => item.overflow_px === 0 && item.wcag_violations === 0));
const page = await readFile("docs/presentation/index.html", "utf8");
assert.equal((page.match(/<figure>/g) ?? []).length, 11);
for (const path of [
  "docs/presentation/assets/mesh-demo.webm",
  "docs/presentation/assets/mesh-demo.en.vtt",
  `${folder}/capture.json`,
  `${folder}/clean-demo/playwright.json`,
  `${folder}/gallery-capture.json`,
]) {
  assert.ok(paths.has(path), "Missing required report/media hash: " + path);
}
console.log(
  JSON.stringify({
    success: true,
    hashed_files: paths.size,
    cold_preparation_stages: 17,
    browser_checks: 4,
    screenshots: 11,
    publish_requests: 1,
    remote_effects: 1,
  }),
);
