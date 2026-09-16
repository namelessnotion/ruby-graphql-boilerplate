import { propagation, trace } from '@opentelemetry/api'
import { W3CTraceContextPropagator } from '@opentelemetry/core'
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http'
import { resourceFromAttributes } from '@opentelemetry/resources'
import { ATTR_SERVICE_NAME } from '@opentelemetry/semantic-conventions'
import { BatchSpanProcessor, WebTracerProvider } from '@opentelemetry/sdk-trace-web'

// Named once so the OTel resource and every log line's `service.name` agree
// on who emitted it, mirroring ruby/lib/observability.rb's SERVICE_NAME.
const SERVICE_NAME = 'stack-client'

// Identifies this app's own hand-written spans.
const INSTRUMENTATION_NAME = 'stack-client'

// Tier 2: OTLP export, opt-in via VITE_OTEL_EXPORTER_OTLP_ENDPOINT so a
// developer with no collector running pays no wasted export retries. Left
// unset, the global tracer provider stays the OpenTelemetry API's own no-op —
// spans still open and close, they just record nothing and cost nothing.
//
// No ZoneContextManager here: automatic context propagation across promises
// needs zone.js, which is heavy and invasive. Every network call in this app
// goes through the single Apollo link chain (see lib/apollo-client.ts), which
// creates and ends its spans explicitly instead of relying on ambient context.
const endpoint = import.meta.env.VITE_OTEL_EXPORTER_OTLP_ENDPOINT
if (endpoint) {
  const provider = new WebTracerProvider({
    resource: resourceFromAttributes({ [ATTR_SERVICE_NAME]: SERVICE_NAME }),
    spanProcessors: [new BatchSpanProcessor(new OTLPTraceExporter({ url: `${endpoint}/v1/traces` }))],
  })
  provider.register({ propagator: new W3CTraceContextPropagator() })
}

export const tracer = () => trace.getTracer(INSTRUMENTATION_NAME)

export { propagation, trace }

// Tier 1: structured logging, always on. One JSON object per console line, in
// the same field shape as ruby/lib/observability.rb's Formatter, so a browser
// log and a server log read the same way.
type Fields = Record<string, string | number | boolean | null | undefined>

function write(level: 'info' | 'warn' | 'error', message: string, fields: Fields) {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    'service.name': SERVICE_NAME,
    message,
    ...fields,
  }

  console[level === 'info' ? 'log' : level](JSON.stringify(entry))
}

export const Log = {
  info: (message: string, fields: Fields = {}) => write('info', message, fields),
  warn: (message: string, fields: Fields = {}) => write('warn', message, fields),
  error: (message: string, fields: Fields = {}) => write('error', message, fields),
}
