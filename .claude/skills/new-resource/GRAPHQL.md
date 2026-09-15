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

`app/graphql/mutations/<verb>_<resource>.rb`, mirroring
`app/graphql/mutations/save_note.rb`:

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
    rescue Sequel::ValidationFailed => e
      raise GraphQL::ExecutionError, e.message
    end
  end
end
```

Wire it into the schema: `field :verb_x, mutation: Mutations::VerbX` on
`Types::MutationType`, plus a `require_relative '../mutations/verb_x'` at the
top of that file (each root type/mutation file explicitly requires what it
references — there's no autoloading here).

## Query field

Add to `Types::QueryType`:

```ruby
field :xs, XType.connection_type, null: false, description: 'All xs.', max_page_size: 25
```

(plus a `require_relative 'objects/x_type'` at the top of `query_type.rb`,
same reason as the mutation require above).

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
