# stack

Boilerplate for a Ruby GraphQL API (`ruby/`) and a Vue client (`vuejs/`).

## Database setup

The API uses PostgreSQL via Sequel. Connection details for each environment
live in `ruby/.env.development` and `ruby/.env.test` as a `DATABASE_URL`.

1. Start Postgres:

   ```sh
   docker compose up -d db
   ```

   On a fresh volume, `docker/postgres/init-databases.sh` reads
   `ruby/.env.development` and `ruby/.env.test` and creates the role and
   database for each environment automatically.

2. If the volume already existed before a `.env.*` file's user, password, or
   database name changed (so the init script above didn't run again), create
   or update the role/database for an environment directly:

   ```sh
   cd ruby
   bundle exec rake db:init                # uses APP_ENV, defaults to development
   bundle exec rake db:init[test]
   bundle exec rake db:init[development]
   ```

   This is safe to re-run; it only creates what's missing.

3. Run migrations for each environment:

   ```sh
   cd ruby
   APP_ENV=development bundle exec bin/migrate up
   APP_ENV=test bundle exec bin/migrate up
   ```

With the test database migrated, `cd ruby && bundle exec rspec` will run
against it (`APP_ENV` defaults to `test` in specs).

## Running the app

With the database set up (above), run the API and the client in two separate
terminals.

1. **Ruby API** (GraphQL + REST) — `bin/server` binds to port 9292, which is
   where the Vue client expects it, so the only thing to set is the Vite dev
   origin CORS allows:

   ```sh
   cd ruby
   CORS_ALLOWED_ORIGIN=http://localhost:5173 bundle exec bin/server
   ```

   Verify it's up: `curl http://localhost:9292/healthz` should return
   `{"status":"ok"}`. To bind elsewhere, set `LISTEN_ADDR` (e.g.
   `LISTEN_ADDR=http://0.0.0.0:4000`) and point the client at the new address
   with `VITE_GRAPHQL_URL`.

2. **Vue client** (Vite dev server, defaults to port 5173):

   ```sh
   cd vuejs
   npm install   # first time only
   npm run dev
   ```

   Open http://localhost:5173 — it talks to the API at
   `http://localhost:9292/graphql` by default (override with a `VITE_GRAPHQL_URL`
   env var, e.g. in `vuejs/.env.local`, if you bind the API elsewhere).

If you change the GraphQL schema, regenerate the client's typed operations
before restarting Vite:

```sh
cd ruby && bundle exec rake graphql:schema:dump
cd ../vuejs && npm run generate
```

## REST API

Alongside GraphQL, a set of Roda apps serve a versioned, RESTful `/api`
surface through the same `App` Rack app and Falcon process — no separate
server or port. `App#route` dispatches any `/api/*` path to it via
`Rack::URLMap`. Routing is split across three layers, each its own file:

- `app/api/api_app.rb` (`Api::App`) — mounted at `/api`. Handles CORS
  preflight for the whole API and dispatches `/api/v1/*` to `Api::V1::App`.
- `app/api/v1/app.rb` (`Api::V1::App`) — mounted at `/api/v1`. Gates each
  resource by name and hands the rest of the request to its own sub-app.
- `app/api/v1/notes.rb` (`Api::V1::Notes`) — the boilerplate example
  resource, mounted at `/api/v1/notes`, backed by the same `Note` model and
  `Services::SaveNote` service the GraphQL mutation uses.

| Method | Path                 | Description                     |
| ------ | -------------------- | -------------------------------- |
| GET    | `/api/v1/notes`      | List all notes                  |
| GET    | `/api/v1/notes/:id`  | Fetch one note (404 if missing) |
| POST   | `/api/v1/notes`      | Create a note (422 if invalid)  |
| OPTIONS| `/api/v1/notes`      | CORS preflight                  |

```sh
curl http://localhost:9292/api/v1/notes
curl -X POST http://localhost:9292/api/v1/notes \
  -H 'Content-Type: application/json' \
  -d '{"note": "remember the milk"}'
```

Add a new resource under the current version by creating
`app/api/v1/<resource>.rb` (a Roda sub-app, following `notes.rb`) and
mounting it with an `r.on('<resource>') { r.run Api::V1::<Resource> }` line
in `app/api/v1/app.rb`. Keep each resource's routes thin, delegating to
`Services::` for behavior — the same convention GraphQL mutations follow.
Start a new version by adding `app/api/v2/app.rb` and mounting it from
`app/api/api_app.rb` the same way `v1` is mounted.

## IRB console

`bin/console` loads the app (`lib/environment.rb`) and drops you into IRB, so
models, services, and `DB` are available directly:

```sh
cd ruby
bin/console
```

```
irb(main):001> DB.table_exists?(:notes)
=> true
```

## Background jobs (Resque)

Background jobs run via [Resque](https://github.com/resque/resque), backed by
Redis. Connection details live in `ruby/.env.development` and
`ruby/.env.test` as `REDIS_URL` (each environment uses a different Redis
database index so they don't share state).

1. Start Redis:

   ```sh
   docker compose up -d redis
   ```

2. Start a worker (in its own terminal), listening on every queue:

   ```sh
   cd ruby
   QUEUE=* bundle exec rake resque:work
   ```

To check a worker can actually reach Redis and process a job, enqueue the
built-in smoke-test job (`Jobs::IncrementCounterJob`, in
`ruby/app/jobs/increment_counter_job.rb`), which just increments a counter
key:

```sh
cd ruby
bundle exec rake resque:test_enqueue
```

With a worker running, it'll pick the job up and increment `test_counter`
(stored as `resque:test_counter`, since Resque namespaces all of its own keys
under `resque:`). Confirm it worked:

```sh
docker compose exec redis redis-cli -n 0 get resque:test_counter
```

(use `-n 1` instead if you're checking against the test environment's Redis
database).

## Redis in the request path

Application code talks to Redis through `RedisConnection`
(`ruby/lib/redis_connection.rb`), which wraps
[async-redis](https://github.com/socketry/async-redis) rather than the
blocking `redis` gem Resque uses. Falcon serves every request in a fiber on a
single reactor per worker, so a blocking command would stall every other
in-flight request; async-redis yields to the reactor instead and gives each
fiber its own pooled connection.

It reads the same `REDIS_URL` as Resque, including the database index, and
connects lazily, so no sockets exist at boot for Falcon's workers to inherit
when they fork.

```ruby
# Inside a request, a reactor is already running:
RedisConnection.with { |redis| redis.call('GET', 'some:key') }
```

`with` also works from a rake task, `bin/console`, or a spec — it starts a
reactor when there isn't one and blocks until the block returns.

## Doctor

Once you've started the pieces above, check they're all actually up:

```sh
bin/doctor
```

It checks Postgres, Redis, the Ruby API, a Resque worker, the Vite/Vue
client, and the observability backend, reading connection details from
`ruby/.env.development`. Override `API_URL` / `VITE_URL` / `GRAFANA_URL` if
you've bound those somewhere other than this README's defaults
(`http://localhost:9292`, `http://localhost:5173`, `http://localhost:3000`).
Exits non-zero if anything's down — except the observability backend, which
is opt-in and only ever reported on.

## Observability

Tracing and structured logging live in `ruby/lib/observability.rb`, in two
tiers, because the OpenTelemetry signals are not equally mature.

**Structured logs** are always on. `Observability::Log` writes one JSON object
per line to stdout, each carrying the `trace_id` and `span_id` of the span in
scope when it was written — which is what lets a log line be read next to the
trace it belongs to. `LOG_LEVEL` sets the threshold (`info` in development,
`fatal` in the test env so a run stays quiet).

**Traces** come from the stable OpenTelemetry trace SDK (1.x) and export over
OTLP. `OTEL_SDK_DISABLED` switches the tier off, leaving a no-op tracer:
spans still open and close, they just record nothing and cost nothing, and
neither the SDK nor the OTLP exporter is even loaded. It is set in both
`ruby/.env.development` and `ruby/.env.test`: there's a collector to run
locally now (below), but it's opt-in, and an SDK left on without one just
retries exports that can never land. The suite therefore needs nothing
running, and specs that assert on spans install an in-memory exporter for
their own duration.

Metrics are deliberately absent. The metrics and logs SDKs are both pre-1.0
and break between minor versions, so RED metrics are left for the collector to
derive from the spans below rather than emitted by the app.

Spans are opened at three hand-written seams, and the rest come from the
instrumentation gems for GraphQL, pg, Redis and Resque:

- **`App#call`** — one server span per request, named `<METHOD> <route>` with
  record ids collapsed (`GET /api/v1/notes/:id`) so the names stay usable as
  metric series. It continues an inbound `traceparent`, so a trace that starts
  in the browser carries on into the API instead of breaking in two, and it
  records the response status, marking 5xx failed.
- **`Services::BaseService#perform`** — every write in the app funnels through
  this one method, so one span there covers them all.
- **`AppSchema`** — the `rescue_from` handlers record the original exception
  on the span before translating it into a client-facing GraphQL error, which
  is otherwise the last place that exception exists.

To see it working without a collector, run the app with `OTEL_SDK_DISABLED=false`
and `OTEL_TRACES_EXPORTER=none`, then add an in-memory exporter in
`bin/console`. To see it working against a real one, start the backend below.

## Observability backend

What receives the OTLP above: one container, `grafana/otel-lgtm`, bundling an
OpenTelemetry Collector with Tempo (traces), Prometheus (metrics), Loki
(logs) and Grafana. It's opt-in — nothing else in this stack needs it, and
it's the heaviest thing here — so it sits behind a compose profile and a
plain `docker compose up -d` never starts it.

The app speaks OTLP, a wire protocol rather than a vendor SDK, so this whole
service is swappable for a hosted backend later without touching application
code.

1. Start it:

   ```sh
   docker compose --profile observability up -d
   ```

   Give it about 30 seconds — five processes start inside the container.
   Verify it's up: `docker compose ps otel` should show `healthy`, and
   http://localhost:3000 should open Grafana (no login; the image runs it
   with anonymous admin access).

2. Run the API with the trace SDK switched on, which
   `ruby/.env.development` leaves off by default:

   ```sh
   cd ruby
   OTEL_SDK_DISABLED=false CORS_ALLOWED_ORIGIN=http://localhost:5173 bundle exec bin/server
   ```

   Verify spans are landing: make a request (`curl http://localhost:9292/healthz`),
   then in Grafana open **Explore → Tempo → Search** and search for service
   name `stack-api`. A `GET /healthz` trace shows up within a few seconds.

3. Confirm the whole stack at once:

   ```sh
   bin/doctor
   ```

   Its `Observability` section checks both OTLP ports and Grafana. With the
   profile stopped it says so and leaves the exit status alone, since none of
   this is required.

The collector's config is `docker/otel/otelcol-config.yaml`, mounted over the
one the image ships with — the same arrangement as
`docker/postgres/init-databases.sh`, and for the same reason: container
configuration this app owns belongs in the repo, committed and diffable. It
is the stock pipeline plus two things:

- **CORS for `http://localhost:5173`** on the OTLP/HTTP receiver, so the Vue
  client can export straight to the collector from the browser. Nothing sends
  from the browser yet; the entry is what will let it.
- **The `spanmetrics` connector**, deriving rate/error/duration metrics from
  the spans as they pass through. This is why the Ruby app ships no metrics
  code at all (see above): the series are computed here instead, from the one
  signal the app does emit. They land in Prometheus as
  `traces_span_metrics_calls_total` and
  `traces_span_metrics_duration_milliseconds_*`, labelled with the route
  template, method and status code off each span.

Everything the backend stores lives in the `otel_data` volume, so traces
survive a restart. To reclaim the space:

```sh
docker compose --profile observability down -v
```

### Querying it from an agent

`.mcp.json` registers Grafana's own MCP server
([mcp-grafana](https://github.com/grafana/mcp-grafana)) at project scope, so
an agent can search traces, run PromQL and read dashboards directly rather
than being told what they say. It needs two things on your machine:

- **`uvx`** ([uv](https://github.com/astral-sh/uv)) on `PATH`, which is what
  runs the server.
- **`GRAFANA_MCP_KEY`**, a Grafana service account token. The backend creates
  one on first start; read it out of the running container:

  ```sh
  docker compose exec otel cat /etc/lgtm/mcp.json
  ```

  Export it from your shell profile. It is deliberately *not* committed —
  `.mcp.json` only names the variable — and it lives in Grafana's database
  inside the `otel_data` volume, so the `down -v` above invalidates it and
  the next start issues a new one.

Two caveats worth knowing before you debug a silent server. A shell profile
that exports it from `~/.zshrc` only reaches *interactive* shells, so an
editor or desktop app launched from the GUI won't see it; `~/.zprofile` is
the file that covers both. And Grafana here runs with anonymous admin access,
so curling an endpoint with a bad token still returns 200 — `/api/user` is
the one that actually rejects it, and is the honest way to check a token
works.

## Memory footprint

Four independent checks, each an isolated subprocess (so a reading reflects
only what it measures, not whatever else is loaded in the process taking
it) and each runnable on its own:

```sh
cd ruby
bundle exec rake memory:rss:boot         # current RSS after boot
bundle exec rake memory:rss:request      # RSS growth from a GraphQL + REST request cycle
bundle exec rake memory:profile:boot     # allocation breakdown of boot, by gem/file/class
bundle exec rake memory:profile:request  # allocation breakdown of the same request cycle
```

`rss:*` uses the `get_process_mem` gem to read resident memory (what the OS
says the process actually occupies — interpreter, C extensions, everything).
`profile:*` uses [memory_profiler](https://github.com/SamSaffron/memory_profiler)
for a detailed breakdown of Ruby-level object allocations by gem, file, and
class — a different, narrower measurement (see the tradeoffs above); the two
numbers are not expected to match. Both `profile:*` tasks print the full
report and also save a copy under `ruby/tmp/` (gitignored — these are
point-in-time diagnostic dumps, not committed history).

The "request" checks exercise the `saveNote` mutation, the `notes` query,
and REST create + list against `/api/v1/notes`, wrapped in a rolled-back
transaction (`lib/memory_workload.rb`) so they never leave persisted rows
behind, whichever database `APP_ENV` points at. All 4 require a running,
migrated Postgres (same prerequisite as the IRB console above).

```sh
bundle exec rake memory:snapshot   # run all 4 and append one combined row to benchmarks/memory.csv
bundle exec rake memory:report     # print recent snapshots and deltas from that log
```

`memory:snapshot` is the one to run as you make changes — it appends a
single row (timestamp, git SHA — `+dirty` if `ruby/` has uncommitted
changes — Ruby version, and all 4 metrics) to `ruby/benchmarks/memory.csv`,
which is committed history, diffable across commits as the app grows.
