# Console

The admin console is the existing Vue 3 SPA (plain JS), unchanged by the migration:
it is served as static assets by varman-server via `app.useStatic("/", "wwwroot")`.
Build it from the current `acp/console` and drop the `dist/` output here (or point
`--console` at it). Optionally convert it to KYX + Datastar later (design doc section 6,
Phase 6). It is not a Kyte project.
