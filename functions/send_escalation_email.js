// functions/send_escalation_email.js
//
// Sends ONE consolidated email to trusted contacts after a session
// transitions to escalated. Polls the evidence subcollection every few
// seconds for up to POLL_MAX_MS, then sends whatever is present.
//
// For 'date' mode sessions, also loads the pre-session dateContext/info
// doc and renders it in the email body.
//
// functions/.env:
//   GMAIL_USER=youremail@gmail.com
//   GMAIL_APP_PASSWORD=xxxxxxxxxxxxxxxx
//   GMAIL_FROM_NAME=SafeSignal

const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const POLL_INITIAL_MS = 15 * 1000;
const POLL_INTERVAL_MS = 10 * 1000;
const POLL_MAX_MS = 120 * 1000;
const STABLE_MS = 15 * 1000;
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
    timeoutSeconds: 300,
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

    // --- Poll for evidence ---
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

      if (evidence.length >= EXPECTED_COUNT) {
        logger.info(`  hit expected count (${EXPECTED_COUNT}), sending`);
        break;
      }

      if (evidence.length > 0 && Date.now() - lastChangeAt >= STABLE_MS) {
        logger.info(`  count stable for ${STABLE_MS / 1000}s, sending`);
        break;
      }

      await sleep(POLL_INTERVAL_MS);
    }

    if (Date.now() - startedAt >= POLL_MAX_MS) {
      logger.warn(`  poll timeout after ${POLL_MAX_MS / 1000}s, sending what we have`);
    }

    // --- Assemble email inputs ---
    const [sessionSnap, userSnap, contactsSnap, dateCtxSnap] = await Promise.all([
      sessionRef.get(),
      db.doc(`users/${uid}`).get(),
      db.collection(`users/${uid}/contacts`).get(),
      db.doc(`users/${uid}/sessions/${sessionId}/dateContext/info`).get(),
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

    const dateContext = dateCtxSnap.exists ? dateCtxSnap.data() : null;

    const html = buildHtml({
      userName,
      mode: session.mode,
      triggerReason: session.triggerReason,
      lastLocation: session.lastLocation,
      tripLink: session.tripLink,
      evidence,
      dateContext,
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

function buildHtml({ userName, mode, triggerReason, lastLocation, tripLink, evidence, dateContext }) {
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
      <p>SafeSignal automatically escalated a check-in session — trigger: <strong>${triggerReason || 'no check-in'}</strong>${mode ? ` (mode: ${mode})` : ''}.</p>

      <h3>Location</h3>
      ${maps ? `<p><a href="${maps}">Open in Google Maps</a></p>` : '<p><em>Unavailable</em></p>'}

      ${tripLink ? `<h3>Trip link</h3><p><a href="${tripLink}">${tripLink}</a></p>` : ''}

      ${renderDateContext(dateContext)}

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

function renderDateContext(ctx) {
  if (!ctx) return '';

  const howMet =
    ctx.howMet === 'Other' && ctx.howMetOther
      ? `Other (${ctx.howMetOther})`
      : ctx.howMet || 'Unknown';

  let endAt = '';
  if (ctx.expectedEndAt && typeof ctx.expectedEndAt.toDate === 'function') {
    endAt = ctx.expectedEndAt.toDate().toLocaleString();
  }

  const personImg = ctx.personPhotoUrl
    ? `<p><strong>Person:</strong><br/><a href="${ctx.personPhotoUrl}"><img src="${ctx.personPhotoUrl}" style="max-width:280px;border-radius:6px" /></a></p>`
    : '';
  const carImg = ctx.carPhotoUrl
    ? `<p><strong>Car:</strong><br/><a href="${ctx.carPhotoUrl}"><img src="${ctx.carPhotoUrl}" style="max-width:280px;border-radius:6px" /></a></p>`
    : '';
  const plate = ctx.carPlate
    ? `<li><strong>Plate:</strong> ${ctx.carPlate}</li>`
    : '';

  return `
    <h3 style="color:#b00020;margin-top:24px">Date context (captured before the meeting)</h3>
    <ul style="line-height:1.6">
      <li><strong>Name:</strong> ${ctx.personName || '—'}</li>
      <li><strong>How they met:</strong> ${howMet}</li>
      <li><strong>Venue:</strong> ${ctx.venueName || '—'}${ctx.venueAddress ? ' — ' + ctx.venueAddress : ''}</li>
      ${endAt ? `<li><strong>Expected end:</strong> ${endAt}</li>` : ''}
      ${plate}
    </ul>
    ${personImg}
    ${carImg}
  `;
}