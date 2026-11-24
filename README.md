[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/keepersh?utm_medium=integration&utm_source=button&utm_campaign=keeper)

# Keeper.sh on Railway

Keeper.sh is an open-source calendar sync tool. It pulls events from Google Calendar, Outlook, iCloud, Fastmail, CalDAV servers and iCal/ICS links, and pushes them to one or more calendars so your busy time lines up everywhere. It also offers a REST API, a combined iCal feed and an MCP server for AI agents.

## About Hosting Keeper.sh

This template deploys Keeper.sh 2.34.3, built from the official `keeper-standalone` image, pinned by digest. One service runs the web app, API, sync scheduler and sync worker, plus the MCP server when the service has 1 GB of RAM. Railway Postgres stores accounts, calendars, events and encrypted credentials on a volume. Railway Redis holds only the job queue and short-lived locks, so it needs no volume, and the stack uses a single volume. Migrations run on every start. The first boot creates an `admin` account with a generated password and closes public sign-up. Open the Keeper service's Variables tab, copy `KEEPER_ADMIN_PASSWORD`, then sign in at your Railway URL.

## Common Use Cases

* Block busy time across work and personal calendars (Google, Outlook, iCloud, CalDAV) to stop double-booking
* Merge several calendars into one private iCal feed, with event names hidden if you want
* Let an AI agent (Claude, ChatGPT, Cursor) read your calendars, find free time and manage events through MCP

## Dependencies for Keeper.sh Hosting

* PostgreSQL (Railway Postgres, with a volume)
* Redis (Railway Redis, job queue only)

### Deployment Dependencies

* Keeper.sh source and docs: https://github.com/ridafkih/keeper.sh
* Template repo (Dockerfile, start script, changelog): https://github.com/aalfath/keeper-railway-template
* Google OAuth app (optional, for Google Calendar): https://support.google.com/cloud/answer/15549257
* Microsoft Entra app (optional, for Outlook): https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app

### Implementation Details

**Services**

* **Keeper**: web UI, API, sync scheduler and worker, plus the MCP server at `/mcp`. Public, health check at `/healthz`.
* **Postgres**: all Keeper data, on a volume.
* **Redis**: the sync job queue and locks. If it restarts, the queue rebuilds itself on the next sync run.

**After deploy:** sign in as `admin` with `KEEPER_ADMIN_PASSWORD`. iCloud, Fastmail, CalDAV and ICS sources work straight away. For Google or Outlook, create an OAuth app with the redirect URIs `https://YOUR-DOMAIN/api/sources/callback/google` (or `/outlook`) and `https://YOUR-DOMAIN/api/auth/callback/google` (or `/microsoft`), then set `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` or `MICROSOFT_CLIENT_ID`/`MICROSOFT_CLIENT_SECRET` on the Keeper service. To let other people register, set `KEEPER_ALLOW_SIGNUP=true`, and optionally `REGISTRATION_EMAIL_DOMAINS`.

**Memory:** with 1 GB of RAM (Hobby plan or higher), Keeper runs as separate processes, including the MCP server, using about 570 MB. Below 900 MB (Free or Trial plan, 0.5 GB) it switches to a low-memory mode: one process using about 370 MB, with the MCP server off. It runs the same way and restarts on its own if a process stops.

**MCP client** (1 GB plan). Point your client at your instance; it signs in through Keeper's OAuth consent page:

```json
{ "mcpServers": { "keeper": { "type": "url", "url": "https://YOUR-DOMAIN/mcp" } } }
```

**Updates:** the Keeper service builds from the template repo. When we publish a new Keeper version there, Railway shows you an update on the service. Read the repo's `CHANGELOG.md`, then apply it. Migrations run on start.

## Why Deploy Keeper.sh on Railway?

<!-- Recommended: Keep this section as shown below -->
Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Keeper.sh on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
<!-- End recommended section -->

## Variables

| Variable | Default | What it is |
|---|---|---|
| `KEEPER_ADMIN_USERNAME` | `admin` | Username of the account created on first boot |
| `KEEPER_ADMIN_PASSWORD` | generated | Password of that account. Copy it from the Variables tab |
| `BETTER_AUTH_SECRET` | generated | Signs sessions and MCP tokens |
| `ENCRYPTION_KEY` | generated | Encrypts stored CalDAV passwords. Don't change it after first use |
| `BETTER_AUTH_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Public URL, used for sign-in redirects and the MCP resource |
| `DATABASE_URL`, `REDIS_URL` | references | Railway Postgres and Redis |
| `PORT` | `8080` | Port the service listens on |

Optional, set them on the Keeper service when you need them: `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `MICROSOFT_CLIENT_ID`, `MICROSOFT_CLIENT_SECRET`, `OIDC_ISSUER_URL`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`, `KEEPER_ALLOW_SIGNUP` (`true` opens sign-up), `REGISTRATION_EMAIL_DOMAINS`, `KEEPER_LOW_MEMORY` (`auto`, `true` or `false`), `KEEPER_MCP_ENABLED` (`false` turns the MCP server off), `WORKER_CONCURRENCY` (default `4`). Every upstream variable is listed in the [Keeper.sh README](https://github.com/ridafkih/keeper.sh#environment-variables).

## Repo layout

* `Dockerfile`: `FROM ghcr.io/ridafkih/keeper-standalone:2.34.3@sha256:…` plus our start scripts.
* `start.sh`: checks variables, runs migrations, creates the admin, starts the Keeper processes and exits non-zero if any of them stops (so Railway restarts the service).
* `bootstrap-admin.sh`: creates the admin account over loopback.
* `guard.mjs`: wraps Keeper's web server to answer `/healthz` and refuse public sign-up.

Licence: Keeper.sh is AGPL-3.0 (https://github.com/ridafkih/keeper.sh). This repo only packages it for Railway.
