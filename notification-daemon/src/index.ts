import 'dotenv/config';

import * as admin from 'firebase-admin';
import * as path from 'node:path';

type NotificationType = 'chat' | 'task';

const startedAtMillis = Date.now();
const taskCompletedCache = new Map<string, boolean>();
const userRoleCache = new Map<string, { role: string; cachedAtMillis: number }>();
const userMirrorCache = new Map<
  string,
  {
    phone: string;
    parentPhone: string;
    parentUid: string;
    updatedAtMillis: number | null;
  }
>();

const USER_ROLE_CACHE_TTL_MILLIS = 5 * 60_000;

function requiredEnv(name: string): string {
  const v = process.env[name];
  if (!v || !v.trim()) {
    throw new Error(`Missing required env ${name}. See notification-daemon/README.md`);
  }
  return v.trim();
}

function parseChannelMembers(channelId: string): { a: string; b: string } | null {
  const parts = channelId.split('_');
  if (parts.length !== 2) return null;
  if (!parts[0] || !parts[1]) return null;
  return { a: parts[0], b: parts[1] };
}

function getOtherMember(channelId: string, senderUid: string): string | null {
  const members = parseChannelMembers(channelId);
  if (!members) return null;
  if (senderUid === members.a) return members.b;
  if (senderUid === members.b) return members.a;
  return null;
}

function safeString(v: unknown): string {
  if (v == null) return '';
  return String(v);
}

function truncate(text: string, maxLen: number): string {
  if (text.length <= maxLen) return text;
  return `${text.slice(0, maxLen)}…`;
}

function toMillisMaybe(ts: any): number | null {
  try {
    if (ts?.toMillis?.()) return ts.toMillis();
  } catch (_) {
    // ignore
  }
  return null;
}

async function mirrorChildProfileToParent(params: {
  childUid: string;
  childPhone: string;
  parentUid: string;
  parentPhone: string;
}) {
  const { childUid, childPhone, parentUid, parentPhone } = params;
  if (!childUid || !parentUid || childUid === parentUid) return;
  if (!childPhone.trim()) return;

  const parentRef = admin.firestore().collection('users').doc(parentUid);
  const newChildPhone = childPhone.trim();
  const newParentPhone = parentPhone.trim();

  await admin.firestore().runTransaction(async (tx) => {
    const parentSnap = await tx.get(parentRef);
    const parentData = parentSnap.data() as any;

    // Best-effort cleanup: if this parent doc currently points to this childUid,
    // remove the previous childPhone from the linkedChildPhones array.
    const existingChildUid = safeString(parentData?.childUid).trim();
    const existingChildPhone = safeString(parentData?.childPhone).trim();

    const rawLinkedChildUids = parentData?.linkedChildUids;
    const linkedChildUids = Array.isArray(rawLinkedChildUids)
      ? rawLinkedChildUids.map((x: any) => safeString(x).trim()).filter(Boolean)
      : [];
    const uniqueLinkedChildUids = Array.from(new Set(linkedChildUids));

    // If this parent is linked to exactly this child, overwrite the arrays
    // to keep only the latest phone and avoid accumulating stale numbers.
    const isSingleChildLink = uniqueLinkedChildUids.length === 1 && uniqueLinkedChildUids[0] === childUid;
    const isLegacySingleChildLink = uniqueLinkedChildUids.length === 0 && existingChildUid === childUid;
    if (isSingleChildLink || isLegacySingleChildLink) {
      tx.set(
        parentRef,
        {
          linkedChildUids: [childUid],
          linkedChildPhones: [newChildPhone],
          childUid: childUid,
          childPhone: newChildPhone,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...(newParentPhone ? { phone: newParentPhone } : {}),
        },
        { merge: true },
      );
      return;
    }
    const shouldRemoveOldPhone =
      existingChildUid === childUid &&
      existingChildPhone.length > 0 &&
      existingChildPhone !== newChildPhone;

    const updates: Record<string, any> = {
      linkedChildUids: admin.firestore.FieldValue.arrayUnion(childUid),
      linkedChildPhones: admin.firestore.FieldValue.arrayUnion(newChildPhone),
      childUid: childUid,
      childPhone: newChildPhone,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (shouldRemoveOldPhone) {
      updates.linkedChildPhones = admin.firestore.FieldValue.arrayRemove(existingChildPhone);
      // Apply remove then add in two operations.
      tx.set(parentRef, updates, { merge: true });
      tx.set(
        parentRef,
        {
          linkedChildPhones: admin.firestore.FieldValue.arrayUnion(newChildPhone),
        },
        { merge: true },
      );
    } else {
      tx.set(parentRef, updates, { merge: true });
    }

    if (newParentPhone) {
      tx.set(parentRef, { phone: newParentPhone }, { merge: true });
    }
  });
}

async function getUserRole(uid: string): Promise<string> {
  const now = Date.now();
  const cached = userRoleCache.get(uid);
  if (cached && now - cached.cachedAtMillis < USER_ROLE_CACHE_TTL_MILLIS) {
    return cached.role;
  }

  const doc = await admin.firestore().collection('users').doc(uid).get();
  const role = safeString(doc.data()?.role).trim();
  userRoleCache.set(uid, { role, cachedAtMillis: now });
  return role;
}

async function resolveParentChildUids(channelId: string): Promise<{ parentUid: string | null; childUid: string | null }> {
  const members = parseChannelMembers(channelId);
  if (!members) return { parentUid: null, childUid: null };

  const [roleA, roleB] = await Promise.all([getUserRole(members.a), getUserRole(members.b)]);
  const parentUid = roleA === 'parent' ? members.a : roleB === 'parent' ? members.b : null;
  const childUid = roleA === 'child' ? members.a : roleB === 'child' ? members.b : null;
  return { parentUid, childUid };
}

async function getUserTokens(uid: string): Promise<string[]> {
  const snap = await admin.firestore().collection('users').doc(uid).collection('fcmTokens').get();
  const tokens: string[] = [];
  for (const doc of snap.docs) {
    const data = doc.data();
    const token = safeString((data as any).token || doc.id).trim();
    if (token) tokens.push(token);
  }
  return tokens;
}

async function createUserNotificationIfAbsent(
  uid: string,
  notificationId: string,
  data: {
    type: NotificationType;
    title: string;
    body: string;
    channelId: string;
    senderUid?: string;
    taskId?: string;
    messageId?: string;
    event?: string;
  },
): Promise<boolean> {
  const ref = admin.firestore().collection('users').doc(uid).collection('notifications').doc(notificationId);

  try {
    // Use create() for idempotency (fails if doc exists).
    await ref.create({
      ...data,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  } catch (e: any) {
    // Already exists -> skip to avoid duplicate push.
    const code = safeString(e?.code);
    if (code.includes('already-exists') || code.includes('ALREADY_EXISTS')) {
      return false;
    }

    // Some SDK versions throw with numeric status.
    const msg = safeString(e?.message);
    if (msg.toLowerCase().includes('already exists')) {
      return false;
    }

    throw e;
  }
}

async function sendToUser(
  uid: string,
  payload: { title: string; body: string; data?: Record<string, string> },
): Promise<{ tokenCount: number; successCount: number; failureCount: number } | null> {
  const tokens = await getUserTokens(uid);
  if (tokens.length === 0) {
    console.warn('[daemon] push skipped (no tokens)', { uid });
    return null;
  }

  const res = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title: payload.title,
      body: payload.body,
    },
    data: payload.data,
    android: {
      priority: 'high',
      notification: {
        channelId: 'chat_and_tasks_v4',
      },
    },
    apns: {
      payload: { aps: { sound: 'default' } },
    },
  });

  try {
    if (res.failureCount > 0) {
      const errors = res.responses
        .map((r, idx) => ({
          ok: r.success,
          idx,
          code: safeString((r.error as any)?.code),
          msg: safeString((r.error as any)?.message),
        }))
        .filter((x) => !x.ok)
        .slice(0, 5);

      console.warn('[daemon] push send result', {
        uid,
        tokenCount: tokens.length,
        successCount: res.successCount,
        failureCount: res.failureCount,
        sampleErrors: errors,
      });
    } else {
      console.log('[daemon] push sent', { uid, tokenCount: tokens.length, successCount: res.successCount });
    }
  } catch (_) {
    // ignore
  }

  const tokensToDelete: string[] = [];
  res.responses.forEach((r, idx) => {
    if (r.success) return;
    const code = safeString((r.error as any)?.code);
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

  return {
    tokenCount: tokens.length,
    successCount: res.successCount,
    failureCount: res.failureCount,
  };
}

function extractChannelIdFromDocPath(path: string): { channelId: string; docId: string } | null {
  // Expected paths:
  // - channels/<channelId>/chatMessages/<messageId>
  // - channels/<channelId>/tasks/<taskId>
  // - channels/<channelId>/Chat/<mediaId>
  const parts = path.split('/');
  if (parts.length < 4) return null;
  if (parts[0] !== 'channels') return null;
  const channelId = parts[1];
  const docId = parts[3];
  if (!channelId || !docId) return null;
  return { channelId, docId };
}

const ensuredChannelDocs = new Set<string>();

async function ensureChannelDocExists(channelId: string) {
  if (!channelId) return;
  if (ensuredChannelDocs.has(channelId)) return;
  ensuredChannelDocs.add(channelId);

  try {
    await admin
      .firestore()
      .collection('channels')
      .doc(channelId)
      .set(
        {
          _indexedByDaemon: true,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
  } catch (_) {
    // ignore
  }
}

async function handleShareMediaAdded(change: admin.firestore.DocumentChange<admin.firestore.DocumentData>) {
  const ref = change.doc.ref;
  const parsed = extractChannelIdFromDocPath(ref.path);
  if (!parsed) return;

  const { channelId, docId: mediaId } = parsed;
  const data = change.doc.data();

  const senderUid = safeString((data as any).senderUid).trim();
  if (!senderUid) return;

  // Avoid spamming historical media when the daemon starts.
  const createdAt = (data as any).createdAt;
  const createdMillis = createdAt?.toMillis?.()
    ? createdAt.toMillis()
    : (change.doc as any)?.createTime?.toMillis?.()
      ? (change.doc as any).createTime.toMillis()
      : null;
  if (createdMillis != null && createdMillis < startedAtMillis - 60_000) {
    return;
  }

  const receiverUid = getOtherMember(channelId, senderUid);
  if (!receiverUid) return;

  const mediaType = safeString((data as any).mediaType).trim().toLowerCase();
  const caption = safeString((data as any).caption).trim();

  const title = mediaType == 'video' ? 'Video mới' : 'Ảnh mới';
  const body = truncate(caption.length > 0 ? caption : 'Bạn nhận được một tệp đa phương tiện', 140);

  const notificationId = `${channelId}_chat_media_${mediaId}`;
  const created = await createUserNotificationIfAbsent(receiverUid, notificationId, {
    type: 'chat',
    title,
    body,
    channelId,
    senderUid,
    messageId: mediaId,
    event: mediaType == 'video' ? 'media_video' : 'media_image',
  });

  if (!created) return;

  console.log('[daemon] media -> inbox+push', { channelId, mediaId, senderUid, receiverUid, notificationId, mediaType });

  await sendToUser(receiverUid, {
    title,
    body,
    data: {
      type: 'chat',
      channelId,
      inboxId: notificationId,
      messageId: mediaId,
      senderUid,
      mediaType: mediaType == 'video' ? 'video' : 'image',
    },
  });
}

async function handleChatAdded(change: admin.firestore.DocumentChange<admin.firestore.DocumentData>) {
  const ref = change.doc.ref;
  const parsed = extractChannelIdFromDocPath(ref.path);
  if (!parsed) return;

  const { channelId, docId: messageId } = parsed;
  const data = change.doc.data();

  const senderUid = safeString((data as any).senderUid).trim();
  if (!senderUid) return;

  // Avoid spamming historical messages when the daemon starts.
  const createdAt = (data as any).createdAt;
  const createdMillis = createdAt?.toMillis?.()
    ? createdAt.toMillis()
    : (change.doc as any)?.createTime?.toMillis?.()
      ? (change.doc as any).createTime.toMillis()
      : null;
  if (createdMillis != null && createdMillis < startedAtMillis - 60_000) {
    return;
  }

  const receiverUid = getOtherMember(channelId, senderUid);
  if (!receiverUid) return;

  const text = safeString((data as any).text);
  const snippet = truncate(text, 140);

  const notificationId = `${channelId}_chat_${messageId}`;
  const created = await createUserNotificationIfAbsent(receiverUid, notificationId, {
    type: 'chat',
    title: 'Tin nhắn mới',
    body: snippet,
    channelId,
    senderUid,
    messageId,
  });

  if (!created) return;

  console.log('[daemon] chat -> inbox+push', {
    channelId,
    messageId,
    senderUid,
    receiverUid,
    notificationId,
  });

  await sendToUser(receiverUid, {
    title: 'Tin nhắn mới',
    body: snippet,
    data: {
      type: 'chat',
      channelId,
      inboxId: notificationId,
      messageId,
      senderUid,
    },
  });
}

async function handleTaskCreated(change: admin.firestore.DocumentChange<admin.firestore.DocumentData>) {
  const ref = change.doc.ref;
  const parsed = extractChannelIdFromDocPath(ref.path);
  if (!parsed) return;

  const { channelId, docId: taskId } = parsed;
  const data = change.doc.data();

  taskCompletedCache.set(ref.path, (data as any).completed === true);

  // Avoid backfilling historical tasks when the daemon starts.
  const createdAt = (data as any).createdAt;
  const createdMillis = createdAt?.toMillis?.()
    ? createdAt.toMillis()
    : (change.doc as any)?.createTime?.toMillis?.()
      ? (change.doc as any).createTime.toMillis()
      : (change.doc as any)?.updateTime?.toMillis?.()
        ? (change.doc as any).updateTime.toMillis()
        : null;
  if (createdMillis != null && createdMillis < startedAtMillis - 60_000) {
    taskCompletedCache.set(ref.path, (data as any).completed === true);
    return;
  }

  const createdByUid = safeString((data as any).createdByUid || (data as any).updatedByUid).trim();
  if (!createdByUid) return;

  // Rule: New task notification is for Parent only.
  // Prefer resolving roles from user docs to avoid accidentally notifying Child.
  const resolved = await resolveParentChildUids(channelId);
  const receiverUid = resolved.parentUid || getOtherMember(channelId, createdByUid);
  if (!receiverUid) return;
  // If the Parent created the task, do not notify (avoid self-notify).
  if (receiverUid === createdByUid) return;

  const title = safeString((data as any).title || 'Công việc');

  const notificationId = `${channelId}_task_${taskId}_created`;
  const created = await createUserNotificationIfAbsent(receiverUid, notificationId, {
    type: 'task',
    title: 'Công việc mới',
    body: title,
    channelId,
    senderUid: createdByUid,
    taskId,
    event: 'created',
  });

  if (!created) return;

  console.log('[daemon] task created -> inbox+push', { channelId, taskId, createdByUid, receiverUid, notificationId });

  await sendToUser(receiverUid, {
    title: 'Công việc mới',
    body: title,
    data: {
      type: 'task',
      channelId,
      taskId,
      inboxId: notificationId,
      senderUid: createdByUid,
      event: 'created',
    },
  });
}

async function handleTaskModified(change: admin.firestore.DocumentChange<admin.firestore.DocumentData>) {
  const ref = change.doc.ref;
  const parsed = extractChannelIdFromDocPath(ref.path);
  if (!parsed) return;

  const { channelId, docId: taskId } = parsed;
  const data = change.doc.data();

  // Only notify when completion flips.
  const completed = (data as any).completed === true;
  const prevCompleted = taskCompletedCache.get(ref.path);
  taskCompletedCache.set(ref.path, completed);

  // First time seeing this task in this daemon session: do not notify.
  if (prevCompleted === undefined) {
    return;
  }

  if (prevCompleted === completed) {
    return;
  }

  // Rule: Only notify when task becomes completed.
  if (!completed) {
    return;
  }

  const updatedByUid = safeString((data as any).updatedByUid).trim();
  if (!updatedByUid) return;

  const updatedByRole = safeString((data as any).updatedByRole).trim().toLowerCase();
  // Rule: Completion notification is only when Parent completes.
  if (updatedByRole && updatedByRole !== 'parent') {
    return;
  }

  // Rule: Completed notification goes to Child.
  const resolved = await resolveParentChildUids(channelId);
  const receiverUid = resolved.childUid || getOtherMember(channelId, updatedByUid);
  if (!receiverUid) return;
  if (receiverUid === updatedByUid) return;

  const checkedAt = (data as any).checkedAt;
  const updatedAt = (data as any).updatedAt;

  const title = safeString((data as any).title || 'Công việc');
  const body = `Đã hoàn thành: ${title}`;

  // Use updatedAt/checkedAt if present to make event id unique per toggle.
  const eventMillis =
    updatedAt?.toMillis?.() ? updatedAt.toMillis() : checkedAt?.toMillis?.() ? checkedAt.toMillis() : Date.now();
  const notificationId = `${channelId}_task_${taskId}_completed_${eventMillis}`;

  const created = await createUserNotificationIfAbsent(receiverUid, notificationId, {
    type: 'task',
    title: 'Công việc đã hoàn thành',
    body,
    channelId,
    senderUid: updatedByUid,
    taskId,
    event: 'completed',
  });

  if (!created) return;

  console.log('[daemon] task completed -> inbox+push', { channelId, taskId, updatedByUid, receiverUid, notificationId });

  await sendToUser(receiverUid, {
    title: 'Công việc đã hoàn thành',
    body,
    data: {
      type: 'task',
      channelId,
      taskId,
      inboxId: notificationId,
      senderUid: updatedByUid,
      event: 'completed',
    },
  });
}

async function scanOverdueTasksOnce() {
  const scanStartedAt = Date.now();
  const nowMillis = scanStartedAt;
  const nowTs = admin.firestore.Timestamp.fromMillis(nowMillis);

  // Avoid spamming the same device/user when many tasks are overdue.
  // Android may automatically mute/demote noisy apps/channels.
  const pushedUidThisScan = new Set<string>();

  let channelCount = 0;
  let channelQueryFailed = 0;
  let taskDocsChecked = 0;
  let overdueTasksFound = 0;

  let pushAttempts = 0;
  let pushSuccess = 0;
  let pushSkippedNoTokens = 0;
  let pushAlreadySent = 0;

  console.log('[daemon] overdue scan start', { nowMillis });

  const channelsSnap = await admin.firestore().collection('channels').get();
  channelCount = channelsSnap.size;

  if (channelCount === 0) {
    console.warn('[daemon] overdue scan skipped: no channels docs found');
    console.log('[daemon] overdue scan done', {
      durationMs: Date.now() - scanStartedAt,
      channelCount,
      channelQueryFailed,
      taskDocsChecked,
      overdueTasksFound,
      pushAttempts,
      pushSuccess,
      pushSkippedNoTokens,
      pushAlreadySent,
    });
    return;
  }

  for (const channelDoc of channelsSnap.docs) {
    const channelId = channelDoc.id;
    if (!channelId) continue;

    let snap: admin.firestore.QuerySnapshot<admin.firestore.DocumentData>;
    try {
      snap = await admin
        .firestore()
        .collection('channels')
        .doc(channelId)
        .collection('tasks')
        .where('scheduledAt', '<=', nowTs)
        .orderBy('scheduledAt', 'desc')
        .limit(50)
        .get();
    } catch (e: any) {
      channelQueryFailed++;
      console.warn('[daemon] overdue scan channel query failed', {
        channelId,
        err: safeString(e?.message || e),
      });
      continue;
    }

    for (const doc of snap.docs) {
      const taskId = doc.id;
      const data = doc.data();

      taskDocsChecked++;
      if ((data as any).completed === true) continue;

      const scheduledAt = (data as any).scheduledAt;
      const scheduledMillis = scheduledAt?.toMillis?.() ? scheduledAt.toMillis() : null;
      if (scheduledMillis == null) continue;

      overdueTasksFound++;

      const titleText = safeString((data as any).title || 'Công việc');
      const notificationId = `${channelId}_task_${taskId}_overdue_${scheduledMillis}`;

      const members = parseChannelMembers(channelId);
      const resolved = await resolveParentChildUids(channelId);

      const recipients = new Set<string>();
      if (resolved.parentUid) recipients.add(resolved.parentUid);
      if (resolved.childUid) recipients.add(resolved.childUid);
      if (recipients.size === 0 && members) {
        recipients.add(members.a);
        recipients.add(members.b);
      }

      for (const uid of recipients) {
        const isParent = resolved.parentUid && uid === resolved.parentUid;
        const isChild = resolved.childUid && uid === resolved.childUid;

        const title = isParent
          ? 'Nhắc nhở công việc'
          : isChild
            ? 'Cha/Mẹ chưa hoàn thành'
            : 'Công việc đến hạn';

        const body = isParent
          ? `Đến giờ, vui lòng hoàn thành: ${titleText}`
          : isChild
            ? `Công việc đến giờ nhưng Cha/Mẹ chưa hoàn thành: ${titleText}`
            : `Đến hạn nhưng chưa hoàn thành: ${titleText}`;

        const notifRef = admin
          .firestore()
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .doc(notificationId);

        const deliveryRef = admin
          .firestore()
          .collection('channels')
          .doc(channelId)
          .collection('tasks')
          .doc(taskId)
          .collection('overdueDeliveries')
          .doc(`${scheduledMillis}_${uid}`);

        // If we've already successfully delivered this overdue reminder, do not
        // recreate the user's inbox item or resend push (even if they deleted it).
        try {
          const delivered = await deliveryRef.get();
          if (delivered.exists) {
            pushAlreadySent++;
            continue;
          }
        } catch (_) {
          // ignore
        }

        let pushSentAt: unknown = null;
        try {
          const existing = await notifRef.get();
          if (!existing.exists) {
            await notifRef.create({
              type: 'task',
              title,
              body,
              channelId,
              taskId,
              event: 'overdue',
              read: false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          } else {
            pushSentAt = (existing.data() as any)?.pushSentAt;
          }
        } catch (e: any) {
          const msg = safeString(e?.message);
          if (!msg.toLowerCase().includes('already exists')) {
            console.warn('[daemon] overdue inbox read/create failed', {
              uid,
              channelId,
              taskId,
              err: safeString(e?.message || e),
            });
          }
        }

        if (pushSentAt != null) {
          // Backfill delivery marker so deleting the inbox doc won't cause resend
          // for reminders delivered before we introduced overdueDeliveries.
          try {
            await deliveryRef.set(
              {
                uid,
                notificationId,
                pushedAt: pushSentAt,
              },
              { merge: true },
            );
          } catch (_) {
            // ignore
          }

          pushAlreadySent++;
          continue;
        }

        // Rate limit: at most one push per uid per scan.
        if (pushedUidThisScan.has(uid)) {
          try {
            await deliveryRef.set(
              {
                uid,
                notificationId,
                status: 'suppressed_rate_limit',
                attemptedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true },
            );
          } catch (_) {
            // ignore
          }
          continue;
        }

        pushedUidThisScan.add(uid);

        pushAttempts++;
        const result = await sendToUser(uid, {
          title,
          body,
          data: {
            type: 'task',
            channelId,
            taskId,
            inboxId: notificationId,
            event: 'overdue',
          },
        });

        if (result == null) {
          pushSkippedNoTokens++;
          // Persist delivery marker even when no tokens to prevent spam:
          // - scanner won't recreate inbox docs every minute
          // - user deletion won't cause the daemon to recreate old items
          try {
            await deliveryRef.set(
              {
                uid,
                notificationId,
                status: 'no_tokens',
                attemptedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true },
            );
          } catch (_) {
            // ignore
          }
          continue;
        }

        if (result != null && result.successCount > 0) {
          pushSuccess++;
          // Persist delivery marker in task subtree so deletion of inbox doc
          // cannot cause resend.
          try {
            await deliveryRef.set(
              {
                uid,
                notificationId,
                status: 'sent',
                pushedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true },
            );
          } catch (_) {
            // ignore
          }

          // Also mark the inbox doc for UX (idempotency within notifications list).
          try {
            await notifRef.set(
              { pushSentAt: admin.firestore.FieldValue.serverTimestamp() },
              { merge: true },
            );
          } catch (_) {
            // ignore
          }
        } else {
          // Push attempted but none succeeded (invalid tokens, etc).
          try {
            await deliveryRef.set(
              {
                uid,
                notificationId,
                status: 'failed',
                attemptedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true },
            );
          } catch (_) {
            // ignore
          }
        }
      }
    }
  }

  console.log('[daemon] overdue scan done', {
    durationMs: Date.now() - scanStartedAt,
    channelCount,
    channelQueryFailed,
    taskDocsChecked,
    overdueTasksFound,
    pushAttempts,
    pushSuccess,
    pushSkippedNoTokens,
    pushAlreadySent,
  });
}

async function scanRecentShareMediaOnce() {
  const sinceMillis = startedAtMillis - 60_000;
  const sinceTs = admin.firestore.Timestamp.fromMillis(sinceMillis);

  const channelsSnap = await admin.firestore().collection('channels').get();
  for (const channelDoc of channelsSnap.docs) {
    const channelId = channelDoc.id;
    if (!channelId) continue;

    const snap = await admin
      .firestore()
      .collection('channels')
      .doc(channelId)
      .collection('Chat')
      .where('createdAt', '>=', sinceTs)
      .orderBy('createdAt', 'desc')
      .limit(20)
      .get();

    for (const doc of snap.docs) {
      // Reuse the same logic as realtime handler (idempotent create() avoids duplicates).
      const fakeChange = {
        doc,
      } as unknown as admin.firestore.DocumentChange<admin.firestore.DocumentData>;

      try {
        await handleShareMediaAdded(fakeChange);
      } catch (e) {
        console.error('[daemon] sharebox scan handler failed:', e);
      }
    }
  }
}

async function main() {
  const serviceAccountPath = requiredEnv('SERVICE_ACCOUNT_PATH');

  const resolvedServiceAccountPath = path.isAbsolute(serviceAccountPath)
    ? serviceAccountPath
    : path.resolve(process.cwd(), serviceAccountPath);

  // NOTE: Keep the service account file OUT of git.
  // This daemon will run with admin privileges.
  const serviceAccountJson = require(resolvedServiceAccountPath);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccountJson),
  });

  try {
    const projectId = safeString(serviceAccountJson?.project_id || admin.app().options.projectId);
    console.log('[daemon] firebase initialized', { projectId });
  } catch (_) {
    // ignore
  }

  const db = admin.firestore();
  db.settings({ ignoreUndefinedProperties: true });

  // Optional: quick one-off push test.
  // Usage:
  //   TEST_PUSH_UID=<uid> TEST_PUSH_TITLE="Hello" TEST_PUSH_BODY="World" npm start
  const testUid = safeString(process.env.TEST_PUSH_UID).trim();
  if (testUid) {
    const title = safeString(process.env.TEST_PUSH_TITLE).trim() || 'Test push';
    const body = safeString(process.env.TEST_PUSH_BODY).trim() || 'Đây là thông báo test từ notification-daemon';
    console.log('[daemon] sending TEST push', { uid: testUid, title });

    // Also write an inbox item so the in-app notification panel shows data.
    try {
      const nowMillis = Date.now();
      const notificationId = `test_${nowMillis}`;
      await createUserNotificationIfAbsent(testUid, notificationId, {
        type: 'chat',
        title,
        body,
        channelId: `test_${testUid}`,
        event: 'test',
      });
      console.log('[daemon] TEST inbox written', { uid: testUid, notificationId });
    } catch (e) {
      console.warn('[daemon] TEST inbox write failed', { uid: testUid, err: safeString((e as any)?.message || e) });
    }

    await sendToUser(testUid, {
      title,
      body,
      data: {
        type: 'test',
        event: 'test',
      },
    });
    console.log('[daemon] TEST push done; exiting');
    process.exit(0);
  }

  console.log('[daemon] started. listening for chatMessages/Chat/tasks...');

  const enableUserMirror = safeString(process.env.ENABLE_USER_MIRROR).trim().toLowerCase() !== 'false';
  if (enableUserMirror) {
    console.log('[daemon] user mirror enabled (child -> parent)');

    admin
      .firestore()
      .collection('users')
      .where('role', '==', 'child')
      .onSnapshot(
        async (snapshot) => {
          const changes = snapshot.docChanges();
          for (const c of changes) {
            if (c.type !== 'added' && c.type !== 'modified') continue;

            const uid = c.doc.id;
            const data = c.doc.data() as any;

            const phone = safeString(data?.phone).trim();
            const parentPhone = safeString(data?.parentPhone).trim();
            const parentUid = safeString(data?.parentUid).trim();
            const updatedAtMillis = toMillisMaybe(data?.updatedAt);

            const prev = userMirrorCache.get(uid);
            userMirrorCache.set(uid, { phone, parentPhone, parentUid, updatedAtMillis });

            const isFirstSeen = !prev;
            const updatedAtChanged =
              !!prev && prev.updatedAtMillis != null && updatedAtMillis != null && prev.updatedAtMillis !== updatedAtMillis;
            const changed =
              !prev ||
              prev.phone !== phone ||
              prev.parentPhone !== parentPhone ||
              prev.parentUid !== parentUid ||
              updatedAtChanged;
            if (!changed) continue;

            // Avoid backfilling old profiles when the daemon starts.
            // But if a child's profile was updated very recently (e.g. user just saved phone)
            // and the daemon starts after that, we still want to mirror it.
            const isRecentUpdate = updatedAtMillis != null && updatedAtMillis >= startedAtMillis - 60_000;
            if (updatedAtMillis != null && updatedAtMillis < startedAtMillis - 60_000) {
              // Only allow mirroring on first-seen if it was updated recently.
              if (!isFirstSeen) {
                continue;
              }
              if (!isRecentUpdate) {
                continue;
              }
            }

            if (!parentUid || !phone) continue;

            try {
              await mirrorChildProfileToParent({
                childUid: uid,
                childPhone: phone,
                parentUid,
                parentPhone,
              });
              console.log('[daemon] mirror child -> parent', { uid, parentUid, childPhone: phone, parentPhone });
            } catch (e: any) {
              console.warn('[daemon] mirror child -> parent failed', {
                uid,
                parentUid,
                err: safeString(e?.message || e),
              });
            }
          }
        },
        (err) => {
          console.error('[daemon] user mirror onSnapshot error:', err);
        },
      );
  } else {
    console.log('[daemon] user mirror disabled via ENABLE_USER_MIRROR=false');
  }

  // Chat messages: only process newly-added messages.
  admin
    .firestore()
    .collectionGroup('chatMessages')
    .onSnapshot(
      async (snapshot) => {
        const changes = snapshot.docChanges();
        for (const c of changes) {
          if (c.type !== 'added') continue;
          try {
            await handleChatAdded(c);
          } catch (e) {
            console.error('[daemon] chat handler failed:', e);
          }
        }
      },
      (err) => {
        console.error('[daemon] chat onSnapshot error:', err);
      },
    );

  // ShareBox media: only process newly-added media docs.
  admin
    .firestore()
    .collectionGroup('Chat')
    .onSnapshot(
      async (snapshot) => {
        const changes = snapshot.docChanges();
        for (const c of changes) {
          if (c.type !== 'added') continue;
          try {
            await handleShareMediaAdded(c);
          } catch (e) {
            console.error('[daemon] sharebox handler failed:', e);
          }
        }
      },
      (err) => {
        console.error('[daemon] sharebox onSnapshot error:', err);
      },
    );

  // Tasks: notify on create + on completion updates.
  admin
    .firestore()
    .collectionGroup('tasks')
    .onSnapshot(
      async (snapshot) => {
        const changes = snapshot.docChanges();
        for (const c of changes) {
          try {
            const parsed = extractChannelIdFromDocPath(c.doc.ref.path);
            if (parsed?.channelId) {
              await ensureChannelDocExists(parsed.channelId);
            }

            if (c.type === 'added') {
              await handleTaskCreated(c);
            } else if (c.type === 'modified') {
              await handleTaskModified(c);
            }
          } catch (e) {
            console.error('[daemon] task handler failed:', e);
          }
        }
      },
      (err) => {
        console.error('[daemon] task onSnapshot error:', err);
      },
    );

  // Overdue scanner: notify both Parent + Child when a task is due but not completed.
  const overdueIntervalMillis = 60_000;
  let overdueScanInProgress = false;
  const runOverdueScan = async () => {
    if (overdueScanInProgress) {
      console.warn('[daemon] overdue scan skipped (already running)');
      return;
    }
    overdueScanInProgress = true;
    try {
      await scanOverdueTasksOnce();
    } catch (e) {
      console.error('[daemon] overdue scan failed:', e);
    } finally {
      overdueScanInProgress = false;
    }
  };

  // Media scan: ensures ShareBox image/video notifications are present in bell inbox.
  const mediaIntervalMillis = 60_000;
  const runMediaScan = async () => {
    try {
      await scanRecentShareMediaOnce();
    } catch (e) {
      console.error('[daemon] media scan failed:', e);
    }
  };

  // Run once on startup, then every minute.
  void runOverdueScan();
  setInterval(() => {
    void runOverdueScan();
  }, overdueIntervalMillis);

  void runMediaScan();
  setInterval(() => {
    void runMediaScan();
  }, mediaIntervalMillis);

  // Keep process alive.
  // eslint-disable-next-line @typescript-eslint/no-empty-function
  await new Promise<void>(() => {});
}

main().catch((e) => {
  console.error('[daemon] fatal:', e);
  process.exit(1);
});
