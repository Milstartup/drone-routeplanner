-- The central system of Veldvlucht (docs/ARCHITECTUUR.md, chapter 4) in Supabase.
--
-- Fields belong to one owner, who can invite others to watch. Sensor boxes send their
-- measurements with a secret key of their own (sensor_upload). The edge function `centraal`
-- fetches the weather and works out the water advice every hour. The photo analysis on the
-- Mac adds plants that need attention.
--
-- Everything can be run again: the install script applies this file with
-- `supabase db query --linked -f`, which needs no database password.

-- ---------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------

create table if not exists public.velden (
  id uuid primary key default gen_random_uuid(),
  eigenaar uuid not null default auth.uid() references auth.users (id) on delete cascade,
  -- The field id of the app, such as "broccoli-west"; unique per owner.
  veld_id text not null,
  naam text not null,
  -- The field as the app keeps it (format veldvlucht/veld): corners, take-off point, settings, sensors.
  veld jsonb not null,
  bijgewerkt timestamptz not null default now(),
  unique (eigenaar, veld_id)
);

-- People who may watch a field. The owner is not in here.
create table if not exists public.veld_leden (
  veld uuid not null references public.velden (id) on delete cascade,
  gebruiker uuid not null references auth.users (id) on delete cascade,
  toegevoegd timestamptz not null default now(),
  primary key (veld, gebruiker)
);

-- One row per sensor in a field, with the secret key the sensor box sends along.
create table if not exists public.sensoren (
  id uuid primary key default gen_random_uuid(),
  veld uuid not null references public.velden (id) on delete cascade,
  sensor_id text not null,
  sleutel text not null unique default replace(gen_random_uuid()::text, '-', ''),
  unique (veld, sensor_id)
);

create table if not exists public.sensormetingen (
  id bigint generated always as identity primary key,
  sensor uuid not null references public.sensoren (id) on delete cascade,
  veld uuid not null references public.velden (id) on delete cascade,
  tijd timestamptz not null,
  ruw double precision not null,
  batterij_volt double precision,
  diepte_cm double precision,
  -- The box's start id and measurement number, so a box that sends again gives no doubles.
  boot bigint,
  nr bigint,
  ontvangen timestamptz not null default now(),
  unique (sensor, boot, nr)
);
create index if not exists sensormetingen_veld_tijd on public.sensormetingen (veld, tijd desc);

-- The weather forecast per field (format veld/weer), from the edge function.
create table if not exists public.weer (
  veld uuid primary key references public.velden (id) on delete cascade,
  verwachting jsonb not null,
  opgehaald timestamptz not null default now()
);

-- The water advice and markings per field (format veld/resultaten), from the edge function.
create table if not exists public.resultaten (
  veld uuid primary key references public.velden (id) on delete cascade,
  resultaten jsonb not null,
  berekend timestamptz not null default now()
);

-- The photo logs of the flights (format veld/fotolog).
create table if not exists public.vluchten (
  id uuid primary key default gen_random_uuid(),
  veld uuid not null references public.velden (id) on delete cascade,
  vlucht_id text not null,
  fotolog jsonb not null,
  geupload timestamptz not null default now(),
  unique (veld, vlucht_id)
);

-- Plants or spots that need attention, from the photo analysis on the Mac.
create table if not exists public.aandacht (
  id uuid primary key default gen_random_uuid(),
  veld uuid not null references public.velden (id) on delete cascade,
  vlucht_id text not null,
  lat double precision not null,
  lng double precision not null,
  reden text not null,
  foto text,
  zekerheid double precision,
  gemaakt timestamptz not null default now()
);
create index if not exists aandacht_veld on public.aandacht (veld, vlucht_id);

-- ---------------------------------------------------------------------------------------
-- Who may see what
-- ---------------------------------------------------------------------------------------

create or replace function public.is_eigenaar(v uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.velden where id = v and eigenaar = auth.uid())
$$;

create or replace function public.mag_zien(v uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_eigenaar(v)
      or exists (select 1 from public.veld_leden where veld = v and gebruiker = auth.uid())
$$;

alter table public.velden enable row level security;
alter table public.veld_leden enable row level security;
alter table public.sensoren enable row level security;
alter table public.sensormetingen enable row level security;
alter table public.weer enable row level security;
alter table public.resultaten enable row level security;
alter table public.vluchten enable row level security;
alter table public.aandacht enable row level security;

drop policy if exists velden_zien on public.velden;
create policy velden_zien on public.velden for select to authenticated using (public.mag_zien(id));
drop policy if exists velden_maken on public.velden;
create policy velden_maken on public.velden for insert to authenticated with check (eigenaar = auth.uid());
drop policy if exists velden_wijzigen on public.velden;
create policy velden_wijzigen on public.velden for update to authenticated
  using (eigenaar = auth.uid()) with check (eigenaar = auth.uid());
drop policy if exists velden_verwijderen on public.velden;
create policy velden_verwijderen on public.velden for delete to authenticated using (eigenaar = auth.uid());

drop policy if exists leden_zien on public.veld_leden;
create policy leden_zien on public.veld_leden for select to authenticated using (public.mag_zien(veld));
drop policy if exists leden_verwijderen on public.veld_leden;
create policy leden_verwijderen on public.veld_leden for delete to authenticated
  using (public.is_eigenaar(veld) or gebruiker = auth.uid());

-- The keys of the sensor boxes: only for the owner.
drop policy if exists sensoren_zien on public.sensoren;
create policy sensoren_zien on public.sensoren for select to authenticated using (public.is_eigenaar(veld));

drop policy if exists metingen_zien on public.sensormetingen;
create policy metingen_zien on public.sensormetingen for select to authenticated using (public.mag_zien(veld));

drop policy if exists weer_zien on public.weer;
create policy weer_zien on public.weer for select to authenticated using (public.mag_zien(veld));

drop policy if exists resultaten_zien on public.resultaten;
create policy resultaten_zien on public.resultaten for select to authenticated using (public.mag_zien(veld));

drop policy if exists vluchten_zien on public.vluchten;
create policy vluchten_zien on public.vluchten for select to authenticated using (public.mag_zien(veld));
drop policy if exists vluchten_maken on public.vluchten;
create policy vluchten_maken on public.vluchten for insert to authenticated with check (public.is_eigenaar(veld));
drop policy if exists vluchten_wijzigen on public.vluchten;
create policy vluchten_wijzigen on public.vluchten for update to authenticated
  using (public.is_eigenaar(veld)) with check (public.is_eigenaar(veld));

drop policy if exists aandacht_zien on public.aandacht;
create policy aandacht_zien on public.aandacht for select to authenticated using (public.mag_zien(veld));
drop policy if exists aandacht_maken on public.aandacht;
create policy aandacht_maken on public.aandacht for insert to authenticated with check (public.is_eigenaar(veld));
drop policy if exists aandacht_verwijderen on public.aandacht;
create policy aandacht_verwijderen on public.aandacht for delete to authenticated using (public.is_eigenaar(veld));

-- Without a login nothing can be read or written, except through sensor_upload below.
-- Everything is spelled out: since May 2026 new Supabase projects give tables no rights by
-- themselves, and older projects give them all to every role. The rights must be the same in both.
revoke all on public.velden, public.veld_leden, public.sensoren, public.sensormetingen,
  public.weer, public.resultaten, public.vluchten, public.aandacht from anon, authenticated, service_role;
grant select, insert, update, delete on public.velden, public.vluchten, public.aandacht to authenticated;
grant select, delete on public.veld_leden to authenticated;
grant select on public.sensoren, public.sensormetingen, public.weer, public.resultaten to authenticated;
-- The edge function reads what it needs and saves the weather and the advice.
grant select on public.velden, public.sensoren, public.sensormetingen, public.aandacht to service_role;
grant select, insert, update on public.weer, public.resultaten to service_role;

-- ---------------------------------------------------------------------------------------
-- Functions for the app
-- ---------------------------------------------------------------------------------------

-- After new measurements or a changed field: the advice is worked out again right away,
-- once the hourly job of the next migration (bereken_opnieuw) exists.
create or replace function public.na_wijziging(v uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if to_regprocedure('public.bereken_opnieuw(uuid)') is not null then
    execute 'select public.bereken_opnieuw($1)' using v;
  end if;
end;
$$;
revoke execute on function public.na_wijziging(uuid) from public, anon, authenticated, service_role;

-- Saves a field from the app and keeps its sensors in step. Returns each sensor's key,
-- which the owner types into the sensor box.
create or replace function public.bewaar_veld(p_veld_id text, p_naam text, p_veld jsonb)
returns table (sensor_id text, sleutel text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v uuid;
  ids text[];
begin
  if auth.uid() is null then
    raise exception 'Niet ingelogd.';
  end if;
  insert into public.velden (eigenaar, veld_id, naam, veld, bijgewerkt)
  values (auth.uid(), p_veld_id, p_naam, p_veld, now())
  on conflict (eigenaar, veld_id) do update set naam = excluded.naam, veld = excluded.veld, bijgewerkt = now()
  returning id into v;

  select coalesce(array_agg(s ->> 'id'), '{}') into ids
  from jsonb_array_elements(coalesce(p_veld -> 'sensors', '[]'::jsonb)) as s;
  delete from public.sensoren where veld = v and not (public.sensoren.sensor_id = any (ids));
  insert into public.sensoren (veld, sensor_id)
  select v, unnest(ids)
  on conflict (veld, sensor_id) do nothing;

  perform public.na_wijziging(v);
  return query select s.sensor_id, s.sleutel from public.sensoren s where s.veld = v order by s.sensor_id;
end;
$$;

-- Lets someone with a Veldvlucht account watch a field. They must have made an account first.
create or replace function public.nodig_uit(p_veld_id text, p_email text) returns text
language plpgsql security definer set search_path = public, auth as $$
declare
  v uuid;
  wie uuid;
begin
  select id into v from public.velden where eigenaar = auth.uid() and veld_id = p_veld_id;
  if v is null then
    raise exception 'Dit veld is niet van jou.';
  end if;
  select id into wie from auth.users where lower(email) = lower(trim(p_email));
  if wie is null then
    return 'onbekend';
  end if;
  if wie = auth.uid() then
    return 'jezelf';
  end if;
  insert into public.veld_leden (veld, gebruiker) values (v, wie) on conflict do nothing;
  return 'toegevoegd';
end;
$$;

-- Who may watch a field, by e-mail address (for the owner).
create or replace function public.leden(p_veld_id text) returns table (email text, toegevoegd timestamptz)
language sql stable security definer set search_path = public, auth as $$
  select u.email::text, l.toegevoegd
  from public.velden v
  join public.veld_leden l on l.veld = v.id
  join auth.users u on u.id = l.gebruiker
  where v.eigenaar = auth.uid() and v.veld_id = p_veld_id
  order by u.email
$$;

create or replace function public.verwijder_lid(p_veld_id text, p_email text) returns void
language sql security definer set search_path = public, auth as $$
  delete from public.veld_leden l
  using public.velden v, auth.users u
  where l.veld = v.id and l.gebruiker = u.id
    and v.eigenaar = auth.uid() and v.veld_id = p_veld_id and lower(u.email) = lower(trim(p_email))
$$;

-- ---------------------------------------------------------------------------------------
-- The sensor boxes
-- ---------------------------------------------------------------------------------------

-- A sensor box sends its measurements here (format veld/sensorupload, sensor/README.md),
-- with the key of its sensor. Works without a login; the key is the proof.
-- Returns {"ontvangen": n, "nieuw": k}.
create or replace function public.sensor_upload(p_sleutel text, p_upload jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s public.sensoren%rowtype;
  m jsonb;
  v_boot bigint := nullif(p_upload ->> 'boot', '')::bigint;
  nieuw integer := 0;
  aantal integer := 0;
  t timestamptz;
  r double precision;
begin
  select * into s from public.sensoren where sleutel = p_sleutel;
  if not found then
    raise exception 'Onbekende sleutel. Kijk in de app bij Sensoren welke sleutel bij dit kastje hoort.' using errcode = '28000';
  end if;
  if p_upload ->> 'format' is distinct from 'veld/sensorupload' or (p_upload ->> 'version')::int is distinct from 0 then
    raise exception 'Verwacht "format": "veld/sensorupload", versie 0.' using errcode = '22023';
  end if;
  if p_upload ->> 'sensorId' is distinct from s.sensor_id then
    raise exception 'Deze sleutel hoort bij sensor %, niet bij %.', s.sensor_id, p_upload ->> 'sensorId' using errcode = '22023';
  end if;
  for m in select * from jsonb_array_elements(coalesce(p_upload -> 'measurements', '[]'::jsonb)) loop
    aantal := aantal + 1;
    t := now() - make_interval(secs => round((m ->> 'ageS')::double precision));
    r := (m ->> 'raw')::double precision;
    if v_boot is null or m ->> 'nr' is null then
      -- Without numbers: the same value within two minutes counts as the same measurement.
      if exists (select 1 from public.sensormetingen x where x.sensor = s.id and x.ruw = r
                 and abs(extract(epoch from x.tijd - t)) < 120) then
        continue;
      end if;
    end if;
    insert into public.sensormetingen (sensor, veld, tijd, ruw, batterij_volt, diepte_cm, boot, nr)
    values (s.id, s.veld, t, r, nullif(m ->> 'batteryVolt', '')::double precision,
            nullif(p_upload ->> 'depthCm', '')::double precision, v_boot, nullif(m ->> 'nr', '')::bigint)
    on conflict (sensor, boot, nr) do nothing;
    if found then
      nieuw := nieuw + 1;
    end if;
  end loop;
  if nieuw > 0 then
    perform public.na_wijziging(s.veld);
  end if;
  return jsonb_build_object('ontvangen', aantal, 'nieuw', nieuw);
end;
$$;

-- Only these functions may be called from the app (logged in) or by a box (anon).
revoke execute on function public.bewaar_veld(text, text, jsonb), public.nodig_uit(text, text),
  public.leden(text), public.verwijder_lid(text, text), public.sensor_upload(text, jsonb),
  public.is_eigenaar(uuid), public.mag_zien(uuid) from public, anon, authenticated, service_role;
grant execute on function public.bewaar_veld(text, text, jsonb), public.nodig_uit(text, text),
  public.leden(text), public.verwijder_lid(text, text), public.is_eigenaar(uuid), public.mag_zien(uuid)
  to authenticated;
grant execute on function public.sensor_upload(text, jsonb) to anon, authenticated;
