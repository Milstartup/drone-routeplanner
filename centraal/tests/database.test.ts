// Runs the database of the central system in PGlite (Postgres in Node) and checks who may see
// what, sharing a field, and the uploads of the sensor boxes. Supabase's `auth` schema and
// roles are imitated with a few lines of SQL; the migration itself is used as it is.
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
import { beforeAll, describe, expect, it } from 'vitest';

const migration = readFileSync(
  new URL('../supabase/migrations/20261027120000_veldvlucht.sql', import.meta.url),
  'utf8',
);

const A = '00000000-0000-0000-0000-00000000000a';
const B = '00000000-0000-0000-0000-00000000000b';
const C = '00000000-0000-0000-0000-00000000000c';

let db: PGlite;

/** Runs SQL as a logged-in user (or as a sensor box without a login when `user` is null). */
async function as<T>(user: string | null, sql: string, params: unknown[] = [], role?: string): Promise<T[]> {
  await db.exec(`reset role; select set_config('request.jwt.claim.sub', '${user ?? ''}', false);`);
  await db.exec(`set role ${role ?? (user ? 'authenticated' : 'anon')}`);
  try {
    return (await db.query<T>(sql, params)).rows;
  } finally {
    await db.exec('reset role');
  }
}

/** A new database with Supabase's `auth` schema and roles imitated. */
async function startDatabase(privileges = ''): Promise<void> {
  db = new PGlite();
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin bypassrls;
    create schema auth;
    create table auth.users (id uuid primary key, email text);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema public, auth to anon, authenticated, service_role;
    grant execute on function auth.uid() to anon, authenticated, service_role;
    insert into auth.users values ('${A}', 'a@voorbeeld.nl'), ('${B}', 'b@voorbeeld.nl'), ('${C}', 'c@voorbeeld.nl');
    ${privileges}
  `);
}

const upload = (sensorId: string, measurements: object[], extra: object = {}) =>
  JSON.stringify({ format: 'veld/sensorupload', version: 0, sensorId, depthCm: 15, ...extra, measurements });

describe('central system database', () => {
  let keyS1 = '';

  beforeAll(async () => {
    await startDatabase();
    await db.exec(migration);
    // Running it again must work: the install script may do that.
    await db.exec(migration);
  }, 120_000);

  it('saves a field with its sensors and gives each sensor a key', async () => {
    const field = { format: 'veldvlucht/veld', sensors: [{ id: 'veld-a-s1' }, { id: 'veld-a-s2' }] };
    const keys = await as<{ sensor_id: string; sleutel: string }>(
      A, 'select * from public.bewaar_veld($1, $2, $3)', ['veld-a', 'Veld A', JSON.stringify(field)]);
    expect(keys.map((k) => k.sensor_id)).toEqual(['veld-a-s1', 'veld-a-s2']);
    expect(keys[0].sleutel).toMatch(/^[0-9a-f]{32}$/);
    keyS1 = keys[0].sleutel;

    // Saving again keeps the keys.
    const again = await as<{ sleutel: string }>(
      A, 'select * from public.bewaar_veld($1, $2, $3)', ['veld-a', 'Veld A', JSON.stringify(field)]);
    expect(again[0].sleutel).toBe(keyS1);
  });

  it('shows a field only to its owner and the people invited', async () => {
    expect(await as(B, 'select * from public.velden')).toHaveLength(0);
    await expect(as(B, `select public.nodig_uit('veld-a', 'c@voorbeeld.nl')`)).rejects.toThrow('niet van jou');

    expect((await as<{ r: string }>(A, `select public.nodig_uit('veld-a', 'onbekend@voorbeeld.nl') as r`))[0].r).toBe('onbekend');
    expect((await as<{ r: string }>(A, `select public.nodig_uit('veld-a', ' B@Voorbeeld.nl ') as r`))[0].r).toBe('toegevoegd');
    expect(await as(B, 'select * from public.velden')).toHaveLength(1);
    expect(await as(C, 'select * from public.velden')).toHaveLength(0);
    expect(await as<{ email: string }>(A, `select * from public.leden('veld-a')`)).toEqual([
      expect.objectContaining({ email: 'b@voorbeeld.nl' }),
    ]);

    // Someone watching cannot change the field or see the keys of the sensor boxes.
    await as(B, `update public.velden set naam = 'Van B'`);
    expect((await as<{ naam: string }>(A, 'select naam from public.velden'))[0].naam).toBe('Veld A');
    expect(await as(B, 'select * from public.sensoren')).toHaveLength(0);
    expect(await as(A, 'select * from public.sensoren')).toHaveLength(2);
  });

  it('takes measurements from a sensor box with its key, without doubles', async () => {
    const send = (body: string) =>
      as<{ r: { ontvangen: number; nieuw: number } }>(null, 'select public.sensor_upload($1, $2) as r', [keyS1, body]);
    const first = upload('veld-a-s1', [{ nr: 1, ageS: 7200, raw: 2875, batteryVolt: 3.91 }, { nr: 2, ageS: 3600, raw: 2875, batteryVolt: null }], { boot: 4711 });
    expect((await send(first))[0].r).toEqual({ ontvangen: 2, nieuw: 2 });
    // The box missed the answer and sends both again, with a third.
    const again = upload('veld-a-s1', [
      { nr: 1, ageS: 7260, raw: 2875 }, { nr: 2, ageS: 3660, raw: 2875 }, { nr: 3, ageS: 60, raw: 2890 },
    ], { boot: 4711 });
    expect((await send(again))[0].r).toEqual({ ontvangen: 3, nieuw: 1 });

    // A box without numbers: the same value within two minutes counts once.
    const plain = upload('veld-a-s1', [{ ageS: 30, raw: 2900 }]);
    expect((await send(plain))[0].r).toEqual({ ontvangen: 1, nieuw: 1 });
    expect((await send(plain))[0].r).toEqual({ ontvangen: 1, nieuw: 0 });

    const rows = await as<{ ruw: number; diepte_cm: number }>(A, 'select ruw, diepte_cm from public.sensormetingen order by tijd');
    expect(rows.map((r) => r.ruw)).toEqual([2875, 2875, 2890, 2900]);
    expect(rows[0].diepte_cm).toBe(15);
    expect(await as(B, 'select * from public.sensormetingen')).toHaveLength(4);
    expect(await as(C, 'select * from public.sensormetingen')).toHaveLength(0);
  });

  it('refuses a wrong key, a wrong sensor or a wrong format', async () => {
    const body = upload('veld-a-s1', [{ ageS: 1, raw: 1 }]);
    await expect(as(null, 'select public.sensor_upload($1, $2)', ['fout', body])).rejects.toThrow('Onbekende sleutel');
    await expect(as(null, 'select public.sensor_upload($1, $2)', [keyS1, upload('veld-a-s2', [])])).rejects.toThrow('hoort bij sensor veld-a-s1');
    await expect(as(null, 'select public.sensor_upload($1, $2)', [keyS1, JSON.stringify({ format: 'iets', version: 0 })])).rejects.toThrow('veld/sensorupload');
  });

  it('gives nothing to someone without a login', async () => {
    await expect(as(null, 'select * from public.velden')).rejects.toThrow('permission denied');
    await expect(as(null, 'select * from public.sensormetingen')).rejects.toThrow('permission denied');
    await expect(as(null, `select * from public.bewaar_veld('x', 'x', '{}')`)).rejects.toThrow('permission denied');
  });

  it('removes a sensor and its measurements when it leaves the field', async () => {
    const field = { format: 'veldvlucht/veld', sensors: [{ id: 'veld-a-s2' }] };
    await as(A, 'select * from public.bewaar_veld($1, $2, $3)', ['veld-a', 'Veld A', JSON.stringify(field)]);
    expect(await as(A, 'select * from public.sensoren')).toHaveLength(1);
    expect(await as(A, 'select * from public.sensormetingen')).toHaveLength(0);
    await expect(as(null, 'select public.sensor_upload($1, $2)', [keyS1, upload('veld-a-s1', [])])).rejects.toThrow('Onbekende sleutel');
  });

  it('lets only the owner delete a field', async () => {
    await as(B, `delete from public.velden`);
    expect(await as(A, 'select * from public.velden')).toHaveLength(1);
    await as(A, `delete from public.velden`);
    expect(await as(A, 'select * from public.velden')).toHaveLength(0);
    expect(await as(B, 'select * from public.veld_leden')).toHaveLength(0);
  });
});

// Supabase has two kinds of project: since May 2026 new tables get no rights by themselves, and
// older projects give them to every role. The migration must give the same rights in both.
describe.each([
  ['nothing automatically', `alter default privileges in schema public revoke execute on functions from public;`],
  ['everything automatically', `
    alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
    alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
    alter default privileges in schema public grant all on functions to anon, authenticated, service_role;`],
])('rights in a Supabase project that gives %s', (_name, privileges) => {
  let key = '';
  const field = { format: 'veldvlucht/veld', sensors: [{ id: 'veld-s1' }] };
  const service = <T>(sql: string, params: unknown[] = []) => as<T>(null, sql, params, 'service_role');

  beforeAll(async () => {
    await startDatabase(privileges);
    await db.exec(migration);
    const keys = await as<{ sleutel: string }>(A, 'select * from public.bewaar_veld($1, $2, $3)', ['veld', 'Veld', JSON.stringify(field)]);
    key = keys[0].sleutel;
  }, 120_000);

  it('lets the app and a box do their work', async () => {
    expect(await as(A, 'select * from public.velden')).toHaveLength(1);
    expect(await as(A, 'select * from public.sensoren')).toHaveLength(1);
    await as(null, 'select public.sensor_upload($1, $2)', [key, upload('veld-s1', [{ ageS: 60, raw: 2000 }])]);
    expect(await as(A, 'select * from public.sensormetingen')).toHaveLength(1);
  });

  it('lets the edge function read everything and save weather and advice', async () => {
    const [{ id }] = await service<{ id: string }>('select id, veld_id, veld from public.velden');
    expect(await service(`select tijd, ruw, s.sensor_id from public.sensormetingen m join public.sensoren s on s.id = m.sensor`)).toHaveLength(1);
    expect(await service('select lat, lng, reden from public.aandacht')).toHaveLength(0);
    for (let round = 0; round < 2; round += 1) {
      await service(`insert into public.weer (veld, verwachting) values ($1, '{}')
        on conflict (veld) do update set verwachting = excluded.verwachting`, [id]);
      await service(`insert into public.resultaten (veld, resultaten) values ($1, '{}')
        on conflict (veld) do update set resultaten = excluded.resultaten`, [id]);
    }
    expect(await service('select * from public.weer')).toHaveLength(1);
    expect(await as(A, 'select * from public.resultaten')).toHaveLength(1);
  });

  it('keeps the edge function to what it needs', async () => {
    await expect(service('delete from public.velden')).rejects.toThrow('permission denied');
    await expect(service(`update public.sensoren set sleutel = 'x'`)).rejects.toThrow('permission denied');
  });

  it('keeps out everyone else', async () => {
    await expect(as(null, 'select * from public.velden')).rejects.toThrow('permission denied');
    await expect(as(null, 'select * from public.sensoren')).rejects.toThrow('permission denied');
    await expect(as(null, `select public.bewaar_veld('x', 'x', '{}')`)).rejects.toThrow('permission denied');
    await expect(as(null, 'select public.is_eigenaar(null)')).rejects.toThrow('permission denied');
    await expect(as(null, 'select public.na_wijziging(null)')).rejects.toThrow('permission denied');
    await expect(as(A, 'select public.na_wijziging(null)')).rejects.toThrow('permission denied');
    await expect(as(A, `update public.sensoren set sleutel = 'x'`)).rejects.toThrow('permission denied');
    await expect(as(A, `insert into public.resultaten (veld, resultaten) select id, '{}' from public.velden`)).rejects.toThrow('permission denied');
    await expect(as(B, 'select * from public.velden')).resolves.toHaveLength(0);
  });
});
