module EnableBankingItem::Provided
  extend ActiveSupport::Concern

  def enable_banking_provider
    return nil unless credentials_configured?

    Provider::EnableBanking.new(
      application_id: application_id,
      client_certificate: client_certificate
    )
  end

  # Send current user context for manual syncs, even when the bank does not
  # mandate specific headers. Scheduled syncs never claim the user is online.
  def build_psu_headers
    EnableBankingItem::PsuContext.headers_for(
      Current.enable_banking_psu_context,
      family_id: family_id,
      required_headers: aspsp_required_psu_headers
    )
  end
end
