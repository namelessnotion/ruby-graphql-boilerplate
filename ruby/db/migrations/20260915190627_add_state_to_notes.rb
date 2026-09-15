# frozen_string_literal: true
# typed: ignore

Sequel.migration do
  change do
    alter_table(:notes) do
      add_column :state, String, null: false, default: 'pending'
    end
  end
end
