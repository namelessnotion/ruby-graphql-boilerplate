---
name: new-resource
description: Scaffold a new domain resource in this Ruby/Sequel/GraphQL/Roda stack — DB migration, Sequel model (validations, optional state machine), optional GraphQL type/enum/mutation/query, optional REST route/serialization. Use when adding a new persisted resource to ruby/, adding a GraphQL surface to an existing model, or adding a REST surface to an existing model.
---

# New resource

Migration and model are always built (Step 2-3); GraphQL and REST are separate branches (Step 4-5) — a resource can stop after the model if no API surface is needed yet, and either surface can be added later by re-running this skill against an existing model.

## Step 1 — confirm the data model

Before touching any file, you need, explicitly:

- Resource/table name and every column: name, type, nullability, default.
- Associations (`belongs_to`/`has_many`-shaped) to other resources.
- Whether it needs a state machine: initial state, every state, every event
  and the transitions it allows, and whether transitions should write an
  audit log (see Step 3).
- Which surfaces to build: migration+model only, +GraphQL, +REST, or both.

If any of this is missing, ask for it rather than guessing column types or
state names — this is the one step where a wrong guess propagates through
every later step.

## Step 2 — migration

```sh
bundle exec rake "db:new_migration[create_<table>]"
```

Fill in `Sequel.migration do change do ... end end`: `primary_key :id`, typed
columns with `null: false` where the data model says required,
`foreign_key :x_id, :xs, null: ..., index: true` for associations.

If the model needs a state machine, add a `state` column (`String, null:
false, default: '<initial state>'`) in this same migration — it does not
default to persisted otherwise, and `state` falls back to a plain in-memory
attribute that silently resets on every reload.

If transitions should be audited, add a companion migration for an
`<resource>_audit_logs`-shaped table:

```ruby
create_table(:x_audit_logs) do
  primary_key :id
  foreign_key :x_id, :xs, null: false, index: true
  String :event, null: false
  String :from_state, null: false
  String :to_state, null: false
  DateTime :at, null: false
  String :reason
  String :messages
  String :actor
end
```

Run it: `APP_ENV=test bin/migrate up` (and `APP_ENV=development bin/migrate
up` for local dev).

## Step 3 — Sequel model

`app/models/<resource>.rb`, `# typed: strict`, `class X < Sequel::Model`. No
`extend T::Sig` needed — `lib/core_ext/sorbet_sig.rb` includes `T::Sig` into
`Module` globally, so `sig` is already available on every class.

Validations: `validation_helpers` and `timestamps` are already active
globally (`lib/boot.rb`) — no per-model `plugin` call needed, just:

```ruby
sig { void }
def validate
  super
  validates_presence [:some_column]
end
```

For a nilable column, guard a `validation_helpers` comparison with `unless
field.nil?` rather than reaching for a conditional option — there isn't one,
and an unguarded comparison validator raises (`nil` has no `:>` method)
instead of reporting the column invalid:

```ruby
validates_operator(:>, Time.now, :due_at, message: 'must be in the future') unless due_at.nil?
```

State machine (only if Step 1 calls for one):

```ruby
plugin :state_machine

one_to_many :audit_logs # only if Step 2 added the audit_logs table

state_machine :state, initial: :pending do
  state :pending, :other_state
  event :do_thing do
    transition [:pending] => :other_state
  end
  after_transition do |model, transition| # only if audit-logged
    model.commit_audit_log(transition)
  end
end
```

If audit-logged and no `AuditLog`-shaped model exists yet for this resource,
add one: `plugin :state_machine_audit_log`, `many_to_one :<resource>`.

If a state should stamp a column when the model transitions into it (e.g. a
`completed_at`), add the column in the same migration as the state machine
and wire it with `timestamp_accessors`, outside the `state_machine` block:

```ruby
timestamp_accessors(
  [
    [{ to: 'completed' }, :completed_at]
  ]
)
```

Firing an event does not save. `model.do_thing!` mutates the state attribute
in memory only — reload the row and it is unchanged. `sequel-state-machine`
persists through two methods instead:

- `model.process(:do_thing)` — fires the event, saves, returns `true`/`false`.
- `model.must_process(:do_thing)` — same, but returns the model on success and
  raises `StateMachines::Sequel::FailedTransition` on an invalid transition.

Services driving a transition want `must_process`; the raised error is what a
resolver rescues. Note the raised class: it is **not**
`StateMachines::InvalidTransition` (what the bare `state_machines` gem raises
from `do_thing!`), so a spec asserting that class will pass against a
non-persisting implementation and fail against a correct one.

Sorbet: run `bin/tapioca dsl <ModelName>` after every migration — a new column
is invisible to `srb tc` until the model's RBI is regenerated, and the error
reads as a missing method (`Method 'due_at' does not exist on 'Note'`) rather
than as a stale RBI.

The repo's custom compilers in `sorbet/tapioca/compilers/` type columns,
`validates_*`, state-machine/`timestamp_accessor`/`process`/`must_process`
methods (`sequel_model.rb`) and GraphQL input-object argument readers
(`graphql_input_object.rb`) for any model or input type generically.

When `srb tc` reports a method that genuinely exists at runtime, that is a
compiler gap, not a typing problem in your code: extend the relevant compiler
and regenerate. Reaching for `T.unsafe`, a cast, or `# typed: ignore` to move
past it violates `CLAUDE.md`'s quality gates. A gem method missing entirely
usually means an empty gem RBI — check
`sorbet/rbi/gems/<gem>@<version>.rbi` for the `THIS IS AN EMPTY RBI FILE`
marker, add the gem to `sorbet/tapioca/require.rb` if it needs an explicit
require, and run `bundle exec tapioca gem <gem>`.

Give every write a service rather than putting the logic in a resolver or
route action, even a plain `create` — a GraphQL mutation and a REST route for
the same write both call the same service (Step 4 and Step 5's examples both
call into these), so the persistence logic is written once:

```ruby
# app/services/verb_x.rb
require_relative 'base_service'

module Services
  class VerbX < BaseService
    sig { params(some_input: String).void }
    def initialize(some_input:)
      super()
      @some_input = T.let(some_input, String)
    end

    sig { returns(X) }
    def call
      perform { X.create(some_column: @some_input) }
    end
  end
end
```

`BaseService#perform` wraps the block in `Observability.in_span(self.class.name)`
then `DB.transaction(savepoint: true)` — every write gets a span named for its
service for free; don't add a second one inside `call`.

A service driving a state-machine transition looks up the record and fires
the event through `must_process` instead of building anything:

```ruby
sig { returns(X) }
def call
  perform { X.with_pk!(@id).must_process(:do_thing) }
end
```

A service updating a subset of columns assigns only what was passed and
saves once — nilable params double as "leave this column alone":

```ruby
sig { returns(X) }
def call
  perform do
    record = X.with_pk!(@id)
    record.some_column = @some_column unless @some_column.nil?
    record.save_changes
    record
  end
end
```

## Step 4 — GraphQL surface?

If Step 1 says yes: read [`GRAPHQL.md`](GRAPHQL.md). Otherwise skip to Step 6.

## Step 5 — REST surface?

If Step 1 says yes: read [`REST.md`](REST.md). Otherwise skip to Step 6.

## Step 6 — verify

Follow `CLAUDE.md`'s TDD and required-checks rules for the Ruby app
(`bundle exec rspec`, `bundle exec rubocop`, `bundle exec srb tc`) — don't
re-derive them here, that file is the source of truth and is already loaded.
