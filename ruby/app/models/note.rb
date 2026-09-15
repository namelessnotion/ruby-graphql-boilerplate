# frozen_string_literal: true
# typed: strict

# Model of persisted notes
class Note < Sequel::Model
  plugin :state_machine
  extend T::Sig

  one_to_many :audit_logs

  state_machine :state, initial: :pending do
    state :pending,
          :completed,
          :willnotdo,
          :archived

    event :complete do
      transition [:pending] => :completed
    end

    event :willnotdo do
      transition [:pending] => :willnotdo
    end

    event :archive do
      transition %i[pending completed willnotdo] => :archived
    end

    after_transition do |note, transition|
      note.commit_audit_log(transition)
    end
  end

  timestamp_accessors(
    [
      [{ to: 'completed' }, :completed_at],
      [{ to: 'archived' }, :archived_at]
    ]
  )

  sig { void }
  def validate
    super
    validates_presence [:note]
  end
end
