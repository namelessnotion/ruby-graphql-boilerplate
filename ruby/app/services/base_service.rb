# frozen_string_literal: true
# typed: strict

module Services
  # BaseService is a base class for all services.
  class BaseService
    # Every write in the app funnels through here, so one span per service
    # call is enough to see what the app spends its write time on — named for
    # the service that ran, with the transaction inside it.
    sig { params('&': T.proc.returns(T.untyped)).returns(T.untyped) }
    def perform(&)
      Observability.in_span(self.class.name.to_s) do
        DB.transaction(savepoint: true, &)
      end
    end
  end
end
