# frozen_string_literal: true
# typed: strict

# One recorded state transition of a Note, written by Note#commit_audit_log
# (wired via the `after_transition` hook in Note's state machine).
class AuditLog < Sequel::Model
  plugin :state_machine_audit_log
  extend T::Sig

  many_to_one :note
end
