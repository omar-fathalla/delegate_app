import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

/**
 * Cloud Function triggered when a new task is created.
 * Sends push notifications to assigned delegates and creates notification documents.
 */
export const onTaskCreated = functions.firestore
  .document("organizations/{organizationId}/tasks/{taskId}")
  .onCreate(async (snap, context) => {
    const task = snap.data();
    const taskId = context.params.taskId;
    const organizationId = context.params.organizationId;

    try {
      // Get assigned delegate UIDs
      const assignedTo = task.assignedTo as string[];
      if (!assignedTo || assignedTo.length === 0) {
        console.log("No delegates assigned to task:", taskId);
        return null;
      }

      const companyId = task.companyId;

      // Prepare notification data
      const notificationTitle = "مهمة جديدة";
      const notificationBody = `تم تعيين مهمة جديدة لك: ${task.title}`;

      // Create notification documents and send FCM messages
      const batch = admin.firestore().batch();
      const fcmTokens: string[] = [];

      for (const delegateUid of assignedTo) {
        // Create notification document
        const notificationRef = admin.firestore()
          .collection("notifications")
          .doc();

        batch.set(notificationRef, {
          delegateUid,
          organizationId,
          companyId,
          title: notificationTitle,
          body: notificationBody,
          type: "task",
          taskId,
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Get FCM token for this delegate
        const tokenDoc = await admin.firestore()
          .collection("fcm_tokens")
          .doc(delegateUid)
          .get();

        if (tokenDoc.exists) {
          const tokenData = tokenDoc.data();
          if (tokenData && tokenData.token) {
            fcmTokens.push(tokenData.token);
          }
        }
      }

      // Commit notification documents
      await batch.commit();
      console.log(`Created ${assignedTo.length} notification documents`);

      // Send FCM messages
      if (fcmTokens.length > 0) {
        const message = {
          notification: {
            title: notificationTitle,
            body: notificationBody,
          },
          data: {
            type: "task",
            taskId,
            organizationId,
            companyId,
          },
          tokens: fcmTokens,
        };

        const response = await admin.messaging().sendEachForMulticast(message);
        console.log(`Successfully sent ${response.successCount} messages`);
        console.log(`Failed to send ${response.failureCount} messages`);

        // Clean up invalid tokens
        if (response.failureCount > 0) {
          const tokensToRemove: string[] = [];
          response.responses.forEach((resp, idx) => {
            if (!resp.success) {
              console.error("Error sending to token:", fcmTokens[idx], resp.error);
              // Remove invalid tokens
              if (resp.error?.code === "messaging/invalid-registration-token" ||
                  resp.error?.code === "messaging/registration-token-not-registered") {
                tokensToRemove.push(fcmTokens[idx]);
              }
            }
          });

          // Delete invalid tokens from Firestore
          for (const token of tokensToRemove) {
            const tokenQuery = await admin.firestore()
              .collection("fcm_tokens")
              .where("token", "==", token)
              .get();

            tokenQuery.forEach((doc) => {
              doc.ref.delete();
            });
          }
        }
      } else {
        console.log("No FCM tokens found for assigned delegates");
      }

      return null;
    } catch (error) {
      console.error("Error in onTaskCreated:", error);
      return null;
    }
  });

/**
 * Cloud Function triggered when a task is updated.
 * Sends notifications if task status changes or new delegates are assigned.
 */
export const onTaskUpdated = functions.firestore
  .document("organizations/{organizationId}/tasks/{taskId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const taskId = context.params.taskId;
    const organizationId = context.params.organizationId;

    try {
      // Check if status changed
      const statusChanged = before.status !== after.status;

      // Check if new delegates were assigned
      const beforeAssigned = new Set(before.assignedTo || []);
      const afterAssigned = new Set(after.assignedTo || []);
      const newlyAssigned = [...afterAssigned].filter((uid) => !beforeAssigned.has(uid));

      if (!statusChanged && newlyAssigned.length === 0) {
        console.log("No relevant changes to notify about");
        return null;
      }

      const companyId = after.companyId;

      // Send notifications for newly assigned delegates
      if (newlyAssigned.length > 0) {
        const notificationTitle = "مهمة جديدة";
        const notificationBody = `تم تعيين مهمة لك: ${after.title}`;

        const batch = admin.firestore().batch();
        const fcmTokens: string[] = [];

        for (const delegateUid of newlyAssigned) {
          const notificationRef = admin.firestore()
            .collection("notifications")
            .doc();

          batch.set(notificationRef, {
            delegateUid: delegateUid as string,
            organizationId,
            companyId,
            title: notificationTitle,
            body: notificationBody,
            type: "task",
            taskId,
            isRead: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          const tokenDoc = await admin.firestore()
            .collection("fcm_tokens")
            .doc(delegateUid as string)
            .get();

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
              type: "task",
              taskId,
              organizationId,
              companyId,
            },
            tokens: fcmTokens,
          });
        }
      }

      return null;
    } catch (error) {
      console.error("Error in onTaskUpdated:", error);
      return null;
    }
  });

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

      const usersQuery = await admin.firestore().collection("users")
        .where("organizationUID", "==", organizationId)
        .where("role", "in", ["supervisor", "admin", "organizationAdmin"])
        .get();

      const targetUserIds: string[] = [];
      usersQuery.forEach((doc) => {
        const userData = doc.data();
        if (userData.role === 'supervisor') {
          if (userData.companyUID === companyId) {
            targetUserIds.push(doc.id);
          }
        } else {
          targetUserIds.push(doc.id);
        }
      });

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
    const { delegateUid, title, body, organizationId, companyId, type, phoneNumber } = notification;

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

