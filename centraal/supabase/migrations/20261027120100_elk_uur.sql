-- The central system works by itself: pg_cron asks the edge function `centraal` to fetch the
-- weather and work out the advice every hour (at 7 past), and right away after a sensor
-- upload or a changed field. Needs the extensions pg_cron and pg_net of Supabase.
-- The install script stores the project's own address in `instellingen` first.

-- Settings that are not secret, such as the address of this project.
create table if not exists public.instellingen (
  naam text primary key,
  waarde text not null
);
alter table public.instellingen enable row level security;
revoke all on public.instellingen from anon, authenticated;

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

-- Asks the edge function to recalculate one field, or every field when v is null.
-- Does nothing until the project's address is known.
create or replace function public.bereken_opnieuw(v uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  base text;
begin
  select waarde into base from public.instellingen where naam = 'project_url';
  if base is null or not exists (select 1 from pg_extension where extname = 'pg_net') then
    return;
  end if;
  execute 'select net.http_post(url := $1, headers := $2, body := $3, timeout_milliseconds := 60000)'
    using base || '/functions/v1/centraal', '{"Content-Type": "application/json"}'::jsonb,
          case when v is null then '{}'::jsonb else jsonb_build_object('veld', v) end;
end;
$$;
revoke execute on function public.bereken_opnieuw(uuid) from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'veldvlucht-centraal';
select cron.schedule('veldvlucht-centraal', '7 * * * *', 'select public.bereken_opnieuw(null)');
