# SpacetimeDB on Railway

Deployment files for running a self-hosted [SpacetimeDB](https://spacetimedb.com)
standalone node on [Railway](https://railway.com), behind a gateway that publishes
only the routes a client application needs.

Two services are built from this one repository:

| Directory | Service | Public | Purpose |
|---|---|---|---|
| `spacetimedb/` | `spacetimedb` | no | The SpacetimeDB standalone node, on a persistent volume at `/stdb` |
| `gateway/` | `gateway` | yes | Caddy, publishing the client API and tunnelling the admin API behind a secret path |

Each service selects its Dockerfile with the `RAILWAY_DOCKERFILE_PATH` variable,
so both builds keep the repository root as their build context.

## Why a gateway

A SpacetimeDB standalone node performs no server-level authentication: anyone who
can reach it may create a database and run their own WebAssembly or JavaScript
module on it. Upstream's own
[self-hosting guide](https://spacetimedb.com/docs/how-to/deploy/self-hosting)
answers this with an nginx configuration that publishes only the client-facing
routes and blocks everything else. `gateway/Caddyfile` is the same policy:

**Public and anonymous**

- `GET /v1/ping`, `GET /v1/health`
- `POST /v1/identity`, `GET /v1/identity/public-key`, and the rest of `/v1/identity/*`
- `GET /v1/database/<db>/subscribe` — the WebSocket every SDK connects on
- `/v1/database/<db>/route/*` — HTTP handlers a module defines, so it can receive webhooks
- `GET /v1/database/<db>/identity` and `/names` — name resolution every SDK performs before opening the WebSocket

Optionally, with `STDB_PUBLIC_HTTP_CALL=true` / `STDB_PUBLIC_HTTP_SQL=true`:

- `POST /v1/database/<db>/call/<reducer>`
- `POST /v1/database/<db>/sql`

**Administrator only**, under the secret prefix in `STDB_ADMIN_PATH`

- everything else: publish, delete, logs, metrics, `/internal/*`

The SpacetimeDB CLI builds every request URL by string concatenation and sets the
`Authorization` header itself, so a path prefix is the one credential it can carry
without modification:

```sh
spacetime server add --url https://<your-domain>/<STDB_ADMIN_PATH> railway
spacetime publish --server railway my-database
```

## What the SpacetimeDB entrypoint does

`spacetimedb/entrypoint.sh` covers the three things no Railway variable can express:

1. **Volume ownership.** The upstream image runs as the unprivileged `spacetime`
   user and Railway mounts volumes root-owned, so the container takes ownership of
   `/stdb` as root and drops back with `setpriv` before starting the server.
2. **IPv6 bind.** Railway's private network routes IPv6 between services, so the
   node listens on `[::]:$PORT` rather than the image's `0.0.0.0` default.
3. **Cgroup-derived sizing.** `--page_pool_max_size` defaults to 8 GiB — larger
   than most Railway plans' memory quota — so it is set to half of
   `/sys/fs/cgroup/memory.max`.

It also renders `<data-dir>/config.toml` on every boot (the shipped default logs
several targets at `debug`, which runs into Railway's 500 logs/sec cap) and sets
`SPACETIMEDB_DISABLE_DISK_LOGGING=1`, without which the server writes a second
copy of every log line onto the volume the database itself needs.

## Licence

SpacetimeDB is distributed under the Business Source License 1.1. Its Additional
Use Grant permits production use with **no more than one SpacetimeDB instance**,
which is why this deployment runs a single node rather than a cluster. See
[LICENSE.txt](https://github.com/clockworklabs/SpacetimeDB/blob/master/LICENSE.txt)
upstream. The files in this repository are provided as-is.
