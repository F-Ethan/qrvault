-- Actually delete the signed-in user's account (Apple 5.1.1).
-- Paste into the Supabase SQL editor after the RLS fix.
--
-- Deletes their qr_codes rows, then the auth.users row. The app calls
-- this via rpc('delete_own_account') then signs out.

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  delete from public.qr_codes where user_id = uid;
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_own_account() from public, anon;
grant execute on function public.delete_own_account() to authenticated;
