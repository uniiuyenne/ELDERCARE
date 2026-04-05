/*
  Cleanup script for E2E chat/media push tests.

  Deletes the specific Firestore documents created by:
  - scripts/create_test_chat_message.js
  - scripts/create_test_share_media.js

  It also deletes the corresponding in-app inbox docs under users/<uid>/notifications/*
  that the notification-daemon creates.

  Usage:
    node scripts/cleanup_e2e_chat_media_tests.js

  Notes:
  - This is intentionally narrow/safe: it deletes only the hard-coded IDs.
  - If the docs are already gone, deletes are no-ops.
*/

const admin = require('firebase-admin');

function requireServiceAccount() {
  // Prefer env var if provided; fall back to repo secret path used elsewhere.
  const fallback = 'g:/cnweb/ELDERCARE (1)/ELDERCARE/secrets/serviceAccount-careelder.json';
  const serviceAccountPath = process.env.SERVICE_ACCOUNT_PATH || fallback;
  // eslint-disable-next-line import/no-dynamic-require, global-require
  return require(serviceAccountPath);
}

async function main() {
  if (admin.apps.length === 0) {
    admin.initializeApp({
      credential: admin.credential.cert(requireServiceAccount()),
    });
  }

  const db = admin.firestore();
  db.settings({ ignoreUndefinedProperties: true });

  const channelId = 'YLAuu7AFzlbiJSFpywgr9WnIKja2_epzh5qK4MqNQFxXfGqZ56Iqlrzb2';
  const receiverUid = 'epzh5qK4MqNQFxXfGqZ56Iqlrzb2';

  const chatMessageId = 'NFxDot9Ytp145DdvNErH';
  const imageMediaId = 'U9Nw8RBDUdDRgUSrw7Dp';
  const videoMediaId = 'a1wfvLO3kStcQ5cEQhwo';

  const deletes = [
    db.collection('channels').doc(channelId).collection('chatMessages').doc(chatMessageId).delete(),
    db.collection('channels').doc(channelId).collection('Chat').doc(imageMediaId).delete(),
    db.collection('channels').doc(channelId).collection('Chat').doc(videoMediaId).delete(),

    db
      .collection('users')
      .doc(receiverUid)
      .collection('notifications')
      .doc(`${channelId}_chat_${chatMessageId}`)
      .delete(),
    db
      .collection('users')
      .doc(receiverUid)
      .collection('notifications')
      .doc(`${channelId}_chat_media_${imageMediaId}`)
      .delete(),
    db
      .collection('users')
      .doc(receiverUid)
      .collection('notifications')
      .doc(`${channelId}_chat_media_${videoMediaId}`)
      .delete(),
  ];

  const results = await Promise.allSettled(deletes);
  const summary = results.reduce(
    (acc, r) => {
      if (r.status === 'fulfilled') acc.fulfilled += 1;
      else acc.rejected += 1;
      return acc;
    },
    { fulfilled: 0, rejected: 0 }
  );

  // eslint-disable-next-line no-console
  console.log(
    JSON.stringify(
      {
        ok: summary.rejected === 0,
        attempted: results.length,
        ...summary,
      },
      null,
      2
    )
  );

  if (summary.rejected > 0) process.exitCode = 1;
}

main().catch((e) => {
  // eslint-disable-next-line no-console
  console.error(e);
  process.exit(1);
});
