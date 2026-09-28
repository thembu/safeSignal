// functions/send_escalation_email.js
//
// Sends ONE consolidated email to trusted contacts after a session
// transitions to escalated. Polls the evidence subcollection every few
// seconds for up to POLL_MAX_MS, then sends whatever is present (or an
// empty notice if nothing arrived).
//
// functions/.env:
//   GMAIL_USER=youremail@gmail.com
//   GMAIL_APP_PASSWORD=xxxxxxxxxxxxxxxx    (App Password, not real password)
//   GMAIL_FROM_NAME=SafeSignal
//
// In functions/index.js:
//   exports.sendEscalationEmail =
//     require('./send_escalation_email').sendEscalationEmail;

const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// Wait at least this long before the first check — gives the client
// time to start writing evidence.
const POLL_INITIAL_MS = 15 * 1000;
// Check every this-many ms after the initial wait.
const POLL_INTERVAL_MS = 10 * 1000;
// Give up polling after this total elapsed time from escalation.
const POLL_MAX_MS = 120 * 1000;
// If the evidence count is stable for this long AND we have at least
// one item, assume capture is done and send early.
const STABLE_MS = 15 * 1000;
// Expected artefacts on a good run (3 back + 3 front photos, 1 audio,
// 1 video). If we hit this many we send immediately.
const EXPECTED_COUNT = 8;

let transporter = null;
function getTransporter() {
  if (transporter) return transporter;
  const user = process.env.GMAIL_USER;
  const pass = process.env.GMAIL_APP_PASSWORD;
  if (!user || !pass) throw new Error('Missing GMAIL_USER or GMAIL_APP_PASSWORD');
  const nodemailer = require('nodemailer');
  transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: { user, pass },
  });
  return transporter;
}

exports.sendEscalationEmail = onDocumentUpdated(
  {
    document: 'users/{uid}/sessions/{sessionId}',
    region: 'us-central1',
    timeoutSeconds: 300, // must exceed POLL_MAX_MS + send time
  },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    const { uid, sessionId } = event.params;

    if (before.status === 'escalated' || after.status !== 'escalated') return;
    if (after.emailSentAt) return;

    logger.info(`Escalation for ${sessionId} (uid=${uid}) — polling for evidence…`);

    const sessionRef = db.doc(`users/${uid}/sessions/${sessionId}`);
    const evidenceCol = db.collection(`users/${uid}/sessions/${sessionId}/evidence`);

    // Poll for evidence.
    const startedAt = Date.now();
    let evidence = [];
    let lastCount = -1;
    let lastChangeAt = Date.now();

    await sleep(POLL_INITIAL_MS);

    while (Date.now() - startedAt < POLL_MAX_MS) {
      const snap = await evidenceCol.get();
      evidence = [];
      snap.forEach((doc) => evidence.push(doc.data()));

      const elapsed = Math.round((Date.now() - startedAt) / 1000);
      logger.info(`  poll @${elapsed}s: ${evidence.length} evidence item(s)`);

      if (evidence.length !== lastCount) {
        lastCount = evidence.length;
        lastChangeAt = Date.now();
      }

      // Enough evidence collected — send now.
      if (evidence.length >= EXPECTED_COUNT) {
        logger.info(`  hit expected count (${EXPECTED_COUNT}), sending`);
        break;
      }

      // Count has been stable for STABLE_MS with something present — send.
      if (evidence.length > 0 && Date.now() - lastChangeAt >= STABLE_MS) {
        logger.info(`  count stable for ${STABLE_MS / 1000}s, sending`);
        break;
      }

      await sleep(POLL_INTERVAL_MS);
    }

    if (Date.now() - startedAt >= POLL_MAX_MS) {
      logger.warn(`  poll timeout after ${POLL_MAX_MS / 1000}s, sending what we have`);
    }

    // Now assemble and send.
    const [sessionSnap, userSnap, contactsSnap] = await Promise.all([
      sessionRef.get(),
      db.doc(`users/${uid}`).get(),
      db.collection(`users/${uid}/contacts`).get(),
    ]);

    const session = sessionSnap.data() || {};
    const userName =
      userSnap.exists && userSnap.data().displayName
        ? userSnap.data().displayName
        : 'A SafeSignal user';

    const recipients = [];
    contactsSnap.forEach((doc) => {
      const email = doc.data().email;
      if (email) recipients.push(email);
    });

    if (recipients.length === 0) {
      logger.warn('No contact emails on file, skipping');
      return;
    }

    const html = buildHtml({
      userName,
      triggerReason: session.triggerReason,
      lastLocation: session.lastLocation,
      tripLink: session.tripLink,
      evidence,
    });

    const fromName = process.env.GMAIL_FROM_NAME || 'SafeSignal';
    const fromUser = process.env.GMAIL_USER;

    try {
      const t = getTransporter();
      await t.sendMail({
        from: `"${fromName}" <${fromUser}>`,
        to: recipients.join(', '),
        subject: `EMERGENCY - ${userName} may need help`,
        html,
      });
      logger.info(`Email sent to ${recipients.length} recipient(s) with ${evidence.length} evidence item(s)`);
      await sessionRef.update({
        emailSentAt: admin.firestore.FieldValue.serverTimestamp(),
        emailRecipientCount: recipients.length,
        evidenceCount: evidence.length,
      });
    } catch (e) {
      logger.error('Nodemailer send failed', e);
    }
  }
);

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function buildHtml({ userName, triggerReason, lastLocation, tripLink, evidence }) {
  const maps =
    lastLocation && lastLocation.lat && lastLocation.lng
      ? `https://maps.google.com/?q=${lastLocation.lat},${lastLocation.lng}`
      : null;

  const photos = evidence.filter((e) => e.type === 'photo');
  const audios = evidence.filter((e) => e.type === 'audio');
  const videos = evidence.filter((e) => e.type === 'video');

  let evidenceHtml = '';
  if (photos.length > 0) {
    evidenceHtml += `<h3>Photos (${photos.length})</h3><ul>`;
    for (const p of photos) {
      const cam = p.camera || 'camera';
      evidenceHtml += `<li><a href="${p.url}">Photo ${cam} #${p.index || ''}</a></li>`;
    }
    evidenceHtml += '</ul>';
  }
  if (audios.length > 0) {
    evidenceHtml += `<h3>Audio</h3><ul>`;
    for (const a of audios) evidenceHtml += `<li><a href="${a.url}">Recording</a></li>`;
    evidenceHtml += '</ul>';
  }
  if (videos.length > 0) {
    evidenceHtml += `<h3>Video</h3><ul>`;
    for (const v of videos) evidenceHtml += `<li><a href="${v.url}">Video clip</a></li>`;
    evidenceHtml += '</ul>';
  }
  if (evidence.length === 0) {
    evidenceHtml = '<p><em>No evidence captured (permissions denied or capture failed).</em></p>';
  }

  return `
    <div style="font-family: sans-serif; max-width: 600px;">
      <h1 style="color: #b00020;">🚨 EMERGENCY</h1>
      <p><strong>${userName}</strong> may need help.</p>
      <p>SafeSignal automatically escalated a check-in session — trigger: <strong>${triggerReason || 'no check-in'}</strong>.</p>

      <h3>Location</h3>
      ${maps ? `<p><a href="${maps}">Open in Google Maps</a></p>` : '<p><em>Unavailable</em></p>'}

      ${tripLink ? `<h3>Trip link</h3><p><a href="${tripLink}">${tripLink}</a></p>` : ''}

      <h3>Evidence captured</h3>
      ${evidenceHtml}

      <hr />
      <p style="color: #666; font-size: 12px;">
        Please try to reach ${userName} directly. If you cannot, contact local emergency services.
        This alert was sent automatically by SafeSignal.
      </p>
    </div>
  `;
}