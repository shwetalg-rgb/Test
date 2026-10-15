# Gennext Events — Build Spec

The events team app for Shrimad Rajchandra Aatma Tatva Research Centre (RC), Khopoli.
This spec turns the clickable prototype (`app/index.html`) into a real, shared app.

- **Owner:** Shweta Jain (events team) · Admins: Shweta, Saransh
- **Users:** fewer than 15 team members, plus a public link for idea submissions
- **Languages:** English, with a Gujarati toggle for interface labels
- **Devices:** phone and laptop equally (responsive web app; installable as a PWA later)

---

## 1. Recommended stack

| Layer | Choice | Why |
|---|---|---|
| Frontend | **Next.js** (React, App Router) + Tailwind | Rebuild the prototype screens as components; deploys to Vercel in one click |
| Hosting | **Vercel** (free Hobby tier is enough to start) | Push to GitHub → live URL. Preview link for every change |
| Database + login + files | **Supabase** (Postgres, Auth, Storage) | Schema and data are ready in `supabase/`. Google sign-in, row-level security, file buckets for bills and photos |
| Google Drive library | Google Drive API (service account on the shared Drive) | Files stay in Drive; the app indexes them |
| AI creative check | Claude API (`claude-sonnet-5-5`, image input) via a server route | Checks an uploaded creative against the guidelines |
| Excel / PDF | SheetJS (`xlsx`) for the budget report; `pdf-lib` to merge bills into one PDF | Already proven in the prototype |

Vercel is only the host. It isn't required, and any Next.js host (Netlify, Render) works. Supabase is the part that matters.

**No-code alternative:** if the workshop is building with a tool like Lovable or Bolt, give it this spec plus `supabase/schema.sql`. Both tools connect to Supabase directly.

---

## 2. Roles and access

| | Admin | Member | Public link |
|---|---|---|---|
| Events, trackers, calendar | Full edit | View all. Update status and notes on tasks they lead or support. Change the date only on tasks they lead | — |
| Templates (back-calculation norms) | Edit | — | — |
| Expenses | All events, all entries | Log expenses, upload bills, see **only their own** entries | — |
| Budget (annual + event) | Full | **Hidden** | — |
| Vendors and quotations | Edit | View | — |
| Idea Bank | Full, change status | Add ideas, comment | **Submit only** (cannot see the bank) |
| Our Moments | Approve or decline posts | Post (shows after approval) | — |
| Library, Guidelines | Edit | View, run the creative check | — |

All of this is enforced in the database with row-level security (see `supabase/schema.sql`). The app shouldn't rely on hiding buttons alone.

---

## 3. Modules and the logic to build

### 3.1 Events and workflow tracker
- **Two tracks:**
  - **Smilescapes** (1–2 a month, anywhere) has its own template, based on the 10 Oct tracker (about 15 days of runway).
  - **All other events** (RPL, Prem Mahotsav, Anand Mahotsav, US Travel, Sarvarpan Divas, Guru Purnima, Paryushan) follow the **Gennext events calendar**.
- **Events calendar.** Every creative milestone is due a set number of **weeks before the event**:

  | Milestone | Save the date | Registration flyer | Dossier & thumbnails |
  |---|---|---|---|
  | Kick-off | 11 | 14 | — |
  | Referencing | 11 | 12 | — |
  | First draft | 10 | 10 | — |
  | Achira's iteration | 10 | 8.5 | 6 |
  | Sending to events team | 9 | 8 | 5 |
  | Go live | 8 | 6 | 3 |

  **Event pieces:** Opening ceremony, Activation (e.g. Prem Mahotsav: Networking), Big event (e.g. Sarvarpan Divas: Play), Event coverage and Event highlights. Their dates are **TBC** and are set per event (`date_tbc`). The first date entered becomes the norm for that task.
- The tracker list is grouped by creative (Save the date / Registration flyer / Dossier & thumbnails / Event pieces) for calendar events, and by Pre / During / Post for Smilescapes.
- Each event type has a **template**: a list of tasks with department, collateral, external/internal, lead, support, and **offset in days** from the event start (−13 = 13 days before; 0 = D-day; +2 = after).
- **Creating an event generates its tracker:** due date = start date + offset. *(DB trigger `generate_tasks`, already done.)*
- **Changing the event date recalculates** every task date except dates edited by hand, which are flagged `due_overridden`. *(Triggers already done.)*
- Events can span several days (`end_date`, e.g. RPL 25–27 Dec) and can be marked **tentative**.
- Task fields: activity, department, collateral, lead, support, due date, status (**To start / WIP / Live / Closed**), note.
- Views: **List** grouped into Pre event / During / Post, **Board** by status, filters (department, status, person).
- Per event, also: **D-Day roles**, **Event flow** (run of show), **Guidance** (leadership notes, per event type or per event), **Scripts** (voiceover | visuals).

### 3.2 Calendar
- Month grid showing events (multi-day bars) and task deadlines, with an "All tasks / Mine" filter.
- Nice to have: Google Calendar sync, plus WhatsApp or email reminders for tasks due tomorrow and overdue tasks.

### 3.3 Expenses, vendors and quotations
- An expense belongs to one event. Fields: item, budget head, vendor, quoted amount, actual amount, paid by, date, bill available (Y/N), bill file.
- Log only, with no approval step.
- **Bills pack:** for an event, merge every uploaded bill (images and PDFs) into **one PDF**, with the expense summary on page 1. Save it to Storage under `bills/<event>/` for future reference.
- Vendors: name, category, contact, city, GST, rating, events used in.
- Quotations: vendor, item, amount, status (Under review / Selected / Rejected), file.

### 3.4 Budget: the core money logic
Two levels, matching how the budget is approved:

1. **Annual approved budget** (`annual_budgets` + `budget_lines`). This is the *Gennext Budget Summary* approved each April. Lines are grouped by **section → vertical → nature of expense → line item**, with frequency, qty × unit cost, this year's approved amount, and last year's approved and actual amounts.
   - FY 2026-27 is already loaded: **₹2,50,000 approved on 5 May 2026**, with a proposed plan of ₹2,36,816.
   - The admin can **upload next year's sheet** (Excel/CSV). The parser finds the header row with "Line item", carries blank vertical and nature cells down from the row above, and skips "Total" rows. *(Working parser is in the prototype: `parseAnnual`.)*
2. **Line-wise breakdown** (`plan_items`). Each approved line is split into planned spends by month, optionally linked to an event (for example, WhatsApp → 12 monthly campaigns of ₹2,068).

**How an expense is assigned** (view `expense_assignment`, already done):
1. A planned spend chosen by hand, then
2. a budget line chosen by hand, then
3. **auto-match:** same vertical as the event (Smilescapes → *Project Smilestones*; RC events → *Events*) **and** the line item equals the budget head picked when logging, then
4. Smilescapes fallback: anything else from a Smilescapes event goes to *Project Smilestones → Offline promotions → Smilescapes event costs* (food, cycles, props), then
5. otherwise **Not assigned**, shown in a review list. The admin can also mark an expense "Not from the annual budget".

Within a line, an expense attaches to the planned spend linked to the same event.

**Dashboard:** approved, used, remaining, not assigned; used by vertical and by nature; the full approved-vs-used sheet; the breakdown per line with "not yet planned / over-planned" flags.

**Downloadable report (Excel, required format):**
- Sheet 1 **Budget Summary**, in the exact format of the signed sheet:
  - Title block: Title, Period, Date of submission, Submitted by, approval status.
  - Columns: S No, Vertical, Nature of Expense, Line Items / Project, Frequency, FY prev Total Approved, FY prev Actual Expense, FY Proposed Plan, Unit, Per Unit Cost, **FY Actual Used to Date**, **FY Remaining**.
  - Rows: `TOTAL SECTION n` after each section, then GRAND TOTAL, Total Ask and Approved.
  - Section 3 FY26 actual uses the signed figure **₹18,065** (`budget_section_overrides`).
- Sheet 2 **Line-wise Breakdown**.
- Sheet 3 **Expenses**: every expense with its budget line, planned spend and bill status.
- *(Working generator is in the prototype: `downloadBudget` / `reportRows`.)*

There is also an optional **per-event budget**: sanctioned amount per head for an event against what it spent.

### 3.5 Idea Bank ("Activity cupboard")
- Fields: title, description, tags (multiple; admins can add new tags), reference link or file, submitted by, status **New → Shortlisted → Used** (and which event it was used in), comments.
- **Public submit page** at `/submit-idea`, with no login. It can insert ideas but never read them. Add a captcha (e.g. Cloudflare Turnstile) to stop spam.

### 3.6 Our Moments
- Photo and video wall grouped by event. Members post, and the admin approves before posts are visible.
- Store files in Supabase Storage. Resize images on upload.

### 3.7 Library (Google Drive)
- **Files stay in the team's shared Google Drive.** It is organised as **Event → Year** (plus a *Logos* folder).
- A scheduled job (Vercel Cron, e.g. hourly) walks the shared Drive with a service account and upserts each file into `library_items`: name, Drive file ID, folder event and year, kind (Photo / Creative / Logo), thumbnail, link.
- The app gives search, filters and previews. "Open" and "Download" go through the Drive link.
- Uploads from the app go to the matching Drive folder.

### 3.8 Creative guidelines and AI check
- The guidelines are a list of rules grouped by category (logo, colour, typography, mandatory info, imagery, tone, language). Admins edit them.
- **Check a creative:** a member uploads an image and picks the event and format. A server route sends the image plus the current guidelines to the Claude API and asks for strict JSON back: `[{guideline_id, verdict: pass|fail|review|na, reason}]`. Results are stored in `creative_checks` and shown as a checklist.
- The guidelines in the seed are **samples**. Replace them with the real rules.

### 3.9 Home
- Next event with a countdown and progress, my tasks (overdue and due this week), upcoming events, latest moments, fresh ideas.

---

## 4. Data model (summary)

Full SQL is in `supabase/schema.sql`. It has been tested on Postgres 16.

```
profiles ─ team_members                         people (login vs. named-only)
event_types ─< task_templates                   back-calculation norms
event_types ─< events ─< tasks                  trackers (auto-generated)
events ─< event_roles | event_flow | scripts ─< script_lines | guidance
vendors ─< quotations >─ events
annual_budgets ─< budget_lines ─< plan_items >─ events
events ─< expenses  (→ budget_line / plan_item, or auto via view expense_assignment)
ideas ─< idea_comments ; idea_tags
moments >─ events ; library_items (Drive index) ; guidelines ; creative_checks
```

Storage buckets: `bills`, `quotations`, `moments`, `creatives`, `budget-docs`, `idea-refs` (all private; serve them through signed URLs).

---

## 5. Starting data (`supabase/seed.sql`)

- 8 event types (including US Travel) and 10 team members.
- Templates: the Smilescapes template is based on the 10 Oct tracker; RC and RPL templates are drafts.
- Events:
  - Pause at the Promenade (26 Sep, done) and Smilescapes on Wheels (10 Oct, done).
  - Smilescapes 31 Oct.
  - Prem Mahotsav (31 Dec): the events-calendar milestones, plus the current work (main creative approval due 17 Oct; opening ceremony: show to Achira 17 Oct, core idea 20 Oct, grand rehearsal 30 Nov).
  - From the events calendar: RPL (25–27 Dec), Anand Mahotsav (15–17 Feb; the calendar sheet says 16 Feb), US Travel (1 Apr), Sarvarpan Divas (31 May), Guru Purnima (20 Jul) and Paryushan (28 Aug 2027).
- D-Day roles, event flow and the reel script for Smilescapes on Wheels; Pujya Nileshbhai's and Achira's Smilescapes guidance.
- The FY 2026-27 approved budget, all lines, and a draft breakdown.

---

## 6. Workshop plan (suggested order)

1. **Set up (30 min).** Create the Supabase project → run `schema.sql` → run `seed.sql`. Turn on Google sign-in. Create a Next.js app from the Vercel template "Supabase Starter" and connect it to this GitHub repo.
2. **Login and roles.** Sign in with Google. Promote admins with `update profiles set role='admin' where email in (...)`. Link each person to their `team_members` row.
3. **Events and tracker.** Event list, event page with List and Board views, editing status and dates. The database triggers already do the date maths.
4. **Expenses and bills.** Log an expense, upload the bill to Storage, view the event's expenses.
5. **Budget.** Summary, breakdown, review assignments, then the Excel export (port `downloadBudget` from the prototype).
6. **Idea Bank and public link.** Then Moments with approval.
7. **Later:** Drive library sync, AI creative check, bills-PDF merge, reminders, Gujarati labels.

**Definition of done for day 1:** the team can log in, see real events and trackers, update their tasks, and log an expense with a bill.

---

## 7. Open questions for the team

- The approved amount for the new *Smilescapes event costs* line is currently ₹0. Should it get the ₹13,184 buffer?
- Who besides Shweta and Saransh should be admin?
- Do reminders go out on WhatsApp (needs a WhatsApp Business provider) or email?
- What are the real creative guidelines?
- What are the dates for the event pieces (opening ceremony, activation, big event, coverage, highlights) for each event?
- Is Anand Mahotsav 15–17 Feb or 16 Feb?
