# An editing window exists only while the declarant may still edit.
class AddEditableUntilCheckToReports < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :reports,
      "editable_until IS NULL OR (taken_in_charge = FALSE AND status IN (#{Report::UNDER_ANALYSIS_STATUSES.map { |value| connection.quote(value) }.join(", ")}))",
      name: "reports_editable_until_check"
  end
end
