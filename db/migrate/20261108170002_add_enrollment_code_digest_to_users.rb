class AddEnrollmentCodeDigestToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :enrollment_code_digest, :string
    add_index :users, :enrollment_code_digest, unique: true
  end
end
