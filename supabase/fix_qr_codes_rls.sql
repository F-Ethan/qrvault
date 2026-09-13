-- Isolate QR codes per account.
--
-- Symptom this fixes: a second user (same phone or any device) sees another
-- account's Library and My Cards (pinned) codes.
--
-- Cause: a single FOR ALL / SELECT policy that ORs `is_public = true` with
-- `auth.uid() = user_id`. Unfiltered `select()` then returns every public
-- row. `is_pinned` lives on the row, so other people's favorites show up
-- in My Cards.
--
-- Run this in the Supabase Dashboard → SQL Editor.

alter table public.qr_codes enable row level security;

do $$
declare
  pol record;
begin
  for pol in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'qr_codes'
  loop
    execute format('drop policy if exists %I on public.qr_codes', pol.policyname);
  end loop;
end $$;

create policy "Users select own codes"
on public.qr_codes for select
using (auth.uid() = user_id);

create policy "Users insert own codes"
on public.qr_codes for insert
with check (auth.uid() = user_id);

create policy "Users update own codes"
on public.qr_codes for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "Users delete own codes"
on public.qr_codes for delete
using (auth.uid() = user_id);

-- Near You / All Public browse only. Must not grant UPDATE or DELETE.
create policy "Anyone can select public codes"
on public.qr_codes for select
using (is_public = true);
