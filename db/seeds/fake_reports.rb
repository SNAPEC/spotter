# Fictional accounts and RETEX for development and tests: every narrative is invented, every address is
# on the reserved example.test domain. Never loaded in production (see db/seeds.rb).
#
# Everything goes through the models' own lifecycle, so the invariants hold. The fake extractor stands
# in for the LLM and the analyzer runs synchronously, so no job nor network is involved.
#
# Idempotent: accounts are found by e-mail, and reports are generated only while the database holds
# none. A report cannot carry a marker (no link to a user, no date), so "no report yet" is the marker.
raise "Fictional seeds must never run in production" if Rails.env.production?

account_specs = {
  declarant: [ "declarant@example.test", "declarant" ],
  analyst: [ "analyste@example.test", "analyst" ],
  admin: [ "admin@example.test", "admin" ],
  admin2: [ "admin2@example.test", "admin" ]
}

accounts = account_specs.transform_values do |email, role|
  User.find_by(email: email) || User.create!(email: email, role: role)
end

return if Report.exists?

report_specs = [
  { status: "draft", mode: "confidential", event_type: "near_miss", discipline: "top_rope", environment: "indoor", cause: "communication_error",
    text: "Dans une salle fictive, l'assureur a retiré son système trop tôt pendant une descente en moulinette. Le grimpeur s'est arrêté à temps." },
  { status: "draft", mode: "anonymous", event_type: "incident", discipline: "bouldering", environment: "indoor", cause: "mats",
    text: "Un tapis disjoint a été repéré au pied d'un bloc d'une salle fictive après une réception décalée. Personne n'a été blessé." },
  { status: "submitted", mode: "anonymous", event_type: "near_miss", discipline: "lead", environment: "outdoor", cause: "technical_error",
    text: "Sur une falaise fictive du Sud, la corde est passée derrière la jambe d'un grimpeur en tête. Il l'a remarqué avant de chuter." },
  { status: "submitted", mode: "confidential", event_type: "incident", discipline: "abseil", environment: "outdoor", cause: "rope_too_short",
    text: "Pendant un rappel dans un site fictif, la corde s'est révélée trop courte de deux mètres. Le groupe s'est arrêté sur un relais intermédiaire." },
  { status: "analyzing", mode: "confidential", event_type: "accident", discipline: "multi_pitch", environment: "outdoor", cause: "gear_failure", severity: "moderate",
    text: "Un point d'assurage fictif a cédé dans une grande voie imaginaire. Le grimpeur est tombé de trois mètres et s'est fracturé le poignet.",
    casualties: [ { severity: "moderate", answers: { "age_range" => "from_40_to_59", "experience" => "experienced", "injury_location" => "shoulder_arm", "injury_nature" => [ "fracture" ] } } ] },
  { status: "in_validation", mode: "anonymous", event_type: "accident", discipline: "lead", environment: "indoor", cause: "belay_error", severity: "minor",
    text: "Dans une salle fictive, un assurage trop sec a fait heurter le mur à une grimpeuse. Contusion à l'épaule, séance terminée.",
    debrief: { debrief_causes: "Assureur distrait par une conversation.", debrief_message: "Rappelons la règle des trois regards avant de partir." },
    casualties: [ { severity: "minor", answers: { "age_range" => "from_18_to_39", "experience" => "intermediate", "injury_location" => "shoulder_arm", "injury_nature" => [ "bruise_wound" ] } } ] },
  { status: "in_validation", mode: "confidential", event_type: "incident", discipline: "top_rope", environment: "outdoor", cause: "tie_in_error", severity: "material_damage",
    text: "Un nœud d'encordement mal terminé a été repéré par un tiers sur un site fictif, avant le départ du grimpeur.",
    free_text_answers: { "material_damage" => "Corde fictive à remplacer" },
    clarification: "Pouvez-vous préciser qui a fait la vérification finale avant le départ ?" },
  { status: "in_validation", mode: "confidential", event_type: "near_miss", discipline: "approach", environment: "outdoor", cause: "hazardous_setting",
    text: "Sur le sentier d'approche d'une falaise fictive, un bloc instable s'est détaché près du groupe. Personne n'était dessous.",
    failed_analysis: true },
  { status: "in_validation", mode: "anonymous", event_type: "accident", discipline: "bouldering", environment: "outdoor", cause: "bad_landing", severity: "severe",
    text: "Lors d'une séance fictive en bloc, une réception sur un tapis mal placé a causé une chute sur le dos. Évacuation par les secours.",
    casualties: [ { severity: "severe", answers: { "age_range" => "from_12_to_17", "experience" => "beginner", "injury_location" => "spine", "injury_nature" => [ "fracture", "head_trauma" ] } },
                  { severity: "minor", answers: { "age_range" => "from_12_to_17", "experience" => "beginner", "injury_location" => "ankle_foot", "injury_nature" => [ "sprain" ] } } ] },
  { status: "validated", mode: "anonymous", event_type: "accident", discipline: "lead", environment: "indoor", cause: "belay_error", severity: "moderate",
    text: "Une chute en tête dans une salle fictive a été rattrapée trop tard. Entorse grave de la cheville.",
    casualties: [ { severity: "moderate", answers: { "age_range" => "from_40_to_59", "experience" => "intermediate", "injury_location" => "ankle_foot", "injury_nature" => [ "sprain" ] } } ] },
  { status: "validated", mode: "confidential", event_type: "incident", discipline: "auto_belay", environment: "indoor", cause: "installation_failure", severity: "material_damage",
    text: "Un enrouleur fictif ne s'est pas rétracté correctement en bas de voie. Retiré de l'usage le jour même." },
  { status: "validated", mode: "anonymous", event_type: "near_miss", discipline: "multi_pitch", environment: "outdoor", cause: "technical_error",
    text: "Dans une grande voie imaginaire, une corde non égalisée au relais a été repérée avant la manœuvre de rappel." },
  { status: "rejected", mode: "confidential", event_type: "near_miss", discipline: "trad", environment: "outdoor", cause: "communication_error",
    text: "Texte fictif trop vague pour être codé : un échange mal compris entre deux cordées, sans suite." },
  { status: "rejected", mode: "anonymous", event_type: "incident", discipline: "abseil", environment: "indoor", cause: "technical_error",
    text: "Signalement fictif en double d'un autre, rejeté par l'analyste." }
]

# The submission enqueues the analysis job: swap the queue for one that goes nowhere, so a report left
# "submitted" or "analyzing" stays so, and restore it whatever happens.
previous_adapter = ActiveJob::Base.queue_adapter
ActiveJob::Base.queue_adapter = :test
begin
  analyzer = Report::Analyzer.new(extractor: Llm::FakeExtractor.new)
  analyst = accounts.fetch(:analyst)

  report_specs.each do |spec|
    report, _token = Report.start_draft!(mode: spec[:mode], user: (accounts.fetch(:declarant) if spec[:mode] == "confidential"))
    report.save_draft!(
      spec.slice(:event_type, :discipline, :environment, :cause, :severity).merge(
        narrative_attributes: { raw_text: spec[:text], free_text_answers: spec.fetch(:free_text_answers, {}) }.merge(spec.fetch(:debrief, {})),
        casualties_attributes: spec.fetch(:casualties, [])
      )
    )
    next if spec[:status] == "draft"

    report.submit!
    next if spec[:status] == "submitted"

    if spec[:status] == "analyzing"
      report.start_analysis!
      next
    end

    spec[:failed_analysis] ? analyzer.record_failure(report, revision: report.content_revision) : analyzer.call(report, revision: report.content_revision)
    report.ask_clarification!(analyst, spec[:clarification]) if spec[:clarification]
    case spec[:status]
    when "validated"
      report.take_charge!(analyst)
      report.write_anonymized_text!(analyst, "Récit anonymisé fictif : un incident sans gravité dans un lieu fictif.")
      report.validate!(analyst)
    when "rejected" then report.reject!(analyst)
    end
  end
ensure
  ActiveJob::Base.queue_adapter = previous_adapter
end

puts "Seeded #{accounts.size} accounts and #{Report.count} fictional reports (sign in at /dev/login)."
