"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.mirrorChildPhoneToParent = exports.notifyTaskCreated = exports.notifyTaskChanged = exports.notifyChatMessageCreated = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
admin.initializeApp();
function parseChannelMembers(channelId) {
    const parts = channelId.split('_');
    if (parts.length !== 2)
        return null;
    return { a: parts[0], b: parts[1] };
}
async function getUserTokens(uid) {
    const snap = await admin.firestore().collection('users').doc(uid).collection('fcmTokens').get();
    const tokens = [];
    for (const doc of snap.docs) {
        const data = doc.data();
        const token = (data.token ?? doc.id ?? '').toString();
        if (token)
            tokens.push(token);
    }
    return tokens;
}
async function createUserNotification(uid, notificationId, data) {
    await admin
        .firestore()
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .doc(notificationId)
        .set({
        ...data,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
}
async function sendToUser(uid, payload) {
    const tokens = await getUserTokens(uid);
    if (tokens.length === 0)
        return;
    const res = await admin.messaging().sendEachForMulticast({
        tokens,
        notification: payload.notification,
        data: payload.data,
        android: {
            priority: 'high',
            notification: { channelId: 'chat_and_tasks_v4' },
        },
        apns: {
            payload: { aps: { sound: 'default' } },
        },
    });
    try {
        if (res.failureCount > 0) {
            const sampleErrors = res.responses
                .map((r, idx) => ({
                ok: r.success,
                idx,
                code: r.error?.code,
                msg: r.error?.message,
            }))
                .filter((x) => !x.ok)
                .slice(0, 5);
            console.warn('[functions] push send result', {
                uid,
                tokenCount: tokens.length,
                successCount: res.successCount,
                failureCount: res.failureCount,
                sampleErrors,
            });
        }
    }
    catch (_) {
        // ignore
    }
    // Cleanup invalid tokens.
    const tokensToDelete = [];
    res.responses.forEach((r, idx) => {
        if (r.success)
            return;
        const code = r.error?.code;
        if (code === 'messaging/invalid-registration-token' ||
            code === 'messaging/registration-token-not-registered') {
            tokensToDelete.push(tokens[idx]);
        }
    });
    if (tokensToDelete.length > 0) {
        const batch = admin.firestore().batch();
        for (const t of tokensToDelete) {
            batch.delete(admin.firestore().collection('users').doc(uid).collection('fcmTokens').doc(t));
        }
        await batch.commit();
    }
}
exports.notifyChatMessageCreated = (0, firestore_1.onDocumentCreated)('channels/{channelId}/chatMessages/{messageId}', async (event) => {
    const channelId = event.params.channelId;
    const members = parseChannelMembers(channelId);
    if (!members)
        return;
    const data = event.data?.data();
    if (!data)
        return;
    const senderUid = (data.senderUid ?? '').toString();
    const text = (data.text ?? '').toString();
    const receiverUid = senderUid === members.a ? members.b : members.a;
    if (!receiverUid || receiverUid === senderUid)
        return;
    const snippet = text.length > 140 ? `${text.slice(0, 140)}…` : text;
    const notificationId = event.id?.toString?.() ?? `${channelId}_${event.params.messageId}`;
    // Keep in-app notification list in sync with OS push.
    await createUserNotification(receiverUid, notificationId, {
        type: 'chat',
        title: 'Tin nhắn mới',
        body: snippet,
        channelId,
        senderUid,
        messageId: event.params.messageId,
    });
    await sendToUser(receiverUid, {
        notification: {
            title: 'Tin nhắn mới',
            body: snippet,
        },
        data: {
            type: 'chat',
            channelId,
            messageId: event.params.messageId,
            senderUid,
        },
    });
});
exports.notifyTaskChanged = (0, firestore_1.onDocumentUpdated)('channels/{channelId}/tasks/{taskId}', async (event) => {
    const channelId = event.params.channelId;
    const members = parseChannelMembers(channelId);
    if (!members)
        return;
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after)
        return;
    const updatedByUid = (after.updatedByUid ?? '').toString();
    const receiverUid = updatedByUid === members.a ? members.b : members.a;
    if (!receiverUid || receiverUid === updatedByUid)
        return;
    const title = (after.title ?? 'Công việc').toString();
    const beforeCompleted = !!before.completed;
    const afterCompleted = !!after.completed;
    if (beforeCompleted !== afterCompleted) {
        const notificationId = event.id?.toString?.() ?? `${channelId}_${event.params.taskId}_changed`;
        const body = afterCompleted ? `Đã hoàn thành: ${title}` : `Chưa hoàn thành: ${title}`;
        await createUserNotification(receiverUid, notificationId, {
            type: 'task',
            title: 'Cập nhật công việc',
            body,
            channelId,
            taskId: event.params.taskId,
            senderUid: updatedByUid,
            event: afterCompleted ? 'completed' : 'uncompleted',
        });
        await sendToUser(receiverUid, {
            notification: {
                title: 'Cập nhật công việc',
                body,
            },
            data: {
                type: 'task',
                channelId,
                taskId: event.params.taskId,
                event: afterCompleted ? 'completed' : 'uncompleted',
            },
        });
    }
});
exports.notifyTaskCreated = (0, firestore_1.onDocumentCreated)('channels/{channelId}/tasks/{taskId}', async (event) => {
    const channelId = event.params.channelId;
    const members = parseChannelMembers(channelId);
    if (!members)
        return;
    const data = event.data?.data();
    if (!data)
        return;
    const createdByUid = (data.createdByUid ?? data.updatedByUid ?? '').toString();
    const receiverUid = createdByUid === members.a ? members.b : members.a;
    if (!receiverUid || receiverUid === createdByUid)
        return;
    const title = (data.title ?? 'Công việc').toString();
    const notificationId = event.id?.toString?.() ?? `${channelId}_${event.params.taskId}_created`;
    await createUserNotification(receiverUid, notificationId, {
        type: 'task',
        title: 'Công việc mới',
        body: title,
        channelId,
        taskId: event.params.taskId,
        senderUid: createdByUid,
        event: 'created',
    });
    await sendToUser(receiverUid, {
        notification: {
            title: 'Công việc mới',
            body: title,
        },
        data: {
            type: 'task',
            channelId,
            taskId: event.params.taskId,
            event: 'created',
        },
    });
});
exports.mirrorChildPhoneToParent = (0, firestore_1.onDocumentUpdated)('users/{uid}', async (event) => {
    const uid = event.params.uid;
    const before = event.data?.before.data() ?? {};
    const after = event.data?.after.data() ?? {};
    const role = (after.role ?? '').toString();
    if (role !== 'child')
        return;
    const parentUid = (after.parentUid ?? '').toString();
    if (!parentUid || parentUid === uid)
        return;
    const childPhone = (after.phone ?? '').toString().trim();
    if (!childPhone)
        return;
    const parentPhone = (after.parentPhone ?? '').toString().trim();
    const beforePhone = (before.phone ?? '').toString().trim();
    const beforeParentUid = (before.parentUid ?? '').toString();
    const beforeParentPhone = (before.parentPhone ?? '').toString().trim();
    // Skip if nothing relevant changed.
    if (beforePhone === childPhone &&
        beforeParentUid === parentUid &&
        beforeParentPhone === parentPhone) {
        return;
    }
    const parentRef = admin.firestore().collection('users').doc(parentUid);
    try {
        await admin.firestore().runTransaction(async (tx) => {
            const parentSnap = await tx.get(parentRef);
            const parentData = parentSnap.data();
            const existingChildUid = (parentData?.childUid ?? '').toString().trim();
            const existingChildPhone = (parentData?.childPhone ?? '').toString().trim();
            const updates = {
                linkedChildUids: admin.firestore.FieldValue.arrayUnion(uid),
                childUid: uid,
                childPhone,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            };
            const shouldRemoveOldPhone = existingChildUid === uid &&
                existingChildPhone.length > 0 &&
                existingChildPhone !== childPhone;
            if (shouldRemoveOldPhone) {
                tx.set(parentRef, {
                    ...updates,
                    linkedChildPhones: admin.firestore.FieldValue.arrayRemove(existingChildPhone),
                }, { merge: true });
            }
            else {
                tx.set(parentRef, updates, { merge: true });
            }
            tx.set(parentRef, {
                linkedChildPhones: admin.firestore.FieldValue.arrayUnion(childPhone),
            }, { merge: true });
            if (parentPhone) {
                tx.set(parentRef, { phone: parentPhone }, { merge: true });
            }
        });
        console.log('[functions] mirror child -> parent', {
            uid,
            parentUid,
            childPhone,
            parentPhone,
        });
    }
    catch (e) {
        console.warn('[functions] mirror child -> parent failed', {
            uid,
            parentUid,
            code: e?.code,
            message: e?.message,
        });
    }
});
//# sourceMappingURL=index.js.map