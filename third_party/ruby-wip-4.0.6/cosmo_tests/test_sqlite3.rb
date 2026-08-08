# Real SQLite exercise for the CosmoRuby APE.
# Run with:  env -i /path/to/ruby.com /path/to/sqlite_test.rb
# (must be runnable from an empty cwd with no environment)

require "sqlite3"
require "tmpdir"
require "fileutils"

$failures = 0

def check(desc)
  got = yield
  puts "PASS: #{desc} :: #{got.inspect}"
rescue => e
  $failures += 1
  puts "FAIL: #{desc} :: #{e.class}: #{e.message}"
  puts e.backtrace.first(3).map { |l| "      #{l}" }
end

puts "ruby            = #{RUBY_VERSION} #{RUBY_PLATFORM}"
puts "SQLite3::VERSION= #{SQLite3::VERSION}"
puts "SQLITE_VERSION  = #{SQLite3::SQLITE_VERSION}"
puts "SQLITE_LOADED   = #{SQLite3::SQLITE_LOADED_VERSION}"
puts "threadsafe?     = #{SQLite3.threadsafe?}"
puts

# ---------------------------------------------------------------- in-memory
check("in-memory: create/insert/select/transaction") do
  db = SQLite3::Database.new(":memory:")
  db.execute("CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT, age INTEGER, blob BLOB)")

  # bound params, positional
  db.execute("INSERT INTO people (name, age) VALUES (?, ?)", ["Ada", 36])
  # bound params, named
  db.execute("INSERT INTO people (name, age) VALUES (:n, :a)", { "n" => "Grace", "a" => 45 })
  # prepared statement reuse
  st = db.prepare("INSERT INTO people (name, age) VALUES (?, ?)")
  st.execute("Alan", 41)
  st.reset!
  st.execute("Edsger", 72)
  st.close

  # transaction: commit
  db.transaction do
    db.execute("INSERT INTO people (name, age) VALUES (?, ?)", ["Barbara", 83])
  end
  raise "transaction commit lost" unless db.get_first_value("SELECT COUNT(*) FROM people") == 5

  # transaction: rollback
  begin
    db.transaction do
      db.execute("INSERT INTO people (name, age) VALUES (?, ?)", ["Ghost", 0])
      raise "boom"
    end
  rescue RuntimeError
  end
  raise "rollback failed" unless db.get_first_value("SELECT COUNT(*) FROM people") == 5

  # blob round-trip
  raw = (0..255).to_a.pack("C*")
  db.execute("INSERT INTO people (name, blob) VALUES (?, ?)", ["blobby", SQLite3::Blob.new(raw)])
  back = db.get_first_value("SELECT blob FROM people WHERE name = ?", ["blobby"])
  raise "blob mismatch" unless back == raw

  # UTF-8 round-trip
  db.execute("INSERT INTO people (name) VALUES (?)", ["Ævar Ωmega 日本語"])
  utf = db.get_first_value("SELECT name FROM people WHERE name LIKE 'Ævar%'")
  raise "utf8 mismatch #{utf.inspect}" unless utf == "Ævar Ωmega 日本語"
  raise "utf8 encoding #{utf.encoding}" unless utf.encoding == Encoding::UTF_8

  rows = db.execute("SELECT name, age FROM people WHERE age > ? ORDER BY age DESC", [40])
  db.close
  raise "db not closed" unless db.closed?
  rows
end

# --------------------------------------------------------------- file-backed
tmp = Dir.mktmpdir("cosmo-sqlite")
path = File.join(tmp, "test.db")

check("file-backed: create + persist + reopen") do
  db = SQLite3::Database.new(path)
  db.execute("CREATE TABLE kv (k TEXT PRIMARY KEY, v TEXT)")
  db.transaction do
    st = db.prepare("INSERT INTO kv (k, v) VALUES (?, ?)")
    100.times { |i| st.execute("key#{i}", "value#{i}") }
    st.close
  end
  db.close
  raise "db file was not created" unless File.exist?(path)

  # reopen in a fresh handle and read back
  db2 = SQLite3::Database.new(path)
  db2.results_as_hash = true
  n = db2.get_first_value("SELECT COUNT(*) FROM kv")
  raise "expected 100 rows, got #{n}" unless n == 100
  row = db2.execute("SELECT k, v FROM kv WHERE k = ?", ["key42"]).first
  raise "bad row #{row.inspect}" unless row["v"] == "value42"

  # last_insert_row_id / changes
  db2.execute("INSERT INTO kv (k, v) VALUES (?, ?)", ["key100", "value100"])
  raise "changes wrong" unless db2.changes == 1

  # readonly handle should refuse writes
  ro = SQLite3::Database.new(path, readonly: true)
  begin
    ro.execute("INSERT INTO kv (k, v) VALUES ('x','y')")
    raise "readonly database accepted a write"
  rescue SQLite3::ReadOnlyException
  end
  ro.close

  size = File.size(path)
  db2.close
  { rows: 101, bytes: size }
end

check("custom SQL function + aggregate") do
  db = SQLite3::Database.new(":memory:")
  db.create_function("shout", 1) { |func, v| func.result = "#{v}!" }
  out = db.get_first_value("SELECT shout('hi')")
  raise "custom function: #{out.inspect}" unless out == "hi!"
  db.execute("CREATE TABLE n (x INTEGER)")
  [1, 2, 3, 4].each { |i| db.execute("INSERT INTO n VALUES (?)", [i]) }
  total = db.get_first_value("SELECT SUM(x) FROM n")
  db.close
  total
end

check("error handling: SQLException on bad SQL") do
  db = SQLite3::Database.new(":memory:")
  begin
    db.execute("SELECT * FROM does_not_exist")
    raise "expected SQLite3::SQLException"
  rescue SQLite3::SQLException => e
    db.close
    e.message
  end
end

check("busy_timeout + pragmas") do
  db = SQLite3::Database.new(":memory:")
  db.busy_timeout = 1000
  jm = db.journal_mode
  db.close
  jm
end

FileUtils.remove_entry(tmp)

puts
puts "RESULT: failures=#{$failures}"
exit($failures.zero? ? 0 : 1)
