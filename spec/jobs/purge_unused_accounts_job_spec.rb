require "rails_helper"

RSpec.describe PurgeUnusedAccountsJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  def declarant(name = "moniteur") = User.create!(email: "#{name}@example.test")

  def run_on(date)
    travel_to(date) { 2.times { described_class.perform_now } }
  end

  def make_due(user)
    user.update_columns(purge_on: Date.current.prev_month.end_of_month)
  end

  describe "a declarant who never signed in" do
    it "is kept until the end of the month 30 days after creation, then deleted" do
      user = travel_to(Date.new(2026, 11, 17)) { declarant }

      expect(user.purge_on).to eq(Date.new(2026, 12, 31))
      run_on(Date.new(2026, 12, 31))
      expect(User.exists?(user.id)).to be(true)

      run_on(Date.new(2027, 1, 1))
      expect(User.exists?(user.id)).to be(false)
    end
  end

  describe "a declarant who signed in" do
    it "is kept until the end of the month 12 months after the last session expired" do
      user = travel_to(Date.new(2026, 11, 17)) { declarant.tap { |user| user.sessions.create! } }
      expect(user.reload.purge_on).to eq(Date.new(2027, 12, 31))

      travel_to(Date.new(2027, 1, 1)) { Session.purge_expired }
      run_on(Date.new(2027, 12, 31))
      expect(User.exists?(user.id)).to be(true)

      run_on(Date.new(2028, 1, 1))
      expect(User.exists?(user.id)).to be(false)
    end

    it "is pushed back at each sign-in, never brought forward" do
      user = travel_to(Date.new(2026, 11, 17)) { declarant.tap { |user| user.sessions.create! } }
      travel_to(Date.new(2027, 6, 3)) { user.sessions.create! }
      travel_to(Date.new(2027, 6, 4)) { user.sessions.create!(expires_on: Date.new(2027, 6, 30)) }

      expect(user.reload.purge_on).to eq(Date.new(2028, 7, 31))
    end

    it "is kept while a session is left" do
      user = declarant
      user.sessions.create!(expires_on: Date.current)
      make_due(user)

      run_on(Date.current)

      expect(User.exists?(user.id)).to be(true)
    end

    it "is kept while a report still points to it, and deleted once the link is overdue" do
      user = declarant
      report, = Report.start_draft!(mode: "confidential", user: user)
      make_due(user)

      run_on(Date.current)
      expect(User.exists?(user.id)).to be(true)

      run_on(report.report_ownership.cutoff_on)
      expect(User.exists?(user.id)).to be(false)
    end
  end

  it "never deletes staff" do
    staff = %w[analyst admin].map { |role| User.create!(email: "#{role}@example.test", role: role) }

    run_on(Date.current + 2.years)

    expect(User.where(id: staff.map(&:id)).count).to eq(2)
  end

  it "keeps an ex-staff member demoted to declarant, whom logs and audit events point to" do
    admin = User.create!(email: "admin@example.test", role: "admin")
    logged, reset = %w[journal audit].map { |name| User.create!(email: "#{name}@example.test", role: "analyst") }
    AccessLog.record!(user: logged, report: Struct.new(:id).new(SecureRandom.uuid), action: "view")
    reset.issue_enrollment_code!(by: admin)
    [ logged, reset ].each { |user| user.update!(role: "declarant"); make_due(user) }

    run_on(Date.current)

    expect(User.where(id: [ logged.id, reset.id ]).count).to eq(2)
  end

  it "goes on with the other accounts when one fails, logging only the error class" do
    failing, other = %w[un deux].map { |name| declarant(name).tap { |user| make_due(user) } }
    allow(ReportOwnership).to receive(:of).and_wrap_original do |original, user|
      raise ActiveRecord::StatementInvalid, "secret detail" if user.id == failing.id

      original.call(user)
    end
    io = StringIO.new
    Rails.logger.broadcast_to(capture = Logger.new(io))

    described_class.perform_now

    expect(User.exists?(failing.id)).to be(true)
    expect(User.exists?(other.id)).to be(false)
    expect(io.string).to include("ActiveRecord::StatementInvalid")
    expect(io.string).not_to include("secret detail")
  ensure
    Rails.logger.stop_broadcasting_to(capture) if capture
  end

  it "deletes the account's codes with it, through the usual deletion" do
    user = declarant
    user.generate_recovery_codes!
    make_due(user)

    run_on(Date.current)

    expect(User.exists?(user.id)).to be(false)
    expect(RecoveryCode.where(user_id: user.id)).to be_empty
  end

  it "is scheduled daily at 3:00" do
    recurring = Rails.application.config_for(:recurring, env: "production")

    expect(recurring[:purge_unused_accounts]).to include(class: "PurgeUnusedAccountsJob", schedule: "every day at 3am")
  end
end
