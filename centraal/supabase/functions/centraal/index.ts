// The edge function `centraal`: the central system's regular work (_shared/werk.ts).
// pg_cron calls it every hour; a sensor upload and a changed field call it for one field
// right away (body {"veld": "<uuid>"}). It only recalculates, so it needs no login.
import { secretKey, work } from '../_shared/werk.ts';

Deno.serve(async (request) => {
  const body = await request.json().catch(() => ({}));
  const result = await work(body, {
    baseUrl: Deno.env.get('SUPABASE_URL') ?? '',
    key: secretKey((name) => Deno.env.get(name)),
    fetch,
  });
  return Response.json(result.body, { status: result.status });
});
