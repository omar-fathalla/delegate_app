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
