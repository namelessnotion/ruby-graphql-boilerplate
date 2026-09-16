/// <reference types="vite/client" />

// Declaration-merges with Vite's own `ImportMetaEnv` (declared in
// vite/client.d.ts), so `import.meta.env` carries Vite's built-ins (DEV,
// PROD, MODE, BASE_URL) alongside the app's own VITE_ variables. Redeclaring
// `ImportMeta` itself here is unnecessary and risks shadowing Vite's other
// `env`-adjacent members (`hot`, `glob`), so this only extends the env shape.
interface ImportMetaEnv {
  readonly VITE_GRAPHQL_URL?: string
  /**
   * OTLP/HTTP collector origin, e.g. `http://localhost:4318`. Unset by
   * default, which keeps the tracer provider as the OpenTelemetry API's own
   * no-op: spans still open and close, they just record nothing and cost
   * nothing. Set it to turn on browser trace export.
   */
  readonly VITE_OTEL_EXPORTER_OTLP_ENDPOINT?: string
}
