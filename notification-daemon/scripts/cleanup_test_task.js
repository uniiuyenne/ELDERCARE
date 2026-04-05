/* eslint-disable no-console */

const admin = require('firebase-admin');
const path = require('node:path');

function requiredEnv(name) {
  const v = process.env[name];
  if (!v || !String(v).trim()) throw new Error(`Missing env ${name}`);
  return String(v).trim();
}

async function main() {
  const serviceAccountPath = requiredEnv('SERVICE_ACCOUNT_PATH');
  const channelId = requiredEnv('TEST_CHANNEL_ID');
  const taskId = requiredEnv('TEST_TASK_ID');

  const resolvedServiceAccountPath = path.isAbsolute(serviceAccountPath)
    ? serviceAccountPath
    : path.resolve(process.cwd(), serviceAccountPath);

  const serviceAccountJson = require(resolvedServiceAccountPath);
  admin.initializeApp({ credential: admin.credential.cert(serviceAccountJson) });

  const db = admin.firestore();
  db.settings({ ignoreUndefinedProperties: true });

  const ref = db.collection('channels').doc(channelId).collection('tasks').doc(taskId);
  await ref.set(
    {
      completed: true,
      checkedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      _completedByTestCleanup: true,
    },
    { merge: true },
  );

  console.log(JSON.stringify({ ok: true, channelId, taskId, action: 'completed' }, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
