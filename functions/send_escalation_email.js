// functions/send_escalation_email.js
//
// Sends ONE consolidated email to trusted contacts ~60s after a session
// transitions to escalated. Uses Gmail SMTP via nodemailer (free).
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

const DELAY_MS = 60 * 1000;

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
    timeoutSeconds: 120,
  },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    const { uid, sessionId } = event.params;

    if (before.status === 'escalated' || after.status !== 'escalated') return;
    if (after.emailSentAt) return;

    logger.info(`Escalation for ${sessionId} (uid=${uid}) — waiting for evidence…`);

    await sleep(DELAY_MS);

    const sessionRef = db.doc(`users/${uid}/sessions/${sessionId}`);
    const [sessionSnap, userSnap, contactsSnap, evidenceSnap] = await Promise.all([
      sessionRef.get(),
      db.doc(`users/${uid}`).get(),
      db.collection(`users/${uid}/contacts`).get(),
      db.collection(`users/${uid}/sessions/${sessionId}/evidence`).get(),
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

    const evidence = [];
    evidenceSnap.forEach((doc) => evidence.push(doc.data()));

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
      logger.info(`Email sent to ${recipients.length} recipient(s)`);
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