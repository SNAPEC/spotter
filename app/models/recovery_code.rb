class RecoveryCode < ApplicationRecord
  COUNT = 10
  GROUPS = 4
  GROUP_LENGTH = 5
  # No 0/o, 1/l/i: the codes are copied by hand. 31 symbols over 20 characters give about 99 bits.
  ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789".chars.freeze

  belongs_to :user

  def self.generate
    codes = Set.new
    codes << Array.new(GROUPS) { SecureRandom.alphanumeric(GROUP_LENGTH, chars: ALPHABET) }.join("-") while codes.size < COUNT
    codes.to_a
  end

  # HMAC rather than bcrypt: the codes carry ~99 bits of entropy, so a slow hash adds nothing,
  # and a deterministic digest lets a code be found and deleted in one statement.
  def self.digest(code)
    OpenSSL::HMAC.hexdigest("SHA256", key, normalize(code))
  end

  def self.normalize(code)
    code.to_s.downcase.gsub(/[^a-z0-9]/, "")
  end

  def self.key
    Rails.application.key_generator.generate_key("recovery_code", 32)
  end
  private_class_method :key

  def code=(code)
    self.digest = self.class.digest(code)
  end
end
