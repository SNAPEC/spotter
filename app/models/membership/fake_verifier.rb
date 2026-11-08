# Stands in for the membership API: every address is a member until the end of the season (August 31),
# except one tagged "+nonmember", so the refusal path can be tried locally.
class Membership::FakeVerifier < Membership::Verifier
  SEASON_END = { month: 8, day: 31 }.freeze

  def call(email:)
    return { valid: false, expires_on: nil } if email.to_s.split("@").first.to_s.end_with?("+nonmember")

    { valid: true, expires_on: season_end }
  end

  private
    def season_end
      today = Date.current
      this_year = Date.new(today.year, SEASON_END[:month], SEASON_END[:day])
      today <= this_year ? this_year : this_year.next_year
    end
end
