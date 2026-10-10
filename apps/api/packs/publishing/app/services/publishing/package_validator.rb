require "zip"
require "digest"
require "timeout"

module Publishing
  class PackageValidator
    class BudgetExceeded < StandardError; end

    def self.call(candidate, bytes)
      checks = []
      check = ->(code, ok, expected, observed, fix) {
        checks << { code: code, ok: ok, expected: expected, observed: observed, fix: fix }
      }
      check.call("ARTIFACT_DIGEST", Digest::SHA256.hexdigest(bytes) == candidate.artifact_sha256, candidate.artifact_sha256, Digest::SHA256.hexdigest(bytes), "Upload a new candidate; stored bytes must match its immutable digest.")
      manifest = candidate.manifest
      shape = manifest.keys.sort == %w[contract_version entrypoint files schema_version title version] &&
        manifest["schema_version"] == 1 && manifest["contract_version"] == candidate.partner.contract_version &&
        manifest["title"].is_a?(String) && manifest["title"].length.between?(1, 100) &&
        manifest["version"].to_s.match?(/\A\d{1,5}\.\d{1,5}\.\d{1,5}\z/) &&
        manifest["entrypoint"] == "index.html" && manifest["files"].is_a?(Array) &&
        manifest["files"].length.between?(1, Settings::ENTRY_LIMIT)
      check.call("MANIFEST_SCHEMA", shape, "manifest-v1 / index.html / 1..16 files", shape ? "valid" : "invalid", "Use the documented manifest-v1 fields and contract version.")
      return checks unless shape

      files = manifest["files"]
      valid_files = files.all? { |row|
        row.is_a?(Hash) && row.keys.sort == %w[path sha256 size] && safe_path?(row["path"]) &&
          row["sha256"].to_s.match?(/\A[a-f0-9]{64}\z/) && row["size"].is_a?(Integer) && row["size"].between?(1, Settings::EXPANDED_LIMIT)
      } && files.map { |row| row["path"] }.uniq.length == files.length
      check.call("MANIFEST_FILES", valid_files, "unique relative files with size and SHA-256", valid_files ? "valid" : "invalid", "Remove duplicates, unsafe paths and unsupported metadata.")
      return checks unless valid_files

      names = []
      total = 0
      Timeout.timeout(3, BudgetExceeded) do
        Zip::File.open_buffer(bytes) do |zip|
          raise BudgetExceeded if zip.entries.length > Settings::ENTRY_LIMIT
          zip.entries.each do |entry|
            if !safe_path?(entry.name) || entry.ftype != :file
              check.call("ZIP_ENTRY_SAFE", false, "regular relative file", "unsupported entry", "Remove traversal paths, directories, links and device entries.")
              next
            end
            names << entry.name
            entry.get_input_stream do |stream|
              content = stream.read(Settings::EXPANDED_LIMIT - total + 1)
              total += content.bytesize
              raise BudgetExceeded if total > Settings::EXPANDED_LIMIT
              expected = files.find { |row| row["path"] == entry.name }
              matches = expected && expected["size"] == content.bytesize && expected["sha256"] == Digest::SHA256.hexdigest(content)
              check.call("FILE_DIGEST", !!matches, expected ? expected["sha256"] : "file listed in manifest", matches ? "matched" : "mismatch", "Regenerate the manifest from the actual file bytes.")
            end
          end
        end
      end
      complete = names.sort == files.map { |row| row["path"] }.sort && names.uniq.length == names.length && names.include?("index.html")
      check.call("ZIP_INVENTORY", complete, "exactly the declared files including index.html", complete ? "matched" : "mismatch", "Include index.html and remove undeclared or duplicate entries.")
      checks
    rescue Zip::Error, BudgetExceeded, IOError, ArgumentError
      checks << { code: "ZIP_INVALID_OR_OVER_BUDGET", ok: false, expected: "ZIP <=2 MB expanded / <=16 entries / <=3 seconds", observed: "rejected", fix: "Rebuild a small ZIP with regular files." }
    end

    def self.safe_path?(path)
      path.is_a?(String) && path.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_\/.\-]{0,100}\z/) &&
        !path.split("/").include?("..") && !path.include?("//") && !path.end_with?("/")
    end
  end
end
