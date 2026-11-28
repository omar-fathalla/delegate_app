/**
 * TAS-365: the delegate's penalty notifications, written by the server
 * (rules in penalty_delegate_notify_logic.ts). onPenaltyCreated calls
 * notifyPenaltyChange for a penalty created ISSUED (createSupervisorPenalty);
 * onPenaltyUpdated for every status change. The push goes out from
 * onNotificationCreated.
 *
 * Deploy (named only, tashil-dev first, then the app, prod with the release):
 *   functions:tashil-mobile-notifications:onPenaltyCreated
 *   functions:tashil-mobile-notifications:onPenaltyUpdated
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  changeMarkedForServer,
  clientAlreadyNotified,
  delegatePenaltyNotification,
  disputeOpened,
  disputeOpenedNotification,
} from "./penalty_delegate_notify_logic";
import {toMillis} from "./respond_to_penalty_logic";

if (admin.apps.length === 0) admin.initializeApp();

type Doc = Record<string, unknown> | undefined | null;

const ORG_ADMIN = new Set(["organizationadmin", "organization-admin", "organization_admin"]);

/** How long to give an old staff app to write its own notification. */
export const OLD_CLIENT_WAIT_MS = 8000;
/** A client notification this close before the change counts as the same event. */
const OLD_CLIENT_LOOKBACK_MS = 60 * 1000;

async function createOnce(db: FirebaseFirestore.Firestore, id: string,
  doc: Record<string, unknown>): Promise<boolean> {
  try {
    await db.collection("notifications").doc(id).create({
      ...doc,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  } catch (e) {
    // ALREADY_EXISTS on a retried event: already sent.
    if ((e as {code?: number}).code !== 6) throw e;
    return false;
  }
}

export interface NotifyOptions {
  /** When the change happened (event time). */
  eventMs: number;
  /** Wait before the old-client check (tests pass 0). */
  waitMs?: number;
}

/**
 * Writes the delegate's notification for this change once, and tells the
 * deciders when a dispute opens. Returns what was written (for tests).
 */
export async function notifyPenaltyChange(
  db: FirebaseFirestore.Firestore,
  penaltyId: string,
  before: Doc,
  after: Doc,
  opts: NotifyOptions,
): Promise<{delegate: boolean; deciders: number}> {
  const out = {delegate: false, deciders: 0};
  const n = delegatePenaltyNotification(penaltyId, before, after);
  if (n) {
    let skip = false;
    if (!changeMarkedForServer(after)) {
      // Old staff app: it writes its own notification right after the change.
      const wait = opts.waitMs ?? OLD_CLIENT_WAIT_MS;
      if (wait > 0) await new Promise((r) => setTimeout(r, wait));
      const existing = await db.collection("notifications").where("penaltyId", "==", penaltyId).get();
      skip = clientAlreadyNotified(
        existing.docs
          .filter((d) => d.id !== n.id)
          .map((d) => ({delegateUid: d.get("delegateUid"), createdAtMs: toMillis(d.get("createdAt"))})),
        n.delegateUid,
        opts.eventMs - OLD_CLIENT_LOOKBACK_MS,
      );
    }
    if (!skip) out.delegate = await createOnce(db, n.id, n.doc);
  }

  if (disputeOpened(before, after)) {
    const p = after || {};
    const org = String(p.organizationId || p.organizationUID || "").trim();
    const recipients = new Set<string>();
    if (org) {
      const users = db.collection("users");
      const [single, multi] = await Promise.all([
        users.where("organizationUID", "==", org).get(),
        users.where("organizationUIDs", "array-contains", org).get(),
      ]);
      for (const d of [...single.docs, ...multi.docs]) {
        const role = String(d.get("role") || "").trim().toLowerCase();
        if (ORG_ADMIN.has(role)) recipients.add(d.id);
      }
    }
    for (const uid of recipients) {
      if (await createOnce(db, `penalty_${penaltyId}_disp_${uid}`, disputeOpenedNotification(penaltyId, p, uid))) {
        out.deciders++;
      }
    }
    // Super admins read the role broadcast (same channel the app used).
    if (await createOnce(db, `penalty_${penaltyId}_disp_super`,
      disputeOpenedNotification(penaltyId, p, "super-admin"))) {
      out.deciders++;
    }
  }
  return out;
}

/**
 * Stamps issuedAt the first time a penalty reaches ISSUED (the dispute window
 * counts from it). Older apps do not write it.
 */
export function needsIssuedAt(before: Doc, after: Doc): boolean {
  const a = after || {};
  const b = before || {};
  return String(a.status || "").toUpperCase() === "ISSUED" &&
    String(b.status || "").toUpperCase() !== "DISPUTED" &&
    a.issuedAt == null;
}

export const onPenaltyUpdated = functions.firestore
  .document("penalties/{penaltyId}")
  .onUpdate(async (change, context) => {
    const penaltyId = context.params.penaltyId as string;
    const before = change.before.data();
    const after = change.after.data();
    if (String(before?.status || "") === String(after?.status || "")) return;
    const db = admin.firestore();
    if (needsIssuedAt(before, after)) {
      await change.after.ref.update({issuedAt: admin.firestore.Timestamp.fromMillis(Date.parse(context.timestamp))});
    }
    const res = await notifyPenaltyChange(db, penaltyId, before, after, {eventMs: Date.parse(context.timestamp)});
    functions.logger.info("onPenaltyUpdated", {penaltyId, from: before?.status, to: after?.status, ...res});
  });
