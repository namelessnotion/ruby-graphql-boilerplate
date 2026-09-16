# frozen_string_literal: true
# typed: strict

require 'rack'
require_relative '../lib/observability'

# The observability seam for the Rack surface: the span that covers every
# request, and the log line for anything that escapes a surface.
#
# App mixes it in for both. The Roda apps mix it in for `log_unhandled` alone —
# their own `error_handler` blocks answer the REST error contract and would
# otherwise drop the exception entirely, leaving a 500 with nothing behind it.
#
# Deliberately not opentelemetry-instrumentation-rack: that gem's EventHandler
# can run `on_finish` on a different fiber than the one that ran `on_start`,
# which under Falcon is the ordinary case rather than an edge case, and a span
# that ends on a foreign fiber corrupts the context of whatever is running
# there. Opening and closing the span inside a single block keeps it on one
# fiber, and comes to about as much code as configuring the gem would.
module RequestTracing
  extend T::Sig

  # A Rack response triplet: HTTP status, header name/value pairs, and the
  # response body as an array of chunks. Defined here because this is where
  # the triplet gets taken apart; App picks it up through the include.
  RackResponse = T.type_alias { [Integer, T::Hash[String, String], T::Array[String]] }

  # Path segments that are record ids, collapsed so that `/api/v1/notes/1` and
  # `/api/v1/notes/2` share one span name. Span names become metric series
  # once the collector derives RED metrics from them, and a series per record
  # id is how a metrics backend falls over.
  RECORD_ID_SEGMENT = %r{/\d+(?=/|\z)}

  # Pulled in under short names because they appear on both the span and the
  # log line, and the fully qualified constants are longer than the code that
  # uses them.
  HTTP_METHOD = OpenTelemetry::SemanticConventions::Trace::HTTP_METHOD
  HTTP_ROUTE = OpenTelemetry::SemanticConventions::Trace::HTTP_ROUTE
  HTTP_STATUS_CODE = OpenTelemetry::SemanticConventions::Trace::HTTP_STATUS_CODE

  # The line that says what actually broke. Public because the Roda apps call
  # it from their error handlers; the rest of this module is App's business.
  sig { params(request: Rack::Request, error: StandardError).void }
  def log_unhandled(request, error)
    Observability::Log.error(
      'unhandled exception',
      HTTP_METHOD => request.request_method,
      HTTP_ROUTE => route_template(request),
      'exception.type' => error.class.name,
      'exception.message' => error.message
    )
  end

  # Collapses record ids, so a log line and its span agree on the route.
  sig { params(request: Rack::Request).returns(String) }
  def route_template(request)
    request.path.gsub(RECORD_ID_SEGMENT, '/:id')
  end

  private

  # Runs the block inside the request's server span and returns its Rack
  # response, having recorded the response status on the span.
  #
  # An exception raised by the block is recorded and marks the span failed
  # before it propagates, so the caller's own rescue only has to decide what
  # to answer the client.
  sig { params(request: Rack::Request, '&': T.proc.returns(RackResponse)).returns(RackResponse) }
  def trace_request(request, &)
    route_name = route_template(request)
    attributes = { HTTP_METHOD => request.request_method, HTTP_ROUTE => route_name }

    # Picks up a `traceparent` the browser sent, so one trace covers the click
    # and the API call rather than breaking in two at the network boundary.
    Observability.continue_trace(request.env) do
      Observability.in_span("#{request.request_method} #{route_name}", kind: :server, **attributes) do |span|
        record_status(span, yield)
      end
    end
  end

  # The status is only known once the surface has answered, so it goes on the
  # span on the way out rather than at span start.
  #
  # A 5xx marks the span failed even though nothing was raised here: each Roda
  # app catches exceptions in its own error_handler and answers 500, which
  # this span would otherwise record as an ordinary response. 4xx is left
  # alone, per the HTTP semantic conventions — a client asking for a note that
  # does not exist is not the API failing, and counting it as one would put
  # every 404 into the error rate the collector derives from these spans.
  sig { params(span: OpenTelemetry::Trace::Span, response: RackResponse).returns(RackResponse) }
  def record_status(span, response)
    status = response.first
    span.set_attribute(HTTP_STATUS_CODE, status)
    span.status = OpenTelemetry::Trace::Status.error("HTTP #{status}") if status >= 500
    response
  end
end
