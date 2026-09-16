import { ApolloClient, ApolloLink, InMemoryCache } from '@apollo/client'
import { MockLink } from '@apollo/client/testing'
import { propagation, trace } from '@opentelemetry/api'
import { W3CTraceContextPropagator } from '@opentelemetry/core'
import { InMemorySpanExporter, SimpleSpanProcessor, WebTracerProvider } from '@opentelemetry/sdk-trace-web'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { NotesDocument } from '@/gql/graphql'

import { errorLink, tracingLink } from '../apollo-client'
import { Log } from '../observability'

// Mirrors the Ruby suite's pattern (see ruby/lib/observability.rb): the
// tracer provider is otherwise the OpenTelemetry API's no-op, so a spec that
// asserts on spans installs an in-memory one for its own duration.
describe('tracingLink', () => {
  let exporter: InMemorySpanExporter

  beforeEach(() => {
    exporter = new InMemorySpanExporter()
    const provider = new WebTracerProvider({ spanProcessors: [new SimpleSpanProcessor(exporter)] })
    provider.register({ propagator: new W3CTraceContextPropagator() })
  })

  afterEach(() => {
    trace.disable()
    propagation.disable()
  })

  it('injects a W3C traceparent header on the outgoing operation', async () => {
    let capturedHeaders: Record<string, string> | undefined
    const captureLink = new ApolloLink((operation, forward) => {
      capturedHeaders = operation.getContext().headers as Record<string, string> | undefined
      return forward(operation)
    })

    const client = new ApolloClient({
      link: ApolloLink.from([
        tracingLink,
        captureLink,
        new MockLink([{ request: { query: NotesDocument }, result: { data: { notes: { edges: [] } } } }], {
          defaultOptions: { delay: 0 },
        }),
      ]),
      cache: new InMemoryCache(),
    })

    await client.query({ query: NotesDocument })

    expect(capturedHeaders?.traceparent).toMatch(/^00-[0-9a-f]{32}-[0-9a-f]{16}-0[01]$/)
  })

  it('ends the span it opened, even when the operation fails', async () => {
    const client = new ApolloClient({
      link: ApolloLink.from([
        tracingLink,
        new MockLink([{ request: { query: NotesDocument }, error: new Error('network down') }], {
          defaultOptions: { delay: 0 },
        }),
      ]),
      cache: new InMemoryCache(),
    })

    await expect(client.query({ query: NotesDocument })).rejects.toThrow()

    const spans = exporter.getFinishedSpans()
    expect(spans).toHaveLength(1)
    expect(spans[0]?.name).toBe('graphql.Notes')
  })
})

describe('errorLink', () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('logs the failure structurally', async () => {
    const errorSpy = vi.spyOn(Log, 'error').mockImplementation(() => {})

    const client = new ApolloClient({
      link: ApolloLink.from([
        errorLink,
        new MockLink([{ request: { query: NotesDocument }, error: new Error('network down') }], {
          defaultOptions: { delay: 0 },
        }),
      ]),
      cache: new InMemoryCache(),
    })

    await expect(client.query({ query: NotesDocument })).rejects.toThrow()

    expect(errorSpy).toHaveBeenCalledWith(
      'graphql operation failed',
      expect.objectContaining({
        'graphql.operation.name': 'Notes',
        'error.type': 'network',
        'error.message': 'network down',
      }),
    )
  })
})
