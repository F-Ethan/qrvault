-- Scan matching, personal overlay (pin/nickname), public notes, scan totals.
-- Paste into the Supabase SQL editor after the RLS + delete_own_account scripts.
--
-- Public scan does NOT auto-add a library membership. Pass p_save_membership
-- true only when the user tapped Open and save.

alter table public.qr_codes
  add column if not exists public_scan_count int4 not null default 0;

update public.qr_codes
set public_scan_count = scan_count
where public_scan_count = 0 and scan_count > 0;

create table if not exists public.qr_code_memberships (
  user_id uuid not null references auth.users (id) on delete cascade,
  qr_code_id uuid not null references public.qr_codes (id) on delete cascade,
  custom_label text,
  is_pinned boolean not null default false,
  my_scan_count int4 not null default 0,
  last_scanned_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, qr_code_id)
);

create index if not exists qr_code_memberships_user_pinned_idx
  on public.qr_code_memberships (user_id)
  where is_pinned = true;

create table if not exists public.qr_code_notes (
  id uuid primary key default gen_random_uuid(),
  qr_code_id uuid not null references public.qr_codes (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 500),
  created_at timestamptz not null default now()
);

create index if not exists qr_code_notes_code_created_idx
  on public.qr_code_notes (qr_code_id, created_at desc);

insert into public.qr_code_memberships (
  user_id, qr_code_id, is_pinned, my_scan_count, last_scanned_at
)
select
  user_id,
  id,
  coalesce(is_pinned, false),
  coalesce(scan_count, 0),
  last_scanned_at
from public.qr_codes
on conflict (user_id, qr_code_id) do nothing;

alter table public.qr_code_memberships enable row level security;
alter table public.qr_code_notes enable row level security;

drop policy if exists "Users manage own memberships" on public.qr_code_memberships;
create policy "Users manage own memberships"
on public.qr_code_memberships for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users read notes on visible codes" on public.qr_code_notes;
create policy "Users read notes on visible codes"
on public.qr_code_notes for select
using (
  exists (
    select 1 from public.qr_codes c
    where c.id = qr_code_id
      and (c.user_id = auth.uid() or c.is_public = true)
  )
);

drop policy if exists "Users insert notes on visible codes" on public.qr_code_notes;
create policy "Users insert notes on visible codes"
on public.qr_code_notes for insert
with check (
  auth.uid() = user_id
  and exists (
    select 1 from public.qr_codes c
    where c.id = qr_code_id
      and (c.user_id = auth.uid() or c.is_public = true)
  )
);

drop policy if exists "Users delete own notes" on public.qr_code_notes;
create policy "Users delete own notes"
on public.qr_code_notes for delete
using (auth.uid() = user_id);

-- Find own then public. Always bump community totals on a match.
-- Membership: always for own rows; for public rows only when p_save_membership.
create or replace function public.record_qr_scan(
  p_content text,
  p_lat double precision default null,
  p_lng double precision default null,
  p_place text default null,
  p_save_membership boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  code public.qr_codes%rowtype;
  mem public.qr_code_memberships%rowtype;
  is_own boolean := false;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  select * into code
  from public.qr_codes
  where user_id = uid
    and content = p_content
  limit 1;

  if found then
    is_own := true;
  else
    select * into code
    from public.qr_codes
    where is_public = true
      and content = p_content
    order by public_scan_count desc, created_at asc
    limit 1;
  end if;

  if code.id is null then
    return null;
  end if;

  update public.qr_codes
  set
    public_scan_count = public_scan_count + 1,
    scan_count = scan_count + 1,
    last_scanned_at = now(),
    last_scanned_lat = coalesce(p_lat, last_scanned_lat),
    last_scanned_lng = coalesce(p_lng, last_scanned_lng),
    last_scanned_place = coalesce(p_place, last_scanned_place),
    updated_at = now()
  where id = code.id
  returning * into code;

  if is_own or p_save_membership then
    insert into public.qr_code_memberships as m (
      user_id, qr_code_id, my_scan_count, last_scanned_at, updated_at
    ) values (uid, code.id, 1, now(), now())
    on conflict (user_id, qr_code_id) do update
      set my_scan_count = public.qr_code_memberships.my_scan_count + 1,
          last_scanned_at = now(),
          updated_at = now()
    returning * into mem;
  else
    select * into mem
    from public.qr_code_memberships
    where user_id = uid and qr_code_id = code.id;
  end if;

  return jsonb_build_object(
    'code', to_jsonb(code),
    'membership', to_jsonb(mem),
    'is_own', is_own
  );
end;
$$;

revoke all on function public.record_qr_scan(text, double precision, double precision, text, boolean)
  from public, anon;
grant execute on function public.record_qr_scan(text, double precision, double precision, text, boolean)
  to authenticated;
