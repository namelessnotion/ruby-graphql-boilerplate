import { ApolloClient, ApolloLink, HttpLink, InMemoryCache } from '@apollo/client'
import { CombinedGraphQLErrors, CombinedProtocolErrors } from '@apollo/client/errors'
import { ErrorLink } from '@apollo/client/link/error'
import { context, propagation, SpanKind, SpanStatusCode, trace } from '@opentelemetry/api'
import { finalize, tap } from 'rxjs'

import { Log, tracer } from './observability'

// Opens a span around every GraphQL operation and injects a W3C `traceparent`
// header, so the browser span becomes the *parent* of the Ruby HTTP span that
// answers it — one trace covers the click through to the database write.
//
// Spans are created and ended explicitly, rather than relying on ambient
// context propagation (see lib/observability.ts for why there is no
// ZoneContextManager here).
export const tracingLink = new ApolloLink((operation, forward) => {
  const span = tracer().startSpan(`graphql.${operation.operationName ?? 'anonymous'}`, {
    kind: SpanKind.CLIENT,
    attributes: { 'graphql.operation.name': operation.operationName ?? '' },
  })

  const headers: Record<string, string> = {}
  propagation.inject(trace.setSpan(context.active(), span), headers)
  operation.setContext(({ headers: existing = {} }: { headers?: Record<string, string> }) => ({
    headers: { ...existing, ...headers },
  }))

  return forward(operation).pipe(
    tap({
      error: (error: unknown) => {
        span.recordException(error instanceof Error ? error : new Error(String(error)))
        span.setStatus({ code: SpanStatusCode.ERROR })
      },
    }),
    finalize(() => span.end()),
  )
})

// Normalizes whatever a failed operation threw into the flat, structured
// fields the JSON logger expects — the same shape whether the server
// returned GraphQL errors, a transport-level protocol error, or the network
// request itself failed.
export function errorFields(error: unknown): Record<string, string | number> {
  if (CombinedGraphQLErrors.is(error)) {
    return {
      'error.type': 'graphql',
      'error.message': error.message,
      'error.graphql_error_count': error.errors.length,
    }
  }

  if (CombinedProtocolErrors.is(error)) {
    return {
      'error.type': 'protocol',
      'error.message': error.message,
      'error.protocol_error_count': error.errors.length,
    }
  }

  return {
    'error.type': 'network',
    'error.message': error instanceof Error ? error.message : String(error),
  }
}

// Records what escaped, structurally, so a failed operation becomes a log
// line instead of a caught-and-discarded object. Components still own their
// own on-screen error message; this is the copy that reaches the log
// pipeline, for every operation rather than one component at a time.
export const errorLink = new ErrorLink(({ error, operation }) => {
  Log.error('graphql operation failed', {
    'graphql.operation.name': operation.operationName ?? 'anonymous',
    ...errorFields(error),
  })
})

export const apolloClient = new ApolloClient({
  link: ApolloLink.from([
    tracingLink,
    errorLink,
    new HttpLink({
      uri: import.meta.env.VITE_GRAPHQL_URL ?? 'http://localhost:9292/graphql',
    }),
  ]),
  cache: new InMemoryCache(),
})
