# Deploy and Host Keeper.sh on Railway

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
