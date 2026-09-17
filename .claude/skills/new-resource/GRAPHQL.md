# GraphQL surface

Disclosed from [`SKILL.md`](SKILL.md) Step 4 — only read this when the resource actually needs a GraphQL surface.

## Type

`app/graphql/types/objects/<resource>_type.rb`:

```ruby
require_relative 'base_object'

module Types
  class XType < BaseObject
    description 'What this represents.'

    field :id, ID, null: false, description: 'The x id.'
    field :some_column, String, null: false, description: 'What this field holds.'
  end
end
```

Every `field` needs `description:`, and the type itself needs a class-level
`description`. `rubocop-graphql`'s `GraphQL/FieldDescription` and
`GraphQL/ObjectDescription` enforce both — this isn't optional style.

## Enum (only if a state machine's states should be exposed)

No `Types::BaseEnum` exists yet in this repo — create it the first time:

```ruby
# app/graphql/types/base_enum.rb
module Types
  class BaseEnum < GraphQL::Schema::Enum
  end
end
```

Then, per resource:

```ruby
module Types
  module Enums
    class XStateType < Types::BaseEnum
      value 'PENDING', 'Description of this state.', value: 'pending'
    end
  end
end
```

## Mutation

`app/graphql/mutations/<verb>_<resource>.rb`:

```ruby
require_relative 'base_mutation'
require_relative '../types/objects/x_type'

module Mutations
  class VerbX < BaseMutation
    description 'What this mutation does.'

    argument :some_input, String, required: true, description: '...'

    field :x, Types::XType, null: false, description: 'The result.'

    sig { params(some_input: String).returns(T::Hash[Symbol, X]) }
    def resolve(some_input:)
      { x: Services::VerbX.new(some_input:).call }
    end
  end
end
```

Don't rescue `Sequel::ValidationFailed`, `Sequel::NoMatchingRow`, or
`StateMachines::Sequel::FailedTransition` here — `AppSchema` translates all
three to a client-facing `GraphQL::ExecutionError` once, centrally, via
`rescue_from` (`app/graphql/schemas/app_schema.rb`), so every mutation
reports the same failure the same way without repeating the rescue. Only add
a local `rescue` for an error that mutation alone can raise.

Wire it into the schema: `field :verb_x, mutation: Mutations::VerbX` on
`Types::MutationType`, plus a `require_relative '../mutations/verb_x'` at the
top of that file (each root type/mutation file explicitly requires what it
references — there's no autoloading here).

### Input object (mutation takes several optional attributes)

Once a mutation updates more than one or two attributes, group them into an
input object instead of listing each as a top-level `argument`.
`Types::Inputs::BaseInputObject` already exists — reuse it, don't recreate it:

```ruby
# app/graphql/types/inputs/x_attributes_input.rb
require_relative 'base_input_object'

module Types
  module Inputs
    class XAttributesInput < BaseInputObject
      description 'Attributes to update on an x.'

      argument :some_column, String, required: false, description: 'What this field holds.'
    end
  end
end
```

Then take it as a single `argument`:

```ruby
argument :x_attributes, Types::Inputs::XAttributesInput, required: true, description: 'The attributes to update.'

sig { params(id: String, x_attributes: Types::Inputs::XAttributesInput).returns(T::Hash[Symbol, X]) }
def resolve(id:, x_attributes:)
  { x: Services::UpdateX.new(id: id.to_i, some_column: x_attributes.some_column).call }
end
```

## Query field

Add to `Types::QueryType`:

```ruby
field :xs, XType.connection_type, null: false, description: 'All xs.', max_page_size: 25

field :x, XType, null: true, description: 'A single x by id, or null when none exists.' do
  argument :id, ID, required: true, description: 'The x id.'
end

sig { returns(Sequel::Dataset) }
def xs
  X.dataset.order(:id)
end

sig { params(id: String).returns(T.nilable(X)) }
def x(id:)
  X.first(id: Integer(id))
rescue ArgumentError
  nil
end
```

(plus a `require_relative 'objects/x_type'` at the top of `query_type.rb`,
same reason as the mutation require above).

The plural field's method name must match the field name exactly (no
`resolver_method:`) — that's how GraphQL-Ruby finds it. `Integer(id)` raises
`ArgumentError` on a non-numeric id; rescuing it to `nil` keeps a malformed id
a null result instead of a 500, matching what a missing id already returns.
If the resource has a state that should act deleted (e.g. `archived`), filter
it out of both fields' datasets — `X.dataset.exclude(state: 'archived')` — a
`state` filter is call-site logic, not something a generic query field
template can bake in.

`max_page_size` is not optional once `AppSchema` has `max_complexity`/
`max_depth` set (it does): an unbounded connection field can make every query
against it fail with "exceeds max complexity," which only shows up at
runtime, not at type-check time. Pick a page size that fits the resource's
actual field count under the schema's `max_complexity`, and only raise
`max_complexity` in `app/graphql/schemas/app_schema.rb` if a legitimately
larger page size needs it.

## After any of the above

Run `bundle exec rake graphql:schema:dump` in `ruby/` to regenerate the
committed `app_schema.graphql`. If a Vue operation/composable needs the new
type/field/mutation, see `CLAUDE.md`'s "Shared integration" section for the
`npm run generate` sync step — don't re-derive it here.
