import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {photoPermissionNotifyUserIds} from "./photo_permission_notify_logic";

admin.initializeApp();

export {onTaskCreated, onTaskUpdated} from "./task_notify";
export {getTaskImage, onTaskImageFinalize} from "./task_image_access";
export {getTaskProofImage, onTaskDeleted, onTaskProofWritten} from "./task_proof_access";


/**
 * Cloud Function triggered when a new photo permission is created.
 */
export const onPhotoPermissionCreated = functions.firestore
  .document("organizations/{organizationId}/companies/{companyId}/photo_permissions/{permissionId}")
  .onCreate(async (snap, context) => {
    const permission = snap.data();
    const permissionId = context.params.permissionId;
    const organizationId = context.params.organizationId;
    const companyId = context.params.companyId;

    try {
      if (permission.status !== 'pending') {
        return null;
      }

      const usersCol = admin.firestore().collection("users");
      const orgRoleQuery = usersCol
        .where("organizationUID", "==", organizationId)
        .where("role", "in", [
          "admin", "supervisor", "company-admin", "company_admin",
          "company_supervisor", "organization-admin", "organizationAdmin",
          "marketingPromotion", "marketing-promotion", "marketing_promotion",
        ])
        .get();
      const orgAdminByListQuery = usersCol
        .where("organizationUIDs", "array-contains", organizationId)
        .get();
      const globalRoleQuery = usersCol
        .where("role", "in", [
          "superAdmin", "super-admin", "super_admin",
          "technicalSupport", "technical-support", "technical_support",
        ])
        .get();
      const [orgRoleSnap, orgAdminByListSnap, globalSnap] = await Promise.all([
        orgRoleQuery, orgAdminByListQuery, globalRoleQuery,
      ]);
      const seenDocs = new Map<string, FirebaseFirestore.DocumentData & {id: string}>();
      for (const snap of [orgRoleSnap, orgAdminByListSnap, globalSnap]) {
        for (const doc of snap.docs) {
          if (!seenDocs.has(doc.id)) {
            seenDocs.set(doc.id, {id: doc.id, ...doc.data()});
          }
        }
      }

      const targetUserIds = photoPermissionNotifyUserIds(
        Array.from(seenDocs.values()),
        companyId,
        organizationId,
      );

      if (targetUserIds.length === 0) {
        console.log("No users found to notify for permission:", permissionId);
        return null;
      }

      const notificationTitle = "طلب إذن تصوير جديد";
      const notificationBody = `قام مندوب بطلب إذن تصوير في ${permission.companyName || "الشركة"}`;

      const batch = admin.firestore().batch();
      const fcmTokens: string[] = [];

      for (const userId of targetUserIds) {
        const notificationRef = admin.firestore().collection("notifications").doc();
        batch.set(notificationRef, {
          delegateUid: userId,
          organizationId,
          companyId,
          title: notificationTitle,
          body: notificationBody,
          type: "photo_permission",
          permissionId,
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        const tokenDoc = await admin.firestore().collection("fcm_tokens").doc(userId).get();
        if (tokenDoc.exists && tokenDoc.data()?.token) {
          fcmTokens.push(tokenDoc.data()!.token);
        }
      }

      await batch.commit();

      if (fcmTokens.length > 0) {
        await admin.messaging().sendEachForMulticast({
          notification: {
            title: notificationTitle,
            body: notificationBody,
          },
          data: {
            type: "photo_permission",
            permissionId,
            organizationId,
            companyId,
          },
          tokens: fcmTokens,
        });
      }
      return null;
    } catch (error) {
      console.error("Error in onPhotoPermissionCreated:", error);
      return null;
    }
  });

/**
 * Cloud Function triggered when a photo permission is updated.
 */
export const onPhotoPermissionUpdated = functions.firestore
  .document("organizations/{organizationId}/companies/{companyId}/photo_permissions/{permissionId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const permissionId = context.params.permissionId;
    const organizationId = context.params.organizationId;
    const companyId = context.params.companyId;

    try {
      if (before.status === after.status) {
        return null;
      }

      const requestedBy = after.requestedBy;
      if (!requestedBy) return null;

      let notificationTitle = "تحديث إذن التصوير";
      let notificationBody = `تم تحديث حالة إذن التصوير لشركة ${after.companyName || ""}`;

      if (after.status === "approved") {
        notificationTitle = "تمت الموافقة على إذن التصوير";
        notificationBody = `تمت الموافقة على إذن التصوير لشركة ${after.companyName || ""}`;
      } else if (after.status === "rejected") {
        notificationTitle = "تم رفض إذن التصوير";
        notificationBody = `تم رفض طلب إذن التصوير لشركة ${after.companyName || ""}`;
      }

      const batch = admin.firestore().batch();
      
      const notificationRef = admin.firestore().collection("notifications").doc();
      batch.set(notificationRef, {
        delegateUid: requestedBy,
        organizationId,
        companyId,
        title: notificationTitle,
        body: notificationBody,
        type: "photo_permission",
        permissionId,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await batch.commit();

      const tokenDoc = await admin.firestore().collection("fcm_tokens").doc(requestedBy).get();
      if (tokenDoc.exists && tokenDoc.data()?.token) {
        await admin.messaging().send({
          notification: {
            title: notificationTitle,
            body: notificationBody,
          },
          data: {
            type: "photo_permission",
            permissionId,
            organizationId,
            companyId,
          },
          token: tokenDoc.data()!.token,
        });
      }

      return null;
    } catch (error) {
      console.error("Error in onPhotoPermissionUpdated:", error);
      return null;
    }
  });

/**
 * Cloud Function triggered when any new notification is created in Firestore.
 * Automatically dispatches FCM push notifications to target device(s) or FCM topic.
 */
export const onNotificationCreated = functions.firestore
  .document("notifications/{notificationId}")
  .onCreate(async (snap, context) => {
    const notification = snap.data();
    const { delegateUid, title, body, organizationId, companyId, type, phoneNumber, taskId } = notification;

    if (!title || !body) return null;

    try {
      if (delegateUid === "all") {
        // Broadcast push notification to topic 'app_updates'
        await admin.messaging().send({
          topic: "app_updates",
          notification: { title, body },
          android: {
            priority: "high",
            notification: {
              channelId: "task_notifications",
              sound: "default",
              clickAction: "FLUTTER_NOTIFICATION_CLICK",
            },
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
                badge: 1,
              },
            },
          },
          data: {
            type: type || "support_broadcast",
            organizationId: organizationId || "",
            companyId: companyId || "",
            taskId: taskId || "",
          },
        });
        console.log("Successfully sent broadcast push notification to FCM topic 'app_updates'");
      } else if (delegateUid) {
        let recipientUid = delegateUid;

        // Try direct token lookup
        let tokenDoc = await admin.firestore()
          .collection("fcm_tokens")
          .doc(recipientUid)
          .get();

        // If not found and phone number is provided or delegateUid is phone-based, resolve user
        if ((!tokenDoc.exists || !tokenDoc.data()?.token) && (phoneNumber || recipientUid.startsWith("phone_"))) {
          const rawPhone = phoneNumber || recipientUid.replace("phone_", "");
          const cleanPhone = rawPhone.replace(/\D/g, "");

          const usersSnap = await admin.firestore()
            .collection("users")
            .where("phone", "==", rawPhone)
            .limit(1)
            .get();

          if (!usersSnap.empty) {
            recipientUid = usersSnap.docs[0].id;
            tokenDoc = await admin.firestore()
              .collection("fcm_tokens")
              .doc(recipientUid)
              .get();
          } else if (cleanPhone.length >= 9) {
            const delegatesSnap = await admin.firestore()
              .collectionGroup("delegates")
              .where("phone", "==", rawPhone)
              .limit(1)
              .get();

            if (!delegatesSnap.empty) {
              recipientUid = delegatesSnap.docs[0].data().uid || delegatesSnap.docs[0].id;
              tokenDoc = await admin.firestore()
                .collection("fcm_tokens")
                .doc(recipientUid)
                .get();
            }
          }
        }

        if (tokenDoc.exists && tokenDoc.data()?.token) {
          const fcmToken = tokenDoc.data()!.token;
          await admin.messaging().send({
            notification: { title, body },
            android: {
              priority: "high",
              notification: {
                channelId: "task_notifications",
                sound: "default",
                clickAction: "FLUTTER_NOTIFICATION_CLICK",
              },
            },
            apns: {
              payload: {
                aps: {
                  sound: "default",
                  badge: 1,
                },
              },
            },
            data: {
              type: type || "support_alert",
              organizationId: organizationId || "",
              companyId: companyId || "",
              taskId: taskId || "",
            },
            token: fcmToken,
          });
          console.log(`Successfully sent FCM push notification to delegate ${recipientUid}`);
        } else {
          console.log(`No active FCM token found for recipient ${recipientUid}`);
        }
      }
      return null;
    } catch (error) {
      console.error("Error in onNotificationCreated FCM push function:", error);
      return null;
    }
  });

export {delegateLoginV2} from "./delegate_login";
export {onDelegateLinkDeleted} from "./delegate_link_deleted";
export {confirmDelegateOtp} from "./confirm_delegate_otp";
export {staffPhoneLookup} from "./staff_phone_lookup";
export {listGlobalNotifyStaff} from "./list_global_notify_staff";

export {createStaffUser, resendStaffSetupLink, claimInvite} from "./staff_accounts";
export {
  sendStaffPasswordSetupEmail,
  requestStaffPasswordReset,
  completeStaffPasswordSetup,
} from "./staff_password_email";
export {checkDelegateDuplicate} from "./check_delegate_duplicate";
export {
  editDelegateProfile,
  submitNationalIdUpdate,
  reviewNationalIdUpdate,
} from "./delegate_profile_edit";


// Delegate subscriptions: period-end suspension (daily, Cairo time). Paymob
// hooks (quoteSubscriptionRequest / applyVerifiedSubscriptionPayment) are
// library functions for Engineering's Paymob webhook, not deployed endpoints.
export {stampDelegateSource} from "./stamp_delegate_source";
export {setDelegateHold} from "./set_delegate_hold";
export {supervisorReuploadDelegateDocument} from "./supervisor_delegate_doc_reupload";
export {privilegedReuploadDelegateDocument} from "./privileged_delegate_doc_reupload";
export {ensureStorageUploadIntent} from "./storage_upload_intent";
export {startBillingCycle} from "./start_billing_cycle";
export {auditDelegateHoldShadow} from "./holds_shadow";
export {auditDelegateRequestOrgs} from "./request_org_company_check";
export {auditDelegateCreateOrgs} from "./request_org_company_check";
export {
  autoLinkOnCompanyJoin,
  autoLinkOnDelegateWrite,
  autoLinkOnUserStatus,
  reconcileCompanyChainLinksDaily,
} from "./company_chain_autolink";
export {suspendExpiredSubscriptions} from "./subscription_schedule";
export {
  expireAbandonedSubscriptionRenewals,
  finalizeSubscriptionRenewalOnStatus,
  reconcileSubscriptionPaymentsScheduled,
  remindSupervisorsBeforeSubscriptionPeriodEnd,
} from "./subscription_schedule";
export {
  createSubscriptionCheckout,
  previewSubscriptionQuote,
  reconcileSubscriptionPayments,
  paymobSubscriptionWebhook,
} from "./paymob_subscription";
