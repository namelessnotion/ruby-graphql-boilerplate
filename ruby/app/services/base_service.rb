# frozen_string_literal: true
# typed: strict

module Services
  # BaseService is a base class for all services.
  class BaseService
    sig { params('&': T.proc.returns(T.untyped)).returns(T.untyped) }
    def perform(&)
      DB.transaction(savepoint: true, &)
    end
  end
end
