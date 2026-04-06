"use strict";
/**
 * Cloud Function để gửi FCM push notification
 * Trigger: Khi có document mới trong channels/{channelId}/notifications
 * - Nếu type = 'task_completed': Gửi notification tới người con
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.testSendNotification = exports.sendTaskNotification = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();
/**
 * Cloud Function được trigger khi có document mới trong notifications collection
 * Hỗ trợ 2 loại: task_completed và task_overdue
 */
exports.sendTaskNotification = functions.firestore
    .document("channels/{channelId}/notifications/{notificationId}")
    .onCreate(async (snap, context) => {
    const notification = snap.data();
    const { channelId } = context.params;
    try {
        if (!notification) {
            console.log("Notification data is empty, skipping");
            return;
        }
        const notificationType = notification.type;
        // Chỉ xử lý notification loại task_completed hoặc task_overdue
        if (notificationType !== "task_completed" && notificationType !== "task_overdue") {
            console.log(`Notification type '${notificationType}' is not supported, skipping`);
            return;
        }
        const { taskTitle, recipientUid, completedBy, completedByUid: parentUid, dueDate, } = notification;
        if (!recipientUid) {
            console.error("recipientUid not found in notification");
            return;
        }
        // Lấy device token của người con từ Firestore
        const recipientDoc = await db.collection("users").doc(recipientUid).get();
        if (!recipientDoc.exists) {
            console.error(`User document not found for ${recipientUid}`);
            return;
        }
        const recipientData = recipientDoc.data();
        let deviceTokens = [];
        // Lấy device tokens (có thể là array hoặc single token)
        if (recipientData?.deviceTokens) {
            if (Array.isArray(recipientData.deviceTokens)) {
                deviceTokens = recipientData.deviceTokens.filter((token) => typeof token === "string" && token.length > 0);
            }
            else if (typeof recipientData.deviceTokens === "string") {
                deviceTokens = [recipientData.deviceTokens];
            }
        }
        if (deviceTokens.length === 0) {
            console.warn(`No valid device tokens found for user ${recipientUid}`);
            return;
        }
        console.log(`Sending ${notificationType} notification to ${recipientUid} with ${deviceTokens.length} device(s)`);
        // Xác định tiêu đề và body dựa trên loại thông báo
        let titleText;
        let bodyText;
        let emoji;
        if (notificationType === "task_completed") {
            emoji = "✅";
            titleText = "Công việc đã hoàn thành";
            bodyText = `Cha/Mẹ đã hoàn thành: ${taskTitle}`;
        }
        else if (notificationType === "task_overdue") {
            emoji = "⏰";
            titleText = "Công việc quá hạn";
            bodyText = `Cha/Mẹ chưa hoàn thành: ${taskTitle}`;
        }
        else {
            return;
        }
        // Tạo nội dung notification
        const payload = {
            tokens: deviceTokens,
            notification: {
                title: `${emoji} ${titleText}`,
                body: bodyText,
            },
            data: {
                type: notificationType,
                taskTitle: taskTitle || "",
                channelId: channelId,
                completedBy: completedBy || "",
                parentUid: parentUid || "",
                dueDate: dueDate || "",
                timestamp: new Date().toISOString(),
            },
            webpush: {
                notification: {
                    title: `${emoji} ${titleText}`,
                    body: bodyText,
                    icon: "https://via.placeholder.com/192?text=CareElder",
                    badge: "https://via.placeholder.com/128?text=CE",
                    requireInteraction: true,
                },
                fcmOptions: {
                    link: `https://eldercare.app/channel/${channelId}`,
                },
            },
            apns: {
                payload: {
                    aps: {
                        alert: {
                            title: `${emoji} ${titleText}`,
                            body: bodyText,
                        },
                        sound: "default",
                        badge: 1,
                        "custom-data": {
                            type: notificationType,
                            taskTitle: taskTitle || "",
                            channelId: channelId,
                        },
                    },
                },
            },
        };
        // Gửi notification tới tất cả device
        const response = await messaging.sendEachForMulticast(payload);
        console.log(`Successfully sent ${response.successCount} notification(s), failed: ${response.failureCount}`);
        if (response.failureCount > 0) {
            const failedTokens = [];
            response.responses.forEach((resp, idx) => {
                if (!resp.success) {
                    failedTokens.push(deviceTokens[idx]);
                    console.error(`Failed to send notification to ${deviceTokens[idx]}:`, resp.error);
                }
            });
            // Xóa invalid tokens
            if (failedTokens.length > 0) {
                console.log(`Removing ${failedTokens.length} invalid token(s)`);
                await removeInvalidTokens(recipientUid, failedTokens);
            }
        }
        // Update notification status
        await snap.ref.update({
            sent: true,
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
            sentToDevices: response.successCount,
        });
    }
    catch (error) {
        console.error(`Error in sendTaskNotification:`, error);
        // Update error status
        await snap.ref.update({
            sent: false,
            error: String(error),
            errorAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
});
/**
 * Helper function để xóa invalid device tokens
 */
async function removeInvalidTokens(userId, invalidTokens) {
    try {
        const userRef = db.collection("users").doc(userId);
        const userData = await userRef.get();
        if (!userData.exists) {
            return;
        }
        const currentTokens = userData.data()?.deviceTokens || [];
        // Lọc ra tokens hợp lệ
        const validTokens = currentTokens.filter((token) => !invalidTokens.includes(token));
        if (validTokens.length === currentTokens.length) {
            return;
        }
        await userRef.update({
            deviceTokens: validTokens,
            lastTokenUpdate: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`Removed ${invalidTokens.length} invalid token(s) for user ${userId}`);
    }
    catch (error) {
        console.error("Error removing invalid tokens:", error);
    }
}
/**
 * Optional: HTTP endpoint để manual test
 */
exports.testSendNotification = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
    }
    const { recipientUid, taskTitle, channelId } = data;
    if (!recipientUid || !taskTitle || !channelId) {
        throw new functions.https.HttpsError("invalid-argument", "Missing required fields");
    }
    try {
        const recipientDoc = await db.collection("users").doc(recipientUid).get();
        if (!recipientDoc.exists) {
            throw new functions.https.HttpsError("not-found", "User not found");
        }
        const deviceTokens = recipientDoc.data()?.deviceTokens || [];
        if (!Array.isArray(deviceTokens) || deviceTokens.length === 0) {
            throw new functions.https.HttpsError("failed-precondition", "No device tokens found");
        }
        const payload = {
            tokens: deviceTokens,
            notification: {
                title: "✅ Test Notification",
                body: `Test: ${taskTitle}`,
            },
            data: {
                type: "test",
                taskTitle: taskTitle || "",
                channelId: channelId || "",
            },
        };
        const response = await messaging.sendEachForMulticast(payload);
        return {
            success: true,
            successCount: response.successCount,
            failureCount: response.failureCount,
            message: `Test notification sent to ${response.successCount} device(s)`,
        };
    }
    catch (error) {
        console.error("Error in testSendNotification:", error);
        throw new functions.https.HttpsError("internal", String(error));
    }
});
//# sourceMappingURL=index.js.map