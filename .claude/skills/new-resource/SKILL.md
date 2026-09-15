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
`<resource>_audit_logs`-shaped table: `<resource>_id` FK + index, `event`,
`from_state`, `to_state`, `at` all `null: false`; `reason`, `messages`,
`actor` nullable. `db/migrations/20260915190628_create_audit_logs.rb` is a
worked example.

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

Hard requirement: add `gem 'state_machines'` to the Gemfile if it isn't
already there. `sequel-state-machine`'s own gemspec lists `state_machines`
only as a development dependency — without an explicit direct dependency the
plugin raises `NameError: uninitialized constant StateMachines::Error` at
`require` time under `bundle exec`, not just a Sorbet gap. Run `bundle
install` after adding it.

If audit-logged and no `AuditLog`-shaped model exists yet for this resource,
add one: `plugin :state_machine_audit_log`, `many_to_one :<resource>`.

Sorbet: run `bin/tapioca dsl <ModelName>`. The repo's custom
`sorbet/tapioca/compilers/sequel_model.rb` compiler and
`sorbet/rbi/shims/state_machines.rbi` already type columns, `validates_*`,
and state-machine/`timestamp_accessor` methods for any model generically —
no new compiler work needed unless this resource introduces a Sequel plugin
genuinely new to the repo.

If the resource has a write operation more involved than a plain `create`
(needed by either surface below), give it a service rather than putting the
logic in a resolver or route action — `app/graphql/mutations/save_note.rb`
and `app/api/v1/notes.rb` both call the same `Services::SaveNote`, one
service serving both surfaces:

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

`BaseService#perform` wraps the block in `DB.transaction(savepoint: true)`.

## Step 4 — GraphQL surface?

If Step 1 says yes: read [`GRAPHQL.md`](GRAPHQL.md). Otherwise skip to Step 6.

## Step 5 — REST surface?

If Step 1 says yes: read [`REST.md`](REST.md). Otherwise skip to Step 6.

## Step 6 — verify

Follow `CLAUDE.md`'s TDD and required-checks rules for the Ruby app
(`bundle exec rspec`, `bundle exec rubocop`, `bundle exec srb tc`) — don't
re-derive them here, that file is the source of truth and is already loaded.
