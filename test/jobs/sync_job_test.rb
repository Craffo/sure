require "test_helper"

class SyncJobTest < ActiveJob::TestCase
  test "user context survives family fanout and is cleared after the job" do
    family = families(:dylan_family)
    item = family.enable_banking_items.create!(name: "Bank", country_code: "IT", application_id: "test", client_certificate: "test")
    sync = family.syncs.create!
    context = { "family_id" => family.id, "requested_at" => Time.current.to_i, "headers" => { "Psu-User-Agent" => "Browser" } }
    child_syncer = Family::Syncer.new(family)
    child_syncer.stubs(:child_syncables).returns([ item ])
    family.stubs(:sync_trial_status!)
    sync.define_singleton_method(:perform) { child_syncer.perform_sync(self) }

    assert_enqueued_with(job: SyncJob, args: ->(args) { args.last[:enable_banking_psu_context] == context }) do
      SyncJob.perform_now(sync, enable_banking_psu_context: context)
    end
    assert_nil Current.enable_banking_psu_context
  end

  test "background job does not inherit ambient user presence" do
    sync = accounts(:depository).syncs.create!
    observed = :not_called
    sync.define_singleton_method(:perform) { observed = Current.enable_banking_psu_context }
    Current.set(enable_banking_psu_context: { "requested_at" => Time.current.to_i }) do
      SyncJob.perform_now(sync)
    end
    assert_nil observed
  end

  test "sync is performed" do
    syncable = accounts(:depository)

    sync = syncable.syncs.create!(window_start_date: 2.days.ago.to_date)

    sync.expects(:perform).once

    SyncJob.perform_now(sync)
  end
end
