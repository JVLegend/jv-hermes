import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';

// Resolve postgres from Paperclip's own dependencies
const require = createRequire('/app/packages/db/');
const postgres = require('postgres');

const DB_URL = 'postgres://paperclip:paperclip@127.0.0.1:54329/paperclip';
const sql = postgres(DB_URL);

try {
  const users = await sql`SELECT user_id FROM instance_user_roles WHERE role = 'instance_admin' LIMIT 1`;
  if (!users.length) {
    console.log('[setup-key] No admin user found — skipping');
    await sql.end();
    process.exit(0);
  }

  const userId = users[0].user_id;
  const token = process.env.SETUP_API_KEY;
  if (!token) {
    console.log('[setup-key] SETUP_API_KEY env not set — skipping');
    await sql.end();
    process.exit(0);
  }

  const hash = createHash('sha256').update(token).digest('hex');

  // Delete any previous setup key
  await sql`DELETE FROM board_api_keys WHERE name = 'railway-setup'`;

  // Insert new key
  await sql`INSERT INTO board_api_keys (id, user_id, name, key_hash, created_at)
            VALUES (gen_random_uuid(), ${userId}, 'railway-setup', ${hash}, NOW())`;

  console.log('[setup-key] Board API key created for user ' + userId);
  await sql.end();
} catch (e) {
  console.error('[setup-key] Error:', e.message);
  try { await sql.end(); } catch (_) {}
}
