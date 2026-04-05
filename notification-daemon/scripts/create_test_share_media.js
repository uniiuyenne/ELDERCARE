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

  const mediaType = (process.env.TEST_MEDIA_TYPE || 'image').toString().trim().toLowerCase();
  if (mediaType !== 'image' && mediaType !== 'video') {
    throw new Error('TEST_MEDIA_TYPE must be image or video');
  }

  const caption = (process.env.TEST_CAPTION || (mediaType === 'video' ? 'Test video caption' : 'Test image caption')).toString();

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
    .collection('Chat')
    .add({
      senderUid,
      mediaType,
      caption,
      createdAt: now,
    });

  console.log(
    JSON.stringify(
      {
        ok: true,
        action: 'share_media_created',
        channelId,
        mediaId: ref.id,
        senderUid,
        mediaType,
        caption,
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
