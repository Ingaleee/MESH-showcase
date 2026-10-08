require "ripper"
require "pathname"

root = Pathname.new(__dir__).join("../packs/publishing/app").expand_path
violations = []
allowed = {
  "domain" => %w[Publishing Domain DeploymentRules Claim IntegrationFailure Failure StandardError Data Hash String Integer Class],
  "application" => %w[Publishing Application DeploymentPorts ProcessDeployment Store Partner Artifacts Domain DeploymentRules IntegrationFailure Failure Digest SHA256 NotImplementedError]
}
allowed.each do |layer, constants|
  root.join(layer).glob("**/*.rb").each do |file|
    tokens = Ripper.lex(file.read)
    tokens.each do |_, type, value, _|
      violations << "#{file.relative_path_from(root)}: forbidden constant #{value}" if type == :on_const && !constants.include?(value)
    end
    calls = tokens.select { |_, type, _, _| %i[on_ident on_kw].include?(type) }.map { |_, _, value, _| value }
    forbidden = %w[constantize safe_constantize const_get eval class_eval module_eval require_relative autoload]
    violations << "#{file}: dynamic dependency escape" unless (calls & forbidden).empty?
    tokens.each_cons(2) do |left, right|
      next unless left[2] == "require" && right[1] == :on_sp
      # Only the standard-library digest dependency is part of this application's core.
      violations << "#{file}: external require" unless file.read.scan(/require\s+["']([^"']+)["']/).flatten.all? { |name| name == "digest" }
    end
  end
end
# A deliberate Rails dependency is the negative control for the lexer used above.
raise "Dependency scanner failed its negative control" unless Ripper.lex("Rails.logger").any? { |_, type, value, _| type == :on_const && !allowed["application"].include?(value) }
abort violations.join("\n") unless violations.empty?
puts "Publishing Domain/Application dependency rule passed (Ruby lexer + dynamic escape checks)."
