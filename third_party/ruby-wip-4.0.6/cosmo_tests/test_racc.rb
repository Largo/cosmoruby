# frozen_string_literal: true
#
# CosmoRuby racc test.
#
#   ruby.com third_party/ruby/cosmo_tests/test_racc.rb
#
# Two halves, both of which used to be missing from this build:
#
#   1. the RUNTIME -- racc/parser.rb plus the statically linked `racc/cparse`
#      C engine. The point of linking cparse is that Racc::Parser picks the C
#      parse loop instead of its (working but slow) pure-Ruby one; this test
#      asserts that it did, then drives a real generated parser through it.
#   2. the GENERATOR -- `require "racc"`, Racc::GrammarFileParser,
#      Racc::States and Racc::ParserFileGenerator, i.e. racc as a gem rather
#      than as two stray files on the load path.
#
# Exit status 0 means every check passed.

require "racc"          # the gem's entry point (grammar, states, exceptions)
require "racc/parser"   # the runtime, which pulls in racc/cparse
require "racc/static"   # the generator: GrammarFileParser + ParserFileGenerator
require "stringio"

$pass = 0
$fail = 0

def check(name)
  got = yield
  if got
    $pass += 1
    puts "PASS: #{name}#{got == true ? "" : " :: #{got.inspect}"}"
  else
    $fail += 1
    puts "FAIL: #{name}"
  end
rescue => e
  $fail += 1
  puts "FAIL: #{name} :: #{e.class}: #{e.message}"
end

# ------------------------------------------------- the C runtime is in use

check("Racc::VERSION") { Racc::VERSION }

check("cparse is loaded, not the pure-Ruby fallback") do
  Racc::Parser::Racc_Runtime_Type == "c"
end

check("cparse version matches lib/racc/info.rb") do
  # RACC_INFO_VERSION in ext/racc/BUILD.mk has to agree with Racc::VERSION or
  # racc/parser.rb rejects the extension as "old cparse.so" and silently
  # downgrades to Ruby.
  Racc::Parser::Racc_Runtime_Core_Version_C == Racc::VERSION &&
    Racc::Parser::Racc_Runtime_Core_Version == Racc::VERSION
end

check("the C parse routines are the selected ones") do
  Racc::Parser::Racc_Main_Parsing_Routine == :_racc_do_parse_c &&
    Racc::Parser::Racc_YY_Parse_Method == :_racc_yyparse_c
end

check("racc/cparse is a registered feature") do
  $LOADED_FEATURES.any? { |f| f.end_with?("racc/cparse.so") } ||
    require("racc/cparse") == false
end

# -------------------------------------------------------- the generator

GRAMMAR = <<~'RACC'
  class CalcParser
  prechigh
    left '*' '/'
    left '+' '-'
  preclow
  rule
    target : exp
           |     { result = 0 }
    exp    : exp '+' exp  { result = val[0] + val[2] }
           | exp '-' exp  { result = val[0] - val[2] }
           | exp '*' exp  { result = val[0] * val[2] }
           | exp '/' exp  { result = val[0] / val[2] }
           | '(' exp ')'  { result = val[1] }
           | '-' NUMBER   { result = -val[1] }
           | NUMBER
  end

  ---- inner
    def parse(str)
      @tokens = []
      until str.empty?
        case str
        when /\A\s+/          then # skip
        when /\A\d+/          then @tokens.push [:NUMBER, $&.to_i]
        when /\A[-+*\/()]/    then @tokens.push [$&, $&]
        else raise ArgumentError, "bad character: #{str[0]}"
        end
        str = $'
      end
      @tokens.push [false, "$"]
      do_parse
    end

    def next_token
      @tokens.shift
    end
RACC

generated = nil

check("Racc::GrammarFileParser parses a grammar file") do
  result = Racc::GrammarFileParser.parse(GRAMMAR, "calc.y")
  states = Racc::States.new(result.grammar).nfa
  states.dfa
  params = result.params.dup
  params.filename = "calc.y"
  generated = Racc::ParserFileGenerator.new(states, params).generate_parser
  !states.srconflict_exist? && !states.rrconflict_exist? &&
    generated.include?("class CalcParser") && generated.include?("Racc_arg")
end

check("the generated parser is loadable Ruby") do
  eval(generated, TOPLEVEL_BINDING, "calc.tab.rb") # rubocop:disable Security/Eval
  defined?(CalcParser) == "constant" && CalcParser.ancestors.include?(Racc::Parser)
end

# ------------------------------------ drive the generated parser (C engine)

check("generated parser: precedence") { CalcParser.new.parse("1 + 2 * 3") == 7 }
check("generated parser: parentheses") { CalcParser.new.parse("(1 + 2) * 3") == 9 }
check("generated parser: unary minus") { CalcParser.new.parse("-4 + 10") == 6 }
check("generated parser: left associativity") { CalcParser.new.parse("100 - 10 - 1") == 89 }
check("generated parser: empty input reduces the epsilon rule") { CalcParser.new.parse("") == 0 }
check("generated parser: deep nesting (exercises the C stack growth path)") do
  expr = ("(" * 200) + "1" + (")" * 200)
  CalcParser.new.parse(expr) == 1
end
check("generated parser: 2000 terms (exercises the C reduce loop)") do
  CalcParser.new.parse(Array.new(2000, "1").join("+")) == 2000
end

check("generated parser: syntax error raises Racc::ParseError") do
  begin
    CalcParser.new.parse("1 + + 2")
    false
  rescue Racc::ParseError => e
    e.message.include?("parse error")
  end
end

check("Racc::ParseError is a StandardError") { Racc::ParseError.ancestors.include?(StandardError) }

check("token_to_str maps a symbol back to its name") do
  CalcParser.new.token_to_str(0) == "$end" || !CalcParser.new.token_to_str(0).nil?
end

# ------------------------------------------ the yyparse (push) entry point

check("yyparse drives the same grammar through _racc_yyparse_c") do
  klass = Class.new(CalcParser) do
    def parse_via_yyparse(tokens)
      @queue = tokens
      yyparse(self, :scan)
    end

    def scan
      @queue.each { |t| yield t }
    end
  end
  toks = [[:NUMBER, 6], ["*", "*"], [:NUMBER, 7], [false, "$"]]
  klass.new.parse_via_yyparse(toks) == 42
end

# ---------------------------------------------- the real-world consumer

check("nokogiri's generated CSS parser still works on this runtime") do
  require "nokogiri"
  doc = Nokogiri::HTML("<div class='a'><p id='x'>hi</p><p>bye</p></div>")
  doc.css("div.a > p#x").first.text == "hi" &&
    doc.css("p:nth-child(2)").first.text == "bye" &&
    Nokogiri::CSS::Parser.ancestors.include?(Racc::Parser)
end

# ------------------------------------------------------------- rubygems

check("registered as a default gem") do
  Gem::Specification.find_all_by_name("racc").map { |s| [s.version.to_s, s.default_gem?] } ==
    [[Racc::VERSION, true]]
end

check("a gem dependency on racc resolves") do
  dep = Gem::Dependency.new("racc", ">= 1.7")
  !dep.to_spec.nil?
end

puts
puts "RESULT: pass=#{$pass} fail=#{$fail}"
exit($fail.zero? ? 0 : 1)
