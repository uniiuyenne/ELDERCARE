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
  const senderUid = requiredEnv('TEST_SENDER_UID');

  const text = (process.env.TEST_TEXT || 'Test chat message').toString();

  const resolvedServiceAccountPath = path.isAbsolute(serviceAccountPath)
    ? serviceAccountPath
    : path.resolve(process.cwd(), serviceAccountPath);

  const serviceAccountJson = require(resolvedServiceAccountPath);
  admin.initializeApp({ credential: admin.credential.cert(serviceAccountJson) });

  const db = admin.firestore();
  db.settings({ ignoreUndefinedProperties: true });

  const now = admin.firestore.Timestamp.now();

  const ref = await db
    .collection('channels')
    .doc(channelId)
    .collection('chatMessages')
    .add({
      senderUid,
      text,
      createdAt: now,
    });

  console.log(
    JSON.stringify(
      {
        ok: true,
        action: 'chat_message_created',
        channelId,
        messageId: ref.id,
        senderUid,
        text,
        createdAtMillis: now.toMillis(),
      },
      null,
      2,
    ),
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
