-- Payload editor flags for daycare-style URLs (date + editable parts).
-- Paste into the Supabase SQL editor.

alter table public.qr_codes
  add column if not exists has_date boolean not null default false;

alter table public.qr_codes
  add column if not exists has_parts boolean not null default false;

alter table public.qr_codes
  add column if not exists payload_template text;

create index if not exists qr_codes_payload_template_idx
  on public.qr_codes (payload_template)
  where payload_template is not null;
