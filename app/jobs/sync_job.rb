class SyncJob < ApplicationJob
  queue_as :high_priority
  self.log_arguments = false

  # Accept a runtime-only flag to influence sync behavior without persisting config
  def perform(sync, balances_only: false, enable_banking_psu_context: nil)
    # Attach a transient predicate for this execution only
    begin
      sync.define_singleton_method(:balances_only?) { balances_only }
    rescue => e
      Rails.logger.warn("SyncJob: failed to attach balances_only? flag: #{e.class} - #{e.message}")
    end

    Current.set(enable_banking_psu_context: enable_banking_psu_context) do
      sync.perform
    end
  end
end
