# frozen_string_literal: true
# typed: ignore

Sequel.migration do
  change do
    create_table(:audit_logs) do
      primary_key :id
      foreign_key :note_id, :notes, null: false, index: true
      String :event, null: false
      String :from_state, null: false
      String :to_state, null: false
      DateTime :at, null: false
      String :reason
      String :messages
      String :actor
    end
  end
end
