# Keeper (keeper.sh) for Railway: web, API, cron, worker and MCP server in one service.
# Postgres and Redis run as separate Railway services.
FROM ghcr.io/ridafkih/keeper-standalone:2.34.3@sha256:7a31517cfef742c2366a123a4b89eabb0bd25cae213bc92383e443658b25ee9f

# The upstream image starts its own Postgres, Redis and Caddy under s6-overlay.
# On Railway we use Railway Postgres and Redis, so we run the five Keeper
# processes under a small supervisor that exits non-zero when any of them dies.
# guard.mjs blocks public sign-up and serves /healthz on the public port.
COPY start.sh /usr/local/bin/keeper-railway-start
COPY bootstrap-admin.sh /usr/local/bin/keeper-railway-bootstrap-admin
COPY guard.mjs /etc/keeper-railway/guard.mjs
RUN chmod 0755 /usr/local/bin/keeper-railway-start /usr/local/bin/keeper-railway-bootstrap-admin \
  && chmod 0644 /etc/keeper-railway/guard.mjs \
  && mkdir -p /var/lib/keeper-railway

ENV PORT=8080
EXPOSE 8080

# The upstream HEALTHCHECK probes port 80, which this image doesn't use.
HEALTHCHECK NONE

ENTRYPOINT []
CMD ["/usr/local/bin/keeper-railway-start"]
