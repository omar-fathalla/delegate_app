# Rollback record — v<VERSION>

| Field | Value |
|---|---|
| Date (Africa/Cairo) | |
| Release SHA | |
| Release tag | v |
| Previous SHA | |
| Previous tag | v |
| Hosting site | tashil-hr-test (HR web, hr.sw-point.com), project practice-firebase-72df1 |
| Hosting version ID (before) | |
| Hosting version ID (after) | |
| Firestore ruleset ID (before → after) | → |
| Storage ruleset ID (before → after) | → |
| Firestore indexes changed | |
| Functions deployed (name, region) | |
| Android versionCode / Play track | |
| User Test OK (SHA, time) | |
| Approved by (Mohamed, time) | |

## Rollback commands
```bash
# Code
git revert -m 1 <release merge SHA>   # via PR into main, never force-push

# Hosting
firebase hosting:clone tashil-hr-test@<previous version id> tashil-hr-test:live --project practice-firebase-72df1

# Firestore / Storage rules (redeploy from the previous tag)
git checkout v<previous> -- firestore.rules storage.rules
firebase deploy --only firestore:rules,storage --project <project>

# Functions (redeploy from the previous tag)
firebase deploy --only functions:<name> --project <project>

# Android
# Play Console: halt the staged rollout if running.
# Then: revert PR into main + versionCode bump above the current one,
# released through the normal flow (User Test OK on the SHA, Mohamed's go).
```

## Notes
