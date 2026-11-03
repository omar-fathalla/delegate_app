# Rollback record — v<VERSION>

| Field | Value |
|---|---|
| Date (Africa/Cairo) | |
| Release SHA | |
| Release tag | v |
| Previous SHA | |
| Previous tag | v |
| Hosting site / release ID (before) | tashil-hr-test / |
| Hosting release ID (after) | |
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
firebase hosting:clone tashil-hr-test:<previous release/channel> tashil-hr-test:live --project <project>

# Firestore / Storage rules (redeploy from the previous tag)
git checkout v<previous> -- firestore.rules storage.rules
firebase deploy --only firestore:rules,storage --project <project>

# Functions (redeploy from the previous tag)
firebase deploy --only functions:<name> --project <project>

# Android
# Play Console: halt the rollout, then release a higher versionCode built from v<previous>
```

## Notes
