# frozen_string_literal: true
#
# CosmoRuby bigdecimal test.
#
#   ruby.com third_party/ruby/cosmo_tests/test_bigdecimal.rb
#
# Exercises the statically linked bigdecimal 4.0.1 extension: construction
# from every accepted type, arbitrary-precision arithmetic that a Float
# cannot do, rounding modes, exception modes, the BigMath transcendentals,
# Rational/Complex interop, the util.rb refinement-free #to_d helpers, and
# serialization. Exit status 0 means every check passed.

require "bigdecimal"
require "bigdecimal/util"
require "bigdecimal/math"

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

# ---------------------------------------------------------------- basics

check("BigDecimal::VERSION") { BigDecimal::VERSION }

check("the C extension is what is loaded") do
  # bigdecimal.so is pre-registered by ext/extinit.c; if the pure-Ruby half
  # were somehow loaded alone, BigDecimal would not exist at all.
  defined?(BigDecimal) == "constant" && BigDecimal.instance_method(:add).owner == BigDecimal
end

check("from String") { BigDecimal("1.0000000000000000000000000000001").to_s == "0.10000000000000000000000000000001e1" }
check("from Integer") { BigDecimal(2**70).to_i == 2**70 }
check("from Float with precision") { BigDecimal(0.1, 16).to_s("F").start_with?("0.1") }
check("from Rational with precision") { BigDecimal(Rational(1, 3), 20).to_s("F")[0, 12] == "0.3333333333" }
check("from BigDecimal") { BigDecimal(BigDecimal("7")) == 7 }

# ------------------------------------------- arithmetic a Float cannot do

check("0.1 + 0.2 == 0.3 exactly") do
  (BigDecimal("0.1") + BigDecimal("0.2")) == BigDecimal("0.3") && (0.1 + 0.2) != 0.3
end

check("100-digit division is exact to 100 digits") do
  q = BigDecimal(1).div(BigDecimal(7), 100)
  q.to_s("F")[2, 24] == "142857142857142857142857"
end

check("big factorial keeps every digit") do
  f = (1..40).reduce(BigDecimal(1)) { |a, i| a * i }
  f.to_i == (1..40).reduce(1, :*)
end

check("power with negative exponent") { (BigDecimal(2)**-3) == BigDecimal("0.125") }
check("sqrt(2) to 40 digits") { BigDecimal(2).sqrt(40).to_s("F")[0, 12] == "1.4142135623" }
check("modulo and divmod") do
  q, r = BigDecimal("13.5").divmod(BigDecimal("4"))
  q == 3 && r == BigDecimal("1.5")
end

# ------------------------------------------------------------- rounding

check("ROUND_HALF_UP vs ROUND_HALF_EVEN") do
  x = BigDecimal("2.5")
  x.round(0, BigDecimal::ROUND_HALF_UP) == 3 && x.round(0, BigDecimal::ROUND_HALF_EVEN) == 2
end
check("ROUND_CEILING / ROUND_FLOOR") do
  BigDecimal("1.01").round(1, BigDecimal::ROUND_CEILING) == BigDecimal("1.1") &&
    BigDecimal("1.09").round(1, BigDecimal::ROUND_FLOOR) == BigDecimal("1.0")
end
check("truncate / ceil / floor with digits") do
  BigDecimal("-1.234").truncate(2) == BigDecimal("-1.23") &&
    BigDecimal("1.234").ceil(2) == BigDecimal("1.24") &&
    BigDecimal("1.236").floor(2) == BigDecimal("1.23")
end
check("mode(ROUND_MODE) round trips") do
  old = BigDecimal.mode(BigDecimal::ROUND_MODE)
  BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_DOWN)
  got = BigDecimal.mode(BigDecimal::ROUND_MODE)
  BigDecimal.mode(BigDecimal::ROUND_MODE, old)
  got == BigDecimal::ROUND_DOWN
end

# ------------------------------------------------- NaN / Infinity / modes

check("division by zero yields Infinity when unchecked") do
  BigDecimal.mode(BigDecimal::EXCEPTION_ZERODIVIDE, false)
  inf = BigDecimal(1) / BigDecimal(0)
  BigDecimal.mode(BigDecimal::EXCEPTION_ZERODIVIDE, true)
  inf.infinite? == 1
end

check("EXCEPTION_ZERODIVIDE raises when enabled") do
  BigDecimal.mode(BigDecimal::EXCEPTION_ZERODIVIDE, true)
  begin
    BigDecimal(1) / BigDecimal(0)
    false
  rescue ZeroDivisionError, FloatDomainError
    true
  end
end

check("BigDecimal('NaN') is NaN and never equal to itself") do
  n = BigDecimal("NaN")
  n.nan? && !(n == n)
end

check("finite?/nan?/infinite? on a normal value") do
  v = BigDecimal("1.5")
  v.finite? && !v.nan? && v.infinite?.nil?
end

check("BigDecimal(str, exception: false) returns nil") { BigDecimal("zonk", exception: false).nil? }

# ------------------------------------------------------------- BigMath

check("BigMath.PI(30)") { BigMath.PI(30).to_s("F")[0, 12] == "3.1415926535" }
check("BigMath.E(30)") { BigMath.E(30).to_s("F")[0, 12] == "2.7182818284" }
check("BigMath.sqrt(2,30)") { BigMath.sqrt(BigDecimal(2), 30).to_s("F")[0, 10] == "1.41421356" }
check("BigMath.log/exp round trip") do
  x = BigDecimal("3.5")
  BigMath.exp(BigMath.log(x, 30), 30).round(20) == x.round(20)
end
check("BigMath.sin(PI/6) is 0.5") { BigMath.sin(BigMath.PI(30) / 6, 30).round(15) == BigDecimal("0.5") }

# --------------------------------------------------------- interop / util

check("Integer#to_d") { 42.to_d == BigDecimal(42) }
check("String#to_d") { "1.25".to_d == BigDecimal("1.25") }
check("Float#to_d") { 1.25.to_d == BigDecimal("1.25") }
check("Rational#to_d(precision)") { Rational(1, 4).to_d(10) == BigDecimal("0.25") }
check("BigDecimal#to_r") { BigDecimal("0.75").to_r == Rational(3, 4) }
check("BigDecimal#to_d is itself") { BigDecimal("2").to_d == BigDecimal("2") }
check("coerce with Integer") { (1 + BigDecimal("0.5")) == BigDecimal("1.5") }
check("coerce with Rational") { (Rational(1, 2) + BigDecimal("0.5")) == BigDecimal(1) }
check("Complex real/imag (HAVE_RB_COMPLEX_REAL/IMAG)") do
  # BigDecimal() accepts a Complex whose imaginary part is zero; that path is
  # what the rb_complex_real/rb_complex_imag have_func()s are transcribed for.
  BigDecimal(Complex(3, 0)) == 3
end

# ------------------------------------------------------ representation

check("to_s('F') and to_s('E')") do
  BigDecimal("1234.5678").to_s("F") == "1234.5678" && BigDecimal("1234.5678").to_s("E").include?("e")
end
check("split") { BigDecimal("-12.34").split == [-1, "1234", 10, 2] }
check("precs/precision/scale") do
  BigDecimal("123.456").precision == 6 && BigDecimal("123.456").scale == 3
end
check("exponent and sign") do
  BigDecimal("0.001").exponent == -2 && BigDecimal("-1").sign == BigDecimal::SIGN_NEGATIVE_FINITE
end
check("Marshal round trip") { Marshal.load(Marshal.dump(BigDecimal("1.23456789e100"))) == BigDecimal("1.23456789e100") }
check("hash/eql? agree") do
  BigDecimal("1.0").eql?(BigDecimal("1.0")) && BigDecimal("1.0").hash == BigDecimal("1.0").hash
end
check("sorting mixed magnitudes") do
  [BigDecimal("1e20"), BigDecimal("-1"), BigDecimal("0.5")].sort.map { |d| d.to_s("F") } ==
    ["-1.0", "0.5", "100000000000000000000.0"]
end

# ----------------------------------------------------------- rubygems

check("registered as a default gem") do
  Gem::Specification.find_all_by_name("bigdecimal").map { |s| [s.version.to_s, s.default_gem?] } ==
    [[BigDecimal::VERSION, true]]
end

puts
puts "RESULT: pass=#{$pass} fail=#{$fail}"
exit($fail.zero? ? 0 : 1)
