class VersionManifestFormat < ActiveRecord::Migration[8.1]
  def change
    # Existing history stays immutable and retains its original encoding.
    add_column :engagements_submissions, :manifest_format, :string, null: false, default: "ordered-json-v0"
    change_column_default :engagements_submissions, :manifest_format, from: "ordered-json-v0", to: "canonical-json-v1"
  end
end
