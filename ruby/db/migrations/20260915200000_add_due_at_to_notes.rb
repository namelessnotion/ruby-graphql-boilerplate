# frozen_string_literal: true
# typed: ignore

Sequel.migration do
  change do
    alter_table(:notes) do
      add_column :due_at, DateTime
    end
  end
end
