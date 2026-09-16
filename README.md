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

1. **Ruby API** (GraphQL + REST) — `bin/server` defaults to port 9292, but the
   Vue client expects `http://localhost:3000/graphql`, so bind it to port 3000
   and allow the Vite dev origin through CORS:

   ```sh
   cd ruby
   LISTEN_ADDR=http://0.0.0.0:3000 CORS_ALLOWED_ORIGIN=http://localhost:5173 bundle exec bin/server
   ```

   Verify it's up: `curl http://localhost:3000/healthz` should return
   `{"status":"ok"}`.

2. **Vue client** (Vite dev server, defaults to port 5173):

   ```sh
   cd vuejs
   npm install   # first time only
   npm run dev
   ```

   Open http://localhost:5173 — it talks to the API at
   `http://localhost:3000/graphql` by default (override with a `VITE_GRAPHQL_URL`
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
curl http://localhost:3000/api/v1/notes
curl -X POST http://localhost:3000/api/v1/notes \
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

It checks Postgres, Redis, the Ruby API, a Resque worker, and the Vite/Vue
client, reading connection details from `ruby/.env.development`. Override
`API_URL` / `VITE_URL` if you've bound those somewhere other than this
README's defaults (`http://localhost:3000` and `http://localhost:5173`).
Exits non-zero if anything's down.

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
