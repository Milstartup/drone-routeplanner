// The edge function `centraal`: the central system's regular work (_shared/werk.ts).
// pg_cron calls it every hour; a sensor upload and a changed field call it for one field
// right away (body {"veld": "<uuid>"}). It only recalculates, so it needs no login.
import { work } from '../_shared/werk.ts';

Deno.serve(async (request) => {
  const body = await request.json().catch(() => ({}));
  const result = await work(body, {
    baseUrl: Deno.env.get('SUPABASE_URL') ?? '',
    key: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    fetch,
  });
  return Response.json(result.body, { status: result.status });
});
