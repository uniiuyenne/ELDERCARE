/**
 * Cloud Function để gửi FCM push notification
 * Trigger: Khi có document mới trong channels/{channelId}/notifications
 * - Nếu type = 'task_completed': Gửi notification tới người con
 */
import * as functions from "firebase-functions";
/**
 * Cloud Function được trigger khi có document mới trong notifications collection
 * Hỗ trợ 2 loại: task_completed và task_overdue
 */
export declare const sendTaskNotification: functions.CloudFunction<functions.firestore.QueryDocumentSnapshot>;
/**
 * Optional: HTTP endpoint để manual test
 */
export declare const testSendNotification: functions.HttpsFunction & functions.Runnable<any>;
