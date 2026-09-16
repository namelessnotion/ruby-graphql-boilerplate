---
name: observability
description: Add or extend tracing, structured logging, or metrics in this stack's OpenTelemetry layer — where a span belongs, the shared JSON log field schema, how a metric gets derived rather than emitted, and how to run the local OTLP backend. Use when instrumenting a new code path in ruby/ or vuejs/, adding a field to a log line, or wiring up the observability compose profile.
---

# Observability

Two tiers, because the signals are not equally mature: structured logging is
always on and needs nothing running; tracing is the stable OpenTelemetry SDK
and is opt-in per process. There is no metrics tier in application code —
metrics are derived downstream from spans (Step 4). Ruby's half lives in
[`ruby/lib/observability.rb`](../../../ruby/lib/observability.rb); Vue's in
[`vuejs/src/lib/observability.ts`](../../../vuejs/src/lib/observability.ts).
Both are the single seam for their side — nothing else should import
`opentelemetry-api` / `@opentelemetry/api` directly.

## Step 1 — decide which tier this is

- **A span** covers a unit of work with a start and an end that you want on
  the trace: an I/O boundary, a transaction, a request. Go to Step 2 (Ruby) or
  Step 3 (Vue).
- **A log line** covers something you want to read on its own, outside a
  trace's shape — an unhandled exception, an event with no natural span, a
  line an operator greps for. Go to Step 5.
- **A metric** (rate, error count, duration histogram) is never emitted by
  application code here — see Step 4 before reaching for a metrics gem or
  package.

## Step 2 — add a span (Ruby)

Call `Observability.in_span(name, kind: ..., **attributes) { ... }` — never
`OpenTelemetry.tracer_provider` or `OpenTelemetry::Trace` directly. Three
spans already exist, each at a seam that covers many call sites at once
rather than one per resolver or route action:

- [`RequestTracing#trace_request`](../../../ruby/app/request_tracing.rb) — one
  server span per request, opened in `App#call`.
- [`Services::BaseService#perform`](../../../ruby/app/services/base_service.rb)
  — every service's write, since all of them call `perform`.
- [`AppSchema`'s `rescue_from` handlers](../../../ruby/app/graphql/schemas/app_schema.rb)
  — `Observability.record_exception` (not `in_span`; the span is already
  open) on the persistence exceptions GraphQL translates into client errors.

**pg, Redis, GraphQL, and Resque are already traced** by the instrumentation
gems `Observability.configure!` installs — do not hand-write a span around a
Sequel query, a Redis call, a GraphQL field, or a Resque job; you would be
duplicating a span that already exists.

A new hand-written span belongs at a seam not already covered by the above:
an outbound HTTP call to another service, a new async job type that is not
Resque, or a write path that does not go through `BaseService#perform`. When
you add one:

- **Name it low-cardinality.** `RequestTracing::RECORD_ID_SEGMENT` collapses
  `/api/v1/notes/1` to `/api/v1/notes/:id` before it becomes a span name,
  because span names become metric-series labels once the collector derives
  metrics from them (Step 4) — a span name carrying a record id is a
  metrics-cardinality bug, not just noisy.
- **Prefer a semantic-convention constant over a string key** when one exists
  (`OpenTelemetry::SemanticConventions::Trace::HTTP_METHOD`, as
  `RequestTracing` does) — a dotted string like `'http.method'` typed by hand
  drifts from the convention silently.
- **Decide whether an error should fail the span.** A 5xx or an unexpected
  exception should (`span.status = ...error(...)`, as `record_status` does
  for 5xx). A client error — bad input, a record that does not exist — should
  not: use `Observability.record_exception` alone, the way the `rescue_from`
  handlers do, so client mistakes stay out of the error rate a metric derives
  from spans.

Boot order matters: `Observability.configure!` runs from
[`ruby/lib/boot.rb`](../../../ruby/lib/boot.rb) after `pg`/`redis`/`resque`
are required but before any connection opens, because the instrumentation
gems patch client classes — a connection opened earlier is never traced. If
you introduce a new instrumented client, require it before `configure!` runs
and add its `OpenTelemetry::Instrumentation::*` to
`Observability.install_instrumentation`, not at the call site.

## Step 3 — add a span (Vue)

Call `tracer()` from `lib/observability.ts`
(`tracer().startSpan(name, { kind, attributes })`, `span.end()` in a
`finalize`), following
[`tracingLink` in `vuejs/src/lib/apollo-client.ts`](../../../vuejs/src/lib/apollo-client.ts)
— the only span-producing code on this side today, and the mechanism for
browser-to-server correlation: it injects a W3C `traceparent` header via
`propagation.inject(trace.setSpan(context.active(), span), headers)`, which
is what makes the browser span the parent of the Ruby server span that
answers it.

There is deliberately no `ZoneContextManager` — automatic context propagation
across promises needs zone.js, which is heavy and invasive for what this app
needs. Every network call already goes through the one Apollo link chain, so
spans are opened and ended explicitly instead of relying on ambient context.
A new span on this side follows the same pattern: open it explicitly at the
async boundary, inject `traceparent` into whatever request headers cross the
network, end it in a `finally`/`finalize`, and record + status-flag it on
error the way `tracingLink` does. Do not add a generic fetch/XHR
auto-instrumentation package — there is exactly one network path
(`ApolloClient`'s link chain), and adding one there is simpler than
instrumenting fetch globally.

If the server side of a new browser-originated call does not already read
`traceparent` (only `App#call`'s `Observability.continue_trace` does), and
you add CORS headers for it, remember the header allowlist: the `/graphql`
CORS preflight had to explicitly allow `traceparent`, or browsers silently
drop it and the trace breaks in two with green unit tests and no visible
error — see the comment in
[`ruby/app/app.rb`](../../../ruby/app/app.rb).

## Step 4 — a metric, i.e. don't add one in application code

Both the OpenTelemetry metrics and logs SDKs are pre-1.0 and break between
minor versions, so neither app ships metrics code. RED metrics (rate, error
count, duration) are derived instead by the collector's `spanmetrics`
connector, from the attributes already on spans — see
[`docker/otel/otelcol-config.yaml`](../../../docker/otel/otelcol-config.yaml).
To make a new dimension queryable as a metric label:

1. Put the attribute on the relevant span (Step 2/3) as a low-cardinality
   value — the same rule as span names.
2. Add it to `connectors.spanmetrics.dimensions` in
   `docker/otel/otelcol-config.yaml`.

Do not add `opentelemetry-sdk-metrics` (Ruby) or a metrics package (Vue) to
reach for this — it is the one thing this layer deliberately does not do in
app code.

## Step 5 — structured logging

Both sides write one JSON object per line in the same field shape, so a
server log and a browser log read identically:
`timestamp`, `level`, `service.name`, plus caller-supplied fields merged in.
Ruby additionally stamps `trace_id`/`span_id` from the span in scope
(`Observability::Log::Formatter#correlation`), omitted rather than
zero-filled when no span is open; Vue's `Log` does not carry those fields.

- Ruby: `Observability::Log.info/warn/error/debug(message, fields = {})` —
  `fields` is a flat hash, keyed with dotted semantic-convention-style
  strings for anything structured (`RequestTracing#log_unhandled` is the
  reference call site: `HTTP_METHOD => ..., 'exception.type' => ...`).
- Vue: `Log.info/warn/error(message, fields)` from `lib/observability.ts` —
  same shape, following `errorLink` in `apollo-client.ts`.

Reach for `Observability::Log`/`Log` at anything that escapes normal control
flow and would otherwise be silently dropped — the Roda `error_handler`
blocks and `App#call`'s rescue both call `log_unhandled` for exactly this
reason (an unhandled exception used to vanish entirely). Do not use `puts`,
`p`, `console.log`, or the bare stdlib `Logger` — they bypass the JSON shape
and the trace correlation.

## Step 6 — run the local backend

```sh
docker compose --profile observability up -d
```

Starts `grafana/otel-lgtm` (Collector + Tempo + Prometheus + Loki + Grafana)
behind the `observability` compose profile — opt-in, so a plain
`docker compose up -d` never starts it, and `OTEL_SDK_DISABLED` stays `true`
in both `ruby/.env.development` and `ruby/.env.test` until you deliberately
turn tracing on for a run. Full walkthrough — running the API with tracing
on, confirming a span lands in Tempo, `bin/doctor`'s Observability section,
what the collector config adds over the stock pipeline, and querying the
backend from an agent via the Grafana MCP server — is in `README.md`'s
**Observability**, **Observability backend**, and **Doctor** sections; read
those rather than re-deriving the commands here.

## Step 7 — verify

Follow `CLAUDE.md`'s TDD and required-checks rules for whichever app you
touched — that file is the source of truth and is already loaded. Tests that
assert on spans install their own `InMemorySpanExporter` for the example's
duration rather than relying on a running collector:
[`ruby/spec/support/recorded_spans.rb`](../../../ruby/spec/support/recorded_spans.rb)
(shared context `'with recorded spans'`) on the Ruby side,
[`vuejs/src/lib/__tests__/apollo-client.spec.ts`](../../../vuejs/src/lib/__tests__/apollo-client.spec.ts)
on the Vue side. Follow whichever one matches the side you're testing rather
than starting the observability profile for a test run.
