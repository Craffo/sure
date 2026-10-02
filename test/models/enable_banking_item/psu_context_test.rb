require "test_helper"
require "ostruct"

class EnableBankingItem::PsuContextTest < ActiveSupport::TestCase
  setup do
    @item = EnableBankingItem.new(family: families(:dylan_family), last_psu_ip: "8.8.4.4")
    @request = OpenStruct.new(remote_ip: "8.8.8.8", user_agent: "Sure test browser")
    @context = EnableBankingItem::PsuContext.capture(request: @request, family: @item.family)
  end

  test "manual sync supplies fresh headers even with an empty required list" do
    @item.aspsp_required_psu_headers = []
    Current.set(enable_banking_psu_context: @context) do
      assert_equal({ "Psu-Ip-Address" => "8.8.8.8", "Psu-User-Agent" => "Sure test browser" }, @item.build_psu_headers)
    end
  end

  test "background sync never reuses the IP from authorization" do
    @item.aspsp_required_psu_headers = [ "Psu-Ip-Address" ]
    Current.set(enable_banking_psu_context: nil) do
      assert_empty @item.build_psu_headers
    end
  end

  test "delayed sync stops asserting user presence" do
    Current.set(enable_banking_psu_context: @context) do
      travel 6.minutes do
        assert_empty @item.build_psu_headers
      end
    end
  end

  test "missing bank-required headers result in no partial context" do
    @item.aspsp_required_psu_headers = [ "PSU-IP-ADDRESS", "Psu-Accept" ]
    Current.set(enable_banking_psu_context: @context) { assert_empty @item.build_psu_headers }

    @item.aspsp_required_psu_headers = [ "PSU-IP-ADDRESS", "psu-user-agent" ]
    Current.set(enable_banking_psu_context: @context) { assert_equal 2, @item.build_psu_headers.size }
  end

  test "context cannot cross family boundaries" do
    @context["family_id"] = "another-family"
    Current.set(enable_banking_psu_context: @context) { assert_empty @item.build_psu_headers }
  end

  test "local browser supplies user agent without claiming a public IP" do
    @request.remote_ip = "127.0.0.1"
    context = EnableBankingItem::PsuContext.capture(request: @request, family: @item.family)
    Current.set(enable_banking_psu_context: context) do
      assert_equal({ "Psu-User-Agent" => "Sure test browser" }, @item.build_psu_headers)
      @item.aspsp_required_psu_headers = [ "Psu-Ip-Address" ]
      assert_empty @item.build_psu_headers
    end
  end
end
