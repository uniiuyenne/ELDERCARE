/* eslint-disable no-console */

const admin = require('firebase-admin');
const path = require('node:path');

function requiredEnv(name) {
  const v = process.env[name];
  if (!v || !String(v).trim()) throw new Error(`Missing env ${name}`);
  return String(v).trim();
}

async function main() {
  const uid = requiredEnv('TEST_UID');
  const serviceAccountPath = requiredEnv('SERVICE_ACCOUNT_PATH');

  const resolvedServiceAccountPath = path.isAbsolute(serviceAccountPath)
    ? serviceAccountPath
    : path.resolve(process.cwd(), serviceAccountPath);

  const serviceAccountJson = require(resolvedServiceAccountPath);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccountJson),
  });

  const db = admin.firestore();
  db.settings({ ignoreUndefinedProperties: true });

  const channelsSnap = await db.collection('channels').get();
  const channelIds = channelsSnap.docs.map((d) => d.id).filter(Boolean);

  const channelId = channelIds.find((id) => {
    const parts = id.split('_');
    return parts.length === 2 && (parts[0] === uid || parts[1] === uid);
  });

  const chosenChannelId = channelId || `${uid}_${uid}`;
  if (!channelId) {
    await db.collection('channels').doc(chosenChannelId).set(
      {
        _createdByTest: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  const now = Date.now();
  const createdAtMillis = now - 2 * 60 * 1000;
  const scheduledAtMillis = now - 10 * 1000;

  const taskRef = db
    .collection('channels')
    .doc(chosenChannelId)
    .collection('tasks')
    .doc();

  await taskRef.set(
    {
      title: 'TEST overdue (auto)',
      note: 'Task test để kiểm tra nhắc nhở đến hạn',
      completed: false,
      createdByUid: uid,
      updatedByUid: uid,
      updatedByRole: 'child',
      createdAt: admin.firestore.Timestamp.fromMillis(createdAtMillis),
      scheduledAt: admin.firestore.Timestamp.fromMillis(scheduledAtMillis),
      updatedAt: admin.firestore.Timestamp.fromMillis(createdAtMillis),
    },
    { merge: true },
  );

  console.log(JSON.stringify({ ok: true, uid, chosenChannelId, taskId: taskRef.id, scheduledAtMillis }, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
