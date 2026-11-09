require "rails_helper"
require Rails.root.join("spec/support/submittable")

# End to end: whatever path a request or a report takes, the client's IP address must end up nowhere.
# Not covered: the Solid Queue tables, since the test adapter keeps jobs in memory, and the separate
# production cache and queue databases. The risk is low: job arguments are records, never request data,
# and the rate limiter keys the cache on an HMAC of the IP, which this spec checks.
RSpec.describe "No IP address anywhere", type: :request do
  include ActiveJob::TestHelper

  let(:ip) { "203.0.113.7" }
  let(:spoofed_ip) { "198.51.100.23" }
  let(:env) { { "REMOTE_ADDR" => ip } }
  let(:log) { StringIO.new }
  let(:cache_keys) { [] }

  before do
    TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish!
    ActionMailer::Base.deliveries.clear
    Rails.configuration.x.rate_limit_store.clear
  end

  # Every component logger is this broadcast logger: SQL with its binds, requests, jobs.
  around do |example|
    logger = ActiveSupport::Logger.new(log, level: :debug)
    Rails.logger.broadcast_to(logger)
    subscriber = ActiveSupport::Notifications.subscribe(/\Acache_\w+\.active_support\z/) do |*, payload|
      cache_keys << payload[:key].to_s
    end
    example.run
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
    Rails.logger.stop_broadcasting_to(logger)
  end

  def sign_in_over_http(email)
    post login_path, params: { email: email }, env: env
    expect(response).to have_http_status(:ok)
    perform_enqueued_jobs
    path = URI(ActionMailer::Base.deliveries.last.text_part.body.decoded[%r{http://\S+/login/\S+}]).path
    get path, env: env
    post path, env: env
    expect(response).to have_http_status(:redirect)
  end

  # Cast to text, every column of every table: the type of a leak is not known in advance.
  def raw_columns_containing(needle)
    connection = ActiveRecord::Base.connection
    connection.tables.flat_map do |table|
      connection.columns(table).filter_map do |column|
        count = connection.select_value(<<~SQL.squish)
          SELECT count(*) FROM #{connection.quote_table_name(table)}
          WHERE #{connection.quote_column_name(column.name)}::text LIKE #{connection.quote("%#{needle}%")}
        SQL
        "#{table}.#{column.name}" if count.positive?
      end
    end
  end

  # Encrypted columns hold ciphertext: read them again through their models, decrypted.
  def decrypted_records_containing(needle)
    Rails.autoloaders.main.eager_load_dir(Rails.root.join("app/models"))
    ApplicationRecord.descendants.reject(&:abstract_class?).select { |model| model.encrypted_attributes.present? }.flat_map do |model|
      model.unscoped.filter_map { |record| "#{model.name}##{record.id}" if record.attributes.to_json.include?(needle) }
    end
  end

  it "leaves no trace of the client IP after a full journey through the app" do
    declarant = User.create!(email: "declarant@example.test")
    analyst = User.create!(email: "analyste@example.test", role: "analyst")

    sign_in_over_http(declarant.email)
    get root_path, env: env
    expect(response).to have_http_status(:ok)

    # Rails' spoofing check fires on conflicting headers; its message would carry both addresses.
    post login_path, params: { email: declarant.email }, env: env, headers: { "Client-IP" => spoofed_ip, "X-Forwarded-For" => ip }
    expect(response).to have_http_status(:bad_request)

    # Action Cable logged the client address on connection: it is removed, and its route must stay gone.
    get "/cable", env: env
    expect(response).to have_http_status(:not_found)

    sign_in_over_http(analyst.email)
    post recovery_code_path, params: { code: analyst.generate_recovery_codes!.first }, env: env
    # A recovered session only enrols a passkey; this journey skips the WebAuthn ceremony.
    analyst.sessions.sole.update!(recovered: false)
    get analyst_root_path, env: env
    expect(response).to have_http_status(:ok)

    report, _token = Report.start_draft!(mode: "confidential", user: declarant)
    report.save_draft!(event_type: "near_miss", narrative_attributes: { raw_text: "Récit fictif : une corde mal lovée au pied d'une voie imaginaire." })
    submittable(report).submit!
    anonymous, token = Report.start_draft!(mode: "anonymous")
    Report.find_draft_by_token(token).save_draft!(narrative_attributes: { raw_text: "Récit fictif d'un mousqueton mal verrouillé." })
    submittable(anonymous.reload).submit!
    perform_enqueued_jobs
    expect(report.reload).to be_in_validation

    AccessLog.record!(user: analyst, report: report, action: "take_charge")
    report.ask_clarification!(analyst, "Pouvez-vous préciser le type de corde ?")
    perform_enqueued_jobs { ClarificationDigestJob.perform_now }
    report.answer_clarification!("Une corde à simple de 60 mètres, fictive.", user: declarant)
    report.validate!(analyst)
    AccessLog.record!(user: analyst, report: report, action: "validate")
    anonymous.reject!(analyst)

    delete session_path, env: env
    expect(response).to redirect_to(login_path)

    expect(ActionMailer::Base.deliveries.size).to eq(3)
    # Read before searching the database: the search queries hold the address and are logged too.
    logged = log.string.dup
    [ ip, spoofed_ip ].each do |needle|
      expect(raw_columns_containing(needle)).to be_empty, "#{needle} found in the database"
      expect(decrypted_records_containing(needle)).to be_empty, "#{needle} found in decrypted records"
      expect(logged).not_to include(needle)
      expect(cache_keys.join("\n")).not_to include(needle)
      expect(performed_jobs.inspect).not_to include(needle)
      expect(ActionMailer::Base.deliveries.map(&:to_s).join).not_to include(needle)
    end
    expect(logged).to include("Started POST", "INSERT INTO \"sessions\"")
    expect(cache_keys).not_to be_empty
  end
end
