require "rails_helper"

RSpec.describe User, "under concurrency", type: :model do
  self.use_transactional_tests = false
  after { [ AuditEvent, RecoveryCode, Passkey, Session, User ].each(&:delete_all) }

  def race(count, &block)
    gate = Concurrent::CountDownLatch.new(1)
    threads = count.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.wait
          block.call(index)
        end
      end
    end
    gate.count_down
    threads.map(&:value)
  end

  it "keeps 2 admins when two of 3 are demoted at once, without deadlock" do
    10.times do |round|
      admins = 3.times.map { |n| User.create!(email: "admin#{round}-#{n}@example.com", role: "admin") }

      outcomes = race(2) { |index| User.find(admins[index].id).update(role: "analyst") }

      expect(outcomes).to contain_exactly(true, false)
      expect(User.admin.count).to eq(2)
      User.delete_all
    end
  end

  it "accepts a recovery code once across concurrent attempts" do
    user = User.create!(email: "analyste@example.com", role: "analyst")
    code = user.generate_recovery_codes!.first

    outcomes = race(6) { User.find(user.id).use_recovery_code!(code) }

    expect(outcomes.count(true)).to eq(1)
  end
end
