# Changelog

## 2.34.3 (2026-11-24)

- First release of the Railway template: Keeper.sh `v2.34.3` (`ghcr.io/ridafkih/keeper-standalone:2.34.3@sha256:7a31517cfef742c2366a123a4b89eabb0bd25cae213bc92383e443658b25ee9f`), with Railway Postgres (volume) and Railway Redis (queue only, no volume).
- Admin account created on first boot from generated variables; public sign-up closed.
- Low-memory mode below 900 MB (Railway Free/Trial): one process, MCP server off.
