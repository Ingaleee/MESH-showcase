require "json"

source = File.read(File.expand_path("../packs/platform/app/domain/platform/money.rb", __dir__))
variants = {
  "baseline" => source,
  "rounding_boundary" => source.sub("+ 5_000", "+ 4_999"),
  "float_amount" => source.sub('minor.is_a?(Integer)', 'minor.is_a?(Numeric)'),
  "mixed_currency" => source.sub('currency == other.currency', 'true')
}
results = variants.each_with_index.map do |(name, code), index|
  space = "Mutation#{index}"
  eval(code.sub("module Platform", "module #{space}"), TOPLEVEL_BINDING, "#{name}.rb")
  money = Object.const_get(space)::Money
  checks = []
  checks << (money.new(minor: 5, currency: "RUB").commission(basis_points: 1000).minor == 1)
  checks << begin
    money.new(minor: 1.5, currency: "RUB")
    false
  rescue ArgumentError
    true
  end
  checks << begin
    money.new(minor: 1, currency: "RUB") + money.new(minor: 1, currency: "USD")
    false
  rescue ArgumentError
    true
  end
  { variant: name, passes: checks.all? }
end
puts JSON.pretty_generate(results)
abort "Baseline failed or a mutant survived." unless results.first[:passes] && results.drop(1).none? { |result| result[:passes] }
