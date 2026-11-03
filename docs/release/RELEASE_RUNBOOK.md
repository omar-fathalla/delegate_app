# Tashil App release runbook (dev → main)

This applies to Tashil App (`omar-fathalla/delegate_app`) only.

## 1. Flow
1. Every change goes through a PR into `dev`. User Test checks the PR's preview and gives an OK before the PR is merged into `dev`.
2. When `dev` is ready to release, write down the **exact dev SHA** (`git rev-parse origin/dev`).
3. User Test runs the full dev test on **that SHA** and gives an OK naming it. If `dev` moves after that, the OK no longer counts and the test runs again.
4. Mohamed gives his own go for the release, naming the SHA. An agent's OK is not enough.
5. Open a PR `dev → main` whose head is exactly the approved SHA, and merge it. No other commits go to `main`.
6. Production deploys (Hosting, rules, indexes, functions) and the rules cut-over each need **a separate go from Mohamed** and a filled rollback record (section 5) before they run.

- Without GitHub Pro the CI checks can't be made required, so **never merge into `dev` (or `main`) when the CI run on the exact PR head is red or missing**.

## 2. Manual version bump
CI no longer bumps the version or pushes commits.
- In a normal PR into `dev`, edit `pubspec.yaml` `version: X.Y.Z+N`. **N (the versionCode) must be greater than the last released one**. Google Play rejects anything else.
- `android-release.yml` has a "Check versionCode was bumped" step. It compares N with the build number in `pubspec.yaml` at the newest `v*` tag that does not contain HEAD (so a re-run on an already tagged release still passes) and fails before the build if N is not greater.
- Find the current value with `git tag -l 'v*' --sort=-v:refname --no-contains origin/main | head -1`, then `git show <tag>:pubspec.yaml | grep ^version:`.

## 3. Tag the release SHA
Tag only **after a successful release build** of the merged `main` commit (never before):
```bash
git fetch origin
SHA=$(git rev-parse origin/main)     # must be the approved release commit
VERSION=$(git show $SHA:pubspec.yaml | grep -m1 '^version:' | sed 's/version: //; s/+.*//')
git tag -a "v$VERSION" "$SHA" -m "Release v$VERSION"
git push origin "v$VERSION"          # never -f; an existing tag means the version was not bumped
```
The tag is what the versionCode check and the rollback record point to.

## 4. No changelog publish
The in-app «ما الجديد» (what's new) feature was removed, and its CI step was removed from `android-release.yml`. Releases do not publish a changelog and do not write to `app_updates` or anything else in Firestore.

## 5. Rollback record
Before any production deploy, copy `docs/release/ROLLBACK_RECORD_TEMPLATE.md` to `docs/release/records/<date>-v<version>.md`, fill it in with the **current** live IDs (so you can go back to them), and get it approved. Update it after the deploy.

## 6. Rolling back
- Code: revert the `dev → main` merge in a PR. Do not force-push `main`.
- Hosting: `firebase hosting:clone <site>@<previous version id> <site>:live` using the version ID in the record.
- Rules: redeploy the previous ruleset IDs in the record.
- Android: halt the staged rollout in Play Console if one is running. Then open a revert PR into `main` and bump the versionCode above the current one in it, and ship it through the normal release flow (User Test OK on the SHA, Mohamed's go).
Every rollback needs Mohamed's go, the same as a deploy.
