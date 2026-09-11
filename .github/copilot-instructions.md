# Stack guidelines

This repository is a boilerplate for a Ruby GraphQL API and a Vue client. Keep
the applications independent: Ruby code and its tooling live in `ruby/`; Vue
code and its tooling live in `vuejs/`.

## Non-negotiable quality gates

- Use test-driven development: write or update a failing test before implementing
  a behavior change, then make it pass and refactor only while the full relevant
  test set remains green.
- Never bypass, disable, exclude, or weaken a linter, test, or type checker.
  Do not use suppression flags, inline disables, `--no-verify`, `skipLibCheck`,
  `# typed: ignore`, `T.unsafe`, or broad type assertions to avoid fixing an
  underlying problem.
- Add regression coverage for every bug fix and focused tests for every new
  behavior. Test public behavior, error cases, and important boundaries.
- Run the smallest relevant checks after a change, then run all required checks
  for the affected application before considering the work complete.

## Ruby API (`ruby/`)

- Use Ruby 3.4, Falcon, Rack, GraphQL-Ruby, Sequel, PostgreSQL, Sorbet, RSpec,
  Factory Bot, and RuboCop.
- Preserve `# typed: strict` in application files. Define explicit Sorbet
  signatures and model domain types rather than relying on untyped hashes or
  implicit nilability.
- Keep GraphQL resolvers thin; place application behavior in services and
  persistence concerns in Sequel models. Validate inputs and return GraphQL
  errors deliberately rather than leaking database exceptions.
- Use RSpec for unit, request/schema, and integration coverage as appropriate.
  Use Factory Bot to create test data rather than manually duplicating fixtures.
- The app needs a live migrated PostgreSQL database when eager-loading models;
  use `docker compose up -d db` when database-backed tests or development need
  it. Use `APP_ENV=test`; boot loads `.env.test`, which supplies `DATABASE_URL`
  for test connections.
- Required checks for Ruby changes:

  ```sh
  cd ruby
  bundle exec rspec
  bundle exec rubocop
  bundle exec srb tc
  ```

## Vue client (`vuejs/`)

- Use Vue 3 Composition API with TypeScript. Prefer `<script setup lang="ts">`,
  typed props/emits, and composables for reusable stateful behavior.
- Use Apollo Client and `@vue/apollo-composable` for GraphQL operations. Keep
  operations typed, expose loading/error states, and avoid ad hoc `fetch` calls
  for GraphQL endpoints.
- Use Tailwind utility classes for styling. Keep styles responsive, accessible,
  and colocated with their components; do not introduce a competing CSS framework.
- Use Vitest and Vue Test Utils. Test component rendering, emitted events,
  loading/error UI, and GraphQL-composable behavior with mocks at the network
  boundary.
- Maintain a `lint` npm script for ESLint (including Vue and TypeScript rules)
  and do not merge Vue changes until it passes.
- Required checks for Vue changes:

  ```sh
  cd vuejs
  npm run lint
  npx vue-tsc -b
  npm test
  npm run build
  ```

## Shared integration

- Treat the GraphQL schema as a contract. When API schema behavior changes,
  update the Vue operation/composable and tests in the same change.
- Keep environment-specific connection URLs and secrets outside committed source.
  Document required variable names in an example environment file when one is
  introduced.
