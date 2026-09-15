# REST surface

Disclosed from [`SKILL.md`](SKILL.md) Step 5 — only read this when the resource actually needs a REST surface.

## Route file

`app/api/v1/<resources>.rb`, mirroring `app/api/v1/notes.rb` exactly —
`# typed: false` (Roda's routing DSL doesn't carry Sorbet sigs well, this
layer opts out deliberately):

```ruby
require 'roda'
require_relative '../../services/verb_x'

module Api
  module V1
    class Xs < Roda
      plugin :all_verbs
      plugin :json
      plugin :json_parser, content_type_regexp: %r{\Aapplication/json\b}i

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
        x = Services::VerbX.new(some_input: params['some_input']).call
        response.status = 201
        response['location'] = "/api/v1/xs/#{x.id}"
        serialize(x)
      rescue Sequel::ValidationFailed => e
        response.status = 422
        { errors: [e.message] }
      end

      def show_x(id)
        x = X[id]
        return serialize(x) if x

        response.status = 404
        { errors: ['x not found'] }
      end

      def serialize(x)
        { id: x.id, some_column: x.some_column, created_at: x.created_at, updated_at: x.updated_at }
      end
    end
  end
end
```

Error shape is always `{ errors: [...] }` with `response.status` set
explicitly (422 for validation failures, 404 for missing records) — match it
exactly so REST error handling stays uniform across resources.

## Mount it

In `app/api/v1/app.rb`: add `require_relative 'xs'` alongside the existing
`require_relative 'notes'`, and add one line to the route block, alongside
the existing `notes` line:

```ruby
r.on('xs') { r.run Api::V1::Xs }
```

CORS preflight and `/api/v1` versioning are handled once, centrally, in
`app/api/api_app.rb` — don't add per-resource OPTIONS handling or version
prefixes, the mount above is the only wiring needed.
