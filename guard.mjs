// Loaded in front of Keeper's web server. It wraps Bun.serve for the public
// port to (1) refuse public sign-up and (2) answer /healthz, then imports the
// Keeper modules listed in KEEPER_MODULES (comma-separated, in order; the first
// one is awaited before the rest start).
const publicPort = Number(process.env.PORT);
const allowSignup = process.env.KEEPER_ALLOW_SIGNUP === "true";
const signupPath = /^\/+api\/+auth\/.*sign-?up/i;
const apiHealth = `http://127.0.0.1:${process.env.API_PORT || 3001}/api/health`;

const originalServe = Bun.serve.bind(Bun);
Bun.serve = (options) => {
  if (Number(options?.port) === publicPort && typeof options.fetch === "function") {
    const inner = options.fetch;
    options = {
      ...options,
      fetch(request, server) {
        const { pathname } = new URL(request.url);
        if (!allowSignup && signupPath.test(pathname)) {
          return new Response("Sign-up is disabled on this instance", { status: 403 });
        }
        if (pathname === "/healthz") {
          return fetch(apiHealth).then(
            (r) => new Response(r.ok ? "ok" : "api unhealthy", { status: r.ok ? 200 : 503 }),
            () => new Response("api unreachable", { status: 503 }),
          );
        }
        return inner.call(this, request, server);
      },
    };
  }
  return originalServe(options);
};

const modules = (process.env.KEEPER_MODULES || "").split(",").map((m) => m.trim()).filter(Boolean);
if (modules.length === 0) throw new Error("KEEPER_MODULES is empty");
await import(modules[0]);
await Promise.all(modules.slice(1).map((m) => import(m)));
