# REST surface

Disclosed from [`SKILL.md`](SKILL.md) Step 5 — only read this when the resource actually needs a REST surface.

## Route file

`app/api/v1/<resources>.rb` — `# typed: false` (Roda's routing DSL doesn't
carry Sorbet sigs well, this layer opts out deliberately):

```ruby
require 'roda'
require_relative '../../request_tracing'
require_relative '../../services/verb_x'

module Api
  module V1
    # /api/v1/xs — mounted by Api::V1::App.
    class Xs < Roda
      include RequestTracing

      plugin :all_verbs
      plugin :json
      plugin :json_parser, content_type_regexp: %r{\Aapplication/json\b}i

      # See Api::App — each Roda app needs its own handler, since a nested app
      # that handles its own errors never lets them reach its parent.
      plugin :error_handler do |e|
        log_unhandled(request, e)
        response.status = 500
        { errors: ['internal server error'] }
      end

      route do |r|
        r.is do
          r.get { list_xs }
          r.post { create_x(r.params) }
        end

        r.is Integer do |id|
          r.get { show_x(id) }
        end
      end

      private

      def list_xs
        X.dataset.order(:id).map { |x| serialize(x) }
      end

      def create_x(params)
        some_input = params['some_input']
        # Services::VerbX's sig only accepts a String; a missing or
        # non-string param is a client error, not a 500.
        return unprocessable('some_input is not present') unless some_input.is_a?(String)

        x = Services::VerbX.new(some_input:).call
        response.status = 201
        response['location'] = "/api/v1/xs/#{x.id}"
        serialize(x)
      rescue Sequel::ValidationFailed => e
        unprocessable(e.message)
      end

      def show_x(id)
        x = X[id]
        return serialize(x) if x

        response.status = 404
        { errors: ['x not found'] }
      end

      def unprocessable(message)
        response.status = 422
        { errors: [message] }
      end

      def serialize(x)
        { id: x.id, some_column: x.some_column, created_at: x.created_at, updated_at: x.updated_at }
      end
    end
  end
end
```

`include RequestTracing` plus the `error_handler` block that calls
`log_unhandled` isn't optional boilerplate — without it, an exception that
escapes this Roda app is swallowed by `error_handler`'s 500 response with
nothing logged behind it. Every mounted Roda app in `app/api/` carries this
pair for the same reason (see `app/api/api_app.rb` and `app/api/v1/app.rb`).

Check a param's type before passing it into a service, as `create_x` does
above — `params` comes back as untyped `Hash`/`String`/`nil` from Roda/Rack,
while the service's `sig` expects a specific type. An unguarded call lets a
missing or wrong-shaped param reach the `sig`, which raises `TypeError` (a
500) instead of the 422 a client error should get.

Error shape is always `{ errors: [...] }` with `response.status` set
explicitly (422 for validation failures, 404 for missing records) — match it
exactly so REST error handling stays uniform across resources.

## Mount it

In `app/api/v1/app.rb`: add `require_relative 'xs'` alongside any other
resource requires there, and add one line to the route block alongside the
other resources:

```ruby
r.on('xs') { r.run Api::V1::Xs }
```

If this is the very first REST resource in the app, `app/api/v1/app.rb`
needs the mount's boilerplate too (`include RequestTracing`, its own
`error_handler` calling `log_unhandled`, and the `route` block) — copy the
shape shown in the route file above; only the `route` block's contents
differ (one `r.on('<resource>') { r.run Api::V1::<Resource> }` per mounted
resource instead of the leaf actions).

CORS preflight and `/api/v1` versioning are handled once, centrally, in
`app/api/api_app.rb` — don't add per-resource OPTIONS handling or version
prefixes, the mount above is the only wiring needed.
