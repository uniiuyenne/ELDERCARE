import * as admin from 'firebase-admin';
import { onDocumentCreated, onDocumentUpdated } from 'firebase-functions/v2/firestore';

admin.initializeApp();

function parseChannelMembers(channelId: string): { a: string; b: string } | null {
  const parts = channelId.split('_');
  if (parts.length !== 2) return null;
  return { a: parts[0], b: parts[1] };
}

async function getUserTokens(uid: string): Promise<string[]> {
  const snap = await admin.firestore().collection('users').doc(uid).collection('fcmTokens').get();
  const tokens: string[] = [];
  for (const doc of snap.docs) {
    const data = doc.data();
    const token = (data.token ?? doc.id ?? '').toString();
    if (token) tokens.push(token);
  }
  return tokens;
}

async function createUserNotification(
  uid: string,
  notificationId: string,
  data: {
    type: 'chat' | 'task';
    title: string;
    body: string;
    channelId: string;
    senderUid?: string;
    taskId?: string;
    messageId?: string;
    event?: string;
  },
) {
  await admin
    .firestore()
    .collection('users')
    .doc(uid)
    .collection('notifications')
    .doc(notificationId)
    .set(
      {
        ...data,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
}

async function sendToUser(uid: string, payload: admin.messaging.MessagingPayload) {
  const tokens = await getUserTokens(uid);
  if (tokens.length === 0) return;

  const res = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: payload.notification,
    data: payload.data as Record<string, string> | undefined,
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
          code: (r.error as any)?.code as string | undefined,
          msg: (r.error as any)?.message as string | undefined,
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
  } catch (_) {
    // ignore
  }

  // Cleanup invalid tokens.
  const tokensToDelete: string[] = [];
  res.responses.forEach((r, idx) => {
    if (r.success) return;
    const code = (r.error as any)?.code as string | undefined;
    if (
      code === 'messaging/invalid-registration-token' ||
      code === 'messaging/registration-token-not-registered'
    ) {
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

export const notifyChatMessageCreated = onDocumentCreated(
  'channels/{channelId}/chatMessages/{messageId}',
  async (event) => {
    const channelId = event.params.channelId as string;
    const members = parseChannelMembers(channelId);
    if (!members) return;

    const data = event.data?.data();
    if (!data) return;

    const senderUid = (data.senderUid ?? '').toString();
    const text = (data.text ?? '').toString();

    const receiverUid = senderUid === members.a ? members.b : members.a;
    if (!receiverUid || receiverUid === senderUid) return;

    const snippet = text.length > 140 ? `${text.slice(0, 140)}…` : text;
    const notificationId = (event as any).id?.toString?.() ?? `${channelId}_${event.params.messageId}`;

    // Keep in-app notification list in sync with OS push.
    await createUserNotification(receiverUid, notificationId, {
      type: 'chat',
      title: 'Tin nhắn mới',
      body: snippet,
      channelId,
      senderUid,
      messageId: event.params.messageId as string,
    });

    await sendToUser(receiverUid, {
      notification: {
        title: 'Tin nhắn mới',
        body: snippet,
      },
      data: {
        type: 'chat',
        channelId,
        messageId: event.params.messageId as string,
        senderUid,
      },
    });
  },
);

export const notifyTaskChanged = onDocumentUpdated(
  'channels/{channelId}/tasks/{taskId}',
  async (event) => {
    const channelId = event.params.channelId as string;
    const members = parseChannelMembers(channelId);
    if (!members) return;

    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const updatedByUid = (after.updatedByUid ?? '').toString();
    const receiverUid = updatedByUid === members.a ? members.b : members.a;
    if (!receiverUid || receiverUid === updatedByUid) return;

    const title = (after.title ?? 'Công việc').toString();

    const beforeCompleted = !!before.completed;
    const afterCompleted = !!after.completed;

    if (beforeCompleted !== afterCompleted) {
      const notificationId = (event as any).id?.toString?.() ?? `${channelId}_${event.params.taskId}_changed`;
      const body = afterCompleted ? `Đã hoàn thành: ${title}` : `Chưa hoàn thành: ${title}`;

      await createUserNotification(receiverUid, notificationId, {
        type: 'task',
        title: 'Cập nhật công việc',
        body,
        channelId,
        taskId: event.params.taskId as string,
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
          taskId: event.params.taskId as string,
          event: afterCompleted ? 'completed' : 'uncompleted',
        },
      });
    }
  },
);

export const notifyTaskCreated = onDocumentCreated(
  'channels/{channelId}/tasks/{taskId}',
  async (event) => {
    const channelId = event.params.channelId as string;
    const members = parseChannelMembers(channelId);
    if (!members) return;

    const data = event.data?.data();
    if (!data) return;

    const createdByUid = (data.createdByUid ?? data.updatedByUid ?? '').toString();
    const receiverUid = createdByUid === members.a ? members.b : members.a;
    if (!receiverUid || receiverUid === createdByUid) return;

    const title = (data.title ?? 'Công việc').toString();

    const notificationId = (event as any).id?.toString?.() ?? `${channelId}_${event.params.taskId}_created`;
    await createUserNotification(receiverUid, notificationId, {
      type: 'task',
      title: 'Công việc mới',
      body: title,
      channelId,
      taskId: event.params.taskId as string,
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
        taskId: event.params.taskId as string,
        event: 'created',
      },
    });
  },
);

export const mirrorChildPhoneToParent = onDocumentUpdated('users/{uid}', async (event) => {
  const uid = event.params.uid as string;
  const before = event.data?.before.data() ?? {};
  const after = event.data?.after.data() ?? {};

  const role = (after.role ?? '').toString();
  if (role !== 'child') return;

  const parentUid = (after.parentUid ?? '').toString();
  if (!parentUid || parentUid === uid) return;

  const childPhone = (after.phone ?? '').toString().trim();
  if (!childPhone) return;

  const parentPhone = (after.parentPhone ?? '').toString().trim();

  const beforePhone = (before.phone ?? '').toString().trim();
  const beforeParentUid = (before.parentUid ?? '').toString();
  const beforeParentPhone = (before.parentPhone ?? '').toString().trim();

  // Skip if nothing relevant changed.
  if (
    beforePhone === childPhone &&
    beforeParentUid === parentUid &&
    beforeParentPhone === parentPhone
  ) {
    return;
  }

  const parentRef = admin.firestore().collection('users').doc(parentUid);
  try {
    await admin.firestore().runTransaction(async (tx) => {
      const parentSnap = await tx.get(parentRef);
      const parentData = parentSnap.data() as any;
      const existingChildUid = (parentData?.childUid ?? '').toString().trim();
      const existingChildPhone = (parentData?.childPhone ?? '').toString().trim();

      const updates: Record<string, any> = {
        linkedChildUids: admin.firestore.FieldValue.arrayUnion(uid),
        childUid: uid,
        childPhone,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      const shouldRemoveOldPhone =
        existingChildUid === uid &&
        existingChildPhone.length > 0 &&
        existingChildPhone !== childPhone;

      if (shouldRemoveOldPhone) {
        tx.set(
          parentRef,
          {
            ...updates,
            linkedChildPhones: admin.firestore.FieldValue.arrayRemove(existingChildPhone),
          },
          { merge: true },
        );
      } else {
        tx.set(parentRef, updates, { merge: true });
      }

      tx.set(
        parentRef,
        {
          linkedChildPhones: admin.firestore.FieldValue.arrayUnion(childPhone),
        },
        { merge: true },
      );

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
  } catch (e: any) {
    console.warn('[functions] mirror child -> parent failed', {
      uid,
      parentUid,
      code: e?.code,
      message: e?.message,
    });
  }
});
