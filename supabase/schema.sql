-- Gennext Events: database schema (Supabase / Postgres)
-- Run this first in the Supabase SQL editor, then seed.sql.
-- Matches the clickable prototype in app/index.html.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- People
-- ---------------------------------------------------------------------------
create type app_role as enum ('admin', 'member');

create table profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text not null,
  email       text unique,
  role        app_role not null default 'member',
  created_at  timestamptz not null default now()
);

-- Team members who don't have a login yet can still be named as task leads.
create table team_members (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  profile_id  uuid references profiles(id) on delete set null
);

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin');
$$;

create or replace function my_member_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from team_members where profile_id = auth.uid() limit 1;
$$;

-- ---------------------------------------------------------------------------
-- Events and the workflow tracker
-- ---------------------------------------------------------------------------
create table event_types (
  key            text primary key,          -- 'smilescapes', 'prem', 'rpl' ...
  label          text not null,
  short          text not null,
  color          text not null,
  default_venue  text,
  runway_days    int  not null,             -- how far before the event work starts
  budget_vertical text not null default 'Events'  -- vertical in the annual budget
);

create type task_status as enum ('To start', 'WIP', 'Live', 'Closed');
create type audience as enum ('External', 'Internal');

-- Back-calculation norms: one task list per event type.
create table task_templates (
  id            uuid primary key default gen_random_uuid(),
  event_type    text not null references event_types(key) on delete cascade,
  title         text not null,
  department    text not null,
  collateral    text,
  audience      audience not null default 'External',
  lead_id       uuid references team_members(id) on delete set null,
  support_id    uuid references team_members(id) on delete set null,
  offset_days   int  not null,              -- -13 = 13 days before the start date; 0 = D-day; +2 = after
  sort          int  not null default 0
);

create table events (
  id          uuid primary key default gen_random_uuid(),
  type        text not null references event_types(key),
  name        text not null,
  start_date  date not null,
  end_date    date,                         -- multi-day events (RPL 25–27 Dec)
  venue       text,
  tentative   boolean not null default false,
  created_by  uuid references profiles(id),
  created_at  timestamptz not null default now(),
  check (end_date is null or end_date >= start_date)
);

create table tasks (
  id             uuid primary key default gen_random_uuid(),
  event_id       uuid not null references events(id) on delete cascade,
  template_id    uuid references task_templates(id) on delete set null,
  title          text not null,
  department     text not null,
  collateral     text,
  audience       audience not null default 'External',
  lead_id        uuid references team_members(id) on delete set null,
  support_id     uuid references team_members(id) on delete set null,
  offset_days    int  not null,
  due_date       date not null,
  due_overridden boolean not null default false,  -- set when someone edits the date by hand
  status         task_status not null default 'To start',
  note           text,
  updated_at     timestamptz not null default now()
);
create index on tasks (event_id, due_date);
create index on tasks (lead_id);

-- Generate the tracker for a new event from its type's template.
create or replace function generate_tasks() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into tasks (event_id, template_id, title, department, collateral, audience,
                     lead_id, support_id, offset_days, due_date)
  select new.id, t.id, t.title, t.department, t.collateral, t.audience,
         t.lead_id, t.support_id, t.offset_days, new.start_date + t.offset_days
  from task_templates t where t.event_type = new.type;
  return new;
end $$;
create trigger events_generate_tasks after insert on events
  for each row execute function generate_tasks();

-- When the event date changes, move every task date except hand-edited ones.
create or replace function recalc_task_dates() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.start_date <> old.start_date then
    update tasks set due_date = new.start_date + offset_days
    where event_id = new.id and not due_overridden;
  end if;
  return new;
end $$;
create trigger events_recalc_dates after update of start_date on events
  for each row execute function recalc_task_dates();

-- Mark a task as hand-edited when its due date no longer follows the norm.
create or replace function flag_override() returns trigger
language plpgsql as $$
declare d date;
begin
  select start_date into d from events where id = new.event_id;
  new.due_overridden := new.due_date <> d + new.offset_days;
  new.updated_at := now();
  return new;
end $$;
create trigger tasks_flag_override before update of due_date on tasks
  for each row execute function flag_override();

create table event_roles (           -- D-Day roles
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references events(id) on delete cascade,
  member_id  uuid references team_members(id) on delete cascade,
  role       text not null
);

create table event_flow (            -- run of show
  id        uuid primary key default gen_random_uuid(),
  event_id  uuid not null references events(id) on delete cascade,
  at_time   text,
  item      text not null,
  sort      int not null default 0
);

create table guidance (              -- notes from Pujya Nileshbhai, Achira, etc.
  id          uuid primary key default gen_random_uuid(),
  event_type  text references event_types(key) on delete cascade,  -- applies to every event of this type
  event_id    uuid references events(id) on delete cascade,        -- or to one event
  given_by    text not null,
  text        text not null,
  created_at  timestamptz not null default now(),
  check (event_type is not null or event_id is not null)
);

create table scripts (
  id        uuid primary key default gen_random_uuid(),
  event_id  uuid not null references events(id) on delete cascade,
  title     text not null,
  author    text
);
create table script_lines (
  id         uuid primary key default gen_random_uuid(),
  script_id  uuid not null references scripts(id) on delete cascade,
  voiceover  text,
  visuals    text,
  sort       int not null default 0
);

-- ---------------------------------------------------------------------------
-- Vendors, quotations, expenses
-- ---------------------------------------------------------------------------
create table vendors (
  id        uuid primary key default gen_random_uuid(),
  name      text not null,
  category  text,
  contact   text,
  city      text,
  gst       text,
  rating    int check (rating between 1 and 5)
);

create type quote_status as enum ('Under review', 'Selected', 'Rejected');
create table quotations (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references events(id) on delete cascade,
  vendor_id  uuid references vendors(id) on delete set null,
  item       text not null,
  amount     numeric(12,2) not null default 0,
  status     quote_status not null default 'Under review',
  file_path  text                         -- Supabase Storage: quotations/<event>/<file>
);

-- ---------------------------------------------------------------------------
-- Annual approved budget (Gennext Budget Summary) and its line-wise breakdown
-- ---------------------------------------------------------------------------
create table annual_budgets (
  id               uuid primary key default gen_random_uuid(),
  fy               text not null unique,  -- '2026-27'
  title            text not null default 'Gennext Budget Summary',
  period           text,                  -- 'Apr 2026 – Mar 2027'
  submitted_on     date,
  submitted_by     text,
  approved_total   numeric(12,2),
  approved_on      date,
  approval_doc     text                   -- signed scan in Storage
);

create table budget_lines (             -- one row per line of the approved summary
  id            uuid primary key default gen_random_uuid(),
  budget_id     uuid not null references annual_budgets(id) on delete cascade,
  section       int  not null,          -- 'TOTAL SECTION n' in the report
  vertical      text not null,          -- ALL / Project Smilestones / Events
  nature        text,                   -- Offline promotions / Online promotions
  item          text not null,          -- Line Items / Project
  frequency     text,
  qty           numeric,
  unit_label    text,
  unit_cost     numeric(12,2),
  approved      numeric(12,2) not null default 0,  -- proposed plan for this FY
  prev_approved numeric(12,2) default 0,           -- last FY total approved
  prev_actual   numeric(12,2) default 0,           -- last FY actual expense
  sort          int not null default 0
);

-- Section totals that come from the signed sheet and differ from the sum of lines.
create table budget_section_overrides (
  budget_id    uuid references annual_budgets(id) on delete cascade,
  section      int,
  prev_actual  numeric(12,2),
  primary key (budget_id, section)
);

create table plan_items (               -- the "double click" sheet
  id         uuid primary key default gen_random_uuid(),
  line_id    uuid not null references budget_lines(id) on delete cascade,
  month      date not null,             -- first of the month
  title      text not null,
  event_id   uuid references events(id) on delete set null,
  qty        numeric,
  unit_cost  numeric(12,2),
  amount     numeric(12,2) not null default 0
);

create table event_budget_heads (       -- optional per-event sanctioned amounts
  event_id    uuid references events(id) on delete cascade,
  head        text,
  sanctioned  numeric(12,2) not null default 0,
  primary key (event_id, head)
);

create table expenses (
  id              uuid primary key default gen_random_uuid(),
  event_id        uuid not null references events(id) on delete cascade,
  item            text not null,
  head            text,                 -- budget head chosen when logging
  vendor_id       uuid references vendors(id) on delete set null,
  quoted          numeric(12,2),
  amount          numeric(12,2) not null,
  paid_by         uuid references team_members(id),
  spent_on        date not null default current_date,
  bill_available  boolean not null default false,
  bill_path       text,                 -- Storage: bills/<event>/<file>
  -- Assignment to the annual budget. All null = auto-match (see view below).
  budget_line_id  uuid references budget_lines(id) on delete set null,
  plan_item_id    uuid references plan_items(id) on delete set null,
  not_from_budget boolean not null default false,
  created_by      uuid references profiles(id) default auth.uid(),
  created_at      timestamptz not null default now()
);
create index on expenses (event_id);

-- Which budget line and planned spend each expense counts against.
-- Order: manual plan item > manual line > auto (same vertical + line item = head)
--        > Smilescapes fallback line > unassigned.
create or replace view expense_assignment as
with b as (select id from annual_budgets order by fy desc limit 1),
auto_line as (
  select x.id as expense_id,
    coalesce(
      (select l.id from budget_lines l, b
        where l.budget_id = b.id
          and (l.vertical = et.budget_vertical or l.vertical = 'ALL')
          and (lower(l.item) = lower(x.head) or lower(l.nature) = lower(x.head))
        order by l.sort limit 1),
      (select l.id from budget_lines l, b
        where l.budget_id = b.id and et.key = 'smilescapes'
          and l.item ilike 'Smilescapes event costs%' limit 1)
    ) as line_id
  from expenses x join events e on e.id = x.event_id join event_types et on et.key = e.type
)
select x.id as expense_id,
  case when x.not_from_budget then null
       else coalesce(p.line_id, x.budget_line_id, a.line_id) end as line_id,
  case when x.not_from_budget then null
       else coalesce(x.plan_item_id,
         (select pi.id from plan_items pi
           where pi.line_id = coalesce(x.budget_line_id, a.line_id)
             and pi.event_id = x.event_id limit 1)) end as plan_item_id,
  (x.plan_item_id is not null or x.budget_line_id is not null) as manual
from expenses x
left join plan_items p on p.id = x.plan_item_id
left join auto_line a on a.expense_id = x.id;

create or replace view budget_line_usage as
select l.*, coalesce(sum(x.amount), 0) as used,
       l.approved - coalesce(sum(x.amount), 0) as remaining,
       (select coalesce(sum(amount), 0) from plan_items where line_id = l.id) as planned
from budget_lines l
left join expense_assignment ea on ea.line_id = l.id
left join expenses x on x.id = ea.expense_id
group by l.id;

-- ---------------------------------------------------------------------------
-- Idea Bank, Moments, Library, Guidelines, Creative checker
-- ---------------------------------------------------------------------------
create table idea_tags (name text primary key);

create type idea_status as enum ('New', 'Shortlisted', 'Used');
create table ideas (
  id             uuid primary key default gen_random_uuid(),
  title          text not null,
  description    text,
  tags           text[] not null default '{}',
  status         idea_status not null default 'New',
  submitted_name text,                  -- public link submissions
  submitted_by   uuid references profiles(id),
  ref_url        text,
  ref_file       text,
  used_in_event  uuid references events(id) on delete set null,
  created_at     timestamptz not null default now()
);
create table idea_comments (
  id        uuid primary key default gen_random_uuid(),
  idea_id   uuid not null references ideas(id) on delete cascade,
  author    uuid references profiles(id) default auth.uid(),
  body      text not null,
  created_at timestamptz not null default now()
);

create table moments (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid references events(id) on delete set null,
  caption     text,
  media_path  text not null,            -- Storage: moments/<file>
  media_type  text not null default 'image',
  posted_by   uuid references profiles(id) default auth.uid(),
  approved    boolean not null default false,
  approved_by uuid references profiles(id),
  created_at  timestamptz not null default now()
);

-- Index of files that live in Google Drive (Event → Year folders).
create type asset_kind as enum ('Photo', 'Creative', 'Logo', 'Video', 'Other');
create table library_items (
  id             uuid primary key default gen_random_uuid(),
  drive_file_id  text unique not null,
  name           text not null,
  kind           asset_kind not null default 'Other',
  folder_event   text,                  -- 'Prem Mahotsav', 'Logos' ...
  folder_year    text,
  mime_type      text,
  thumbnail_url  text,
  web_view_link  text,
  tags           text[] not null default '{}',
  modified_at    timestamptz,
  synced_at      timestamptz not null default now()
);

create table guidelines (
  id        uuid primary key default gen_random_uuid(),
  category  text not null,
  text      text not null,
  sort      int not null default 0
);

create table creative_checks (
  id          uuid primary key default gen_random_uuid(),
  file_path   text not null,
  event_type  text references event_types(key),
  format      text,
  results     jsonb,                    -- [{guideline_id, verdict: pass|fail|review|na, reason}]
  created_by  uuid references profiles(id) default auth.uid(),
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
do $$ declare t text; begin
  foreach t in array array['profiles','team_members','event_types','task_templates','events','tasks',
    'event_roles','event_flow','guidance','scripts','script_lines','vendors','quotations',
    'annual_budgets','budget_lines','budget_section_overrides','plan_items','event_budget_heads',
    'expenses','idea_tags','ideas','idea_comments','moments','library_items','guidelines','creative_checks']
  loop execute format('alter table %I enable row level security', t); end loop;
end $$;

-- Admins can do everything everywhere.
do $$ declare t text; begin
  foreach t in array array['profiles','team_members','event_types','task_templates','events','tasks',
    'event_roles','event_flow','guidance','scripts','script_lines','vendors','quotations',
    'annual_budgets','budget_lines','budget_section_overrides','plan_items','event_budget_heads',
    'expenses','idea_tags','ideas','idea_comments','moments','library_items','guidelines','creative_checks']
  loop execute format('create policy admin_all on %I for all using (is_admin()) with check (is_admin())', t); end loop;
end $$;

-- Signed-in members can read the planning side of the app.
do $$ declare t text; begin
  foreach t in array array['profiles','team_members','event_types','task_templates','events','tasks',
    'event_roles','event_flow','guidance','scripts','script_lines','vendors','quotations',
    'idea_tags','ideas','idea_comments','library_items','guidelines']
  loop execute format('create policy member_read on %I for select to authenticated using (true)', t); end loop;
end $$;

-- Members update tasks they lead or support (status, note, and the date if they lead it).
create policy member_update_own_tasks on tasks for update to authenticated
  using (lead_id = my_member_id() or support_id = my_member_id())
  with check (lead_id = my_member_id() or support_id = my_member_id());

-- Members add scripts, comments and ideas.
create policy member_add_scripts on scripts for insert to authenticated with check (true);
create policy member_add_lines on script_lines for insert to authenticated with check (true);
create policy member_comment on idea_comments for insert to authenticated with check (author = auth.uid());
create policy member_add_idea on ideas for insert to authenticated with check (true);
-- Public idea link: anonymous visitors can insert only, never read.
create policy public_submit_idea on ideas for insert to anon
  with check (status = 'New' and submitted_by is null);

-- Expenses: members log expenses and see only their own. Budgets stay admin-only.
create policy member_add_expense on expenses for insert to authenticated with check (created_by = auth.uid());
create policy member_read_own_expense on expenses for select to authenticated using (created_by = auth.uid());
create policy member_update_own_expense on expenses for update to authenticated
  using (created_by = auth.uid()) with check (created_by = auth.uid());

-- Moments: anyone signed in can post; everyone sees approved posts and their own.
create policy member_post_moment on moments for insert to authenticated with check (posted_by = auth.uid() and approved = false);
create policy member_read_moments on moments for select to authenticated using (approved or posted_by = auth.uid());

-- Creative checks: members run and read their own.
create policy member_checks on creative_checks for all to authenticated
  using (created_by = auth.uid()) with check (created_by = auth.uid());

-- Views run with the caller's rights, so budget usage stays admin-only.
alter view expense_assignment set (security_invoker = on);
alter view budget_line_usage  set (security_invoker = on);

-- New sign-ups get a member profile; promote admins by hand:
--   update profiles set role = 'admin' where email in ('…');
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, name, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)), new.email);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- Storage buckets (create in the dashboard or here):
insert into storage.buckets (id, name, public) values
  ('bills', 'bills', false), ('quotations', 'quotations', false),
  ('moments', 'moments', false), ('creatives', 'creatives', false),
  ('budget-docs', 'budget-docs', false), ('idea-refs', 'idea-refs', false)
on conflict (id) do nothing;
