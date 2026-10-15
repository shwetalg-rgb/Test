# Gennext Events

Events management app for the Gennext events team at Shrimad Rajchandra Aatma Tatva Research Centre (RC), Khopoli. It covers workflow trackers for Prem Mahotsav, Anand Mahotsav, Sarvarpan Divas, Guru Purnima, Paryushan, RPL and Smilescapes, plus expenses, the annual budget, an Idea Bank, Our Moments, the media library and creative guidelines.

## What's in this repo

| Path | What it is |
|---|---|
| `app/index.html` | **Clickable prototype.** A single file with no build step. Open it in a browser to see every screen with sample data. Use it as the design reference. |
| `docs/BACKEND_SPEC.md` | **Build spec.** Stack, roles, every module's logic, the budget rules, the report format and a workshop plan. Start here. |
| `supabase/schema.sql` | **Database.** Tables, triggers (tracker generation and date recalculation), budget-matching views, row-level security and storage buckets. |
| `supabase/seed.sql` | **Starting data.** Real events, templates, team members, guidance and the approved FY 2026-27 budget. |

## Quick start

1. **See the prototype:** open `app/index.html` in a browser. Switch between Admin and Member at the top.
2. **Set up the database:**
   1. Create a free project at [supabase.com](https://supabase.com).
   2. Open **SQL Editor**, then paste and run `supabase/schema.sql`, then `supabase/seed.sql`.
   3. Under **Authentication → Providers**, enable Google.
3. **Create the app:** on [vercel.com](https://vercel.com), choose **New Project → Templates → "Supabase Starter" (Next.js)**. Link it to your Supabase project. Vercel sets the environment variables.
4. Follow the build order in `docs/BACKEND_SPEC.md` § 6.

## Stack

Next.js + Tailwind on **Vercel**; **Supabase** for the database, Google login and file storage; Google Drive API for the photo and creative library; Claude API for checking creatives against the guidelines; SheetJS for the Excel budget report.
