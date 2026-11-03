# Anonymous auth: who still uses it and a cut-over plan

Status: **documentation only. Nothing changed** (Auth providers, the OTP flag and rules are untouched).

## Which app versions use anonymous auth
| App version | Delegate login | Staff login |
|---|---|---|
| ≤ 1.14.1 (+80), e.g. iOS App Store 1.13.3 | `signInAnonymously()`, then reads `delegates` by phone directly. All later reads/writes run as that anonymous session. | anonymous only for the pre-login phone lookup, then email/password |
| 1.14.2 (+81) and later | `delegateLoginV2` callable → custom token with claims (`role: delegate`, company/org, delegateIds, phones) | `staffPhoneLookup` callable → email/password |

History: `delegateLoginV2` was added 2026-10-24 (73269fd), and anonymous sign-in was removed from the app on 2026-10-25 (edd5375).

## Current usage (read-only count of Auth users, 2026-11-01)
| Session type | active < 1 day | < 7 days | < 30 days | total |
|---|---|---|---|---|
| anonymous (old apps) | **1,559** | 2,805 | 4,806 | 7,322 |
| custom token (delegateLoginV2, new app) | 192 | 209 | 209 | 209 |
| email/password (staff) | 86 | 184 | 286 | 478 |

Most delegates still run old app versions. **Disabling anonymous auth or deploying `firestore.rules.phase1b` today would lock them out.**

## Proposed cut-over
1. **Ship 1.14.2+ everywhere.** iOS: release 1.14.2 (Ready for Distribution). Android: make sure the Play rollout is at 100%.
2. **Force update:** set the app's minimum-version gate to 1.14.2 so old builds show "update required" instead of failing silently.
3. **Watch the numbers weekly** (the same read-only count): wait until anonymous active < 1 day is close to 0, or below an agreed threshold (e.g. < 2% of delegate sessions).
4. **Deploy Phase 1 rules** (safe for old apps). This can happen before step 3 finishes.
5. **Deploy Phase 1b rules**, after the app build with `DelegateQueryScope` is out and adopted. Keep `firestore.rules.phase1` ready to roll back.
6. **Disable the Anonymous provider** in Firebase Auth. Optionally delete stale anonymous users older than 30 days (needs a separate approval).

Rollback at any step: re-enable anonymous auth / redeploy the previous rules file.

## Open decisions
- What adoption threshold do we wait for before step 5/6?
- Should we turn on the force-update gate now?
