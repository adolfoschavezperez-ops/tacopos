/**
 * Standalone HTTP entrypoint for TacoPOS Backoffice 2.0 Preview Read-Only API.
 * Configured strictly via environment variables; zero embedded credentials.
 */

const admin = require('firebase-admin');
const { createPreviewServer } = require('./server');

const port = Number(process.env.PORT || 8085);
const authProjectId = process.env.PREVIEW_AUTH_PROJECT_ID || 'tacopos-backoffice-dev';
const dataProjectId = process.env.PREVIEW_DATA_PROJECT_ID || 'tacopos-backoffice-dev';
const allowedOrigins = (process.env.PREVIEW_ALLOWED_ORIGINS || '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

const authApp = admin.initializeApp({ projectId: authProjectId }, 'preview-auth');
const dataApp =
  dataProjectId === authProjectId
    ? authApp
    : admin.initializeApp({ projectId: dataProjectId }, 'preview-data');

const server = createPreviewServer({
  auth: authApp.auth(),
  authzDb: authApp.firestore(),
  dataDb: dataApp.firestore(),
  allowedOrigins,
  maxDocsPerQuery: Number(process.env.PREVIEW_MAX_DOCS_PER_QUERY || 500),
  maxRequestsPerMin: Number(process.env.PREVIEW_RATE_LIMIT_PER_MIN || 120),
  maxConcurrentPerUid: Number(process.env.PREVIEW_MAX_CONCURRENT || 6),
  maxDaysRange: Number(process.env.PREVIEW_MAX_DAYS_RANGE || 93),
  disabled: process.env.PREVIEW_DISABLED === 'true',
  logger: (entry) => console.log(JSON.stringify(entry)),
});

server.listen(port, '0.0.0.0', () => {
  console.log(
    JSON.stringify({
      event: 'preview_api_started',
      port,
      authProjectId,
      dataProjectId,
      mode: 'read_only',
    }),
  );
});
