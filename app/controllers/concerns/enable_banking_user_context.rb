module EnableBankingUserContext
  extend ActiveSupport::Concern

  private
    def with_enable_banking_user_context(&block)
      context = EnableBankingItem::PsuContext.capture(request: request, family: Current.family)
      Current.set(enable_banking_psu_context: context, &block)
    end
end
