class AddWebauthnChallengeToSessions < ActiveRecord::Migration[8.1]
  def change
    # Server-side and single-use: a challenge kept in the cookie could be replayed with an old cookie.
    add_column :sessions, :webauthn_challenge, :string
  end
end
