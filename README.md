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

1. **Ruby GraphQL API** — `bin/server` defaults to port 9292, but the Vue
   client expects `http://localhost:3000/graphql`, so bind it to port 3000 and
   allow the Vite dev origin through CORS:

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
