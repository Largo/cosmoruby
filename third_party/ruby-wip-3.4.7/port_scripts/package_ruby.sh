
# start in third_party/ruby/port_scripts

# Navigate to o/ directory (assumes running from third_party/ruby/port_scripts)
cd ../../../o

# in o

# Exit if current working directory is not o (does not end in /o)
if [[ ! "$PWD" =~ /o$ ]]; then
  echo "Error: Could not navigate to o/ directory. Please run from third_party/ruby/port_scripts/"
  exit 1
fi

# Clean up any existing cosmo-ruby directory and ruby-stdlib.zip file
rm -rf cosmo-ruby
rm ruby-stdlib.zip

mkdir -p cosmo-ruby/bin

# Create directory structure for Ruby stdlib
mkdir -p cosmo-ruby/lib/ruby/3.4.0

# Copy Ruby standard library
cp -r /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/lib/* cosmo-ruby/lib/ruby/3.4.0/

# Copy bundled gems (rake, minitest, etc.)
mkdir -p cosmo-ruby/lib/ruby/gems/3.4.0
cp -r /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/.bundle/* cosmo-ruby/lib/ruby/gems/3.4.0/

# Create default gem specification for bundler (must be static, no require_relative)
mkdir -p cosmo-ruby/lib/ruby/gems/3.4.0/specifications/default
cat > cosmo-ruby/lib/ruby/gems/3.4.0/specifications/default/bundler.gemspec <<'EOF'
# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = "bundler"
  s.version     = "2.6.9"
  s.license     = "MIT"
  s.authors     = [
    "André Arko", "Samuel Giddins", "Colby Swandale", "Hiroshi Shibata",
    "David Rodríguez", "Grey Baker", "Stephanie Morillo", "Chris Morris", "James Wen", "Tim Moore",
    "André Medeiros", "Jessica Lynn Suttles", "Terence Lee", "Carl Lerche",
    "Yehuda Katz"
  ]
  s.email       = ["team@bundler.io"]
  s.homepage    = "https://bundler.io"
  s.summary     = "The best way to manage your application's dependencies"
  s.description = "Bundler manages an application's dependencies through its entire life, across many machines, systematically and repeatably"

  s.required_ruby_version     = ">= 3.0.0"
  s.required_rubygems_version = ">= 3.0.0"

  s.files = Dir.glob("lib/**/*", File::FNM_DOTMATCH).reject { |f| File.directory?(f) }
  s.require_paths = ["lib"]
end
EOF

#
mkdir -p cosmo-ruby/usr/share/terminfo

#
cp -r /home/groobiest/Code/jart/cosmopolitan/usr/share/terminfo/* cosmo-ruby/usr/share/terminfo

cd cosmo-ruby

# in o/cosmo-ruby

# Extract the existing ZIP fs stuff into the current directory
RUBYLIB=../third_party/ruby/lib ../third_party/ruby/ruby ../third_party/ruby/port_scripts/extract_zip.rb /zip/
touch .cosmo

# Create the ZIP file
zip -r ../ruby-stdlib.zip *

cd ..

# in o

# Prepare the Ruby binary for packaging
cp third_party/ruby/ruby third_party/ruby/ruby.com
cp third_party/ruby/irb third_party/ruby/irb.com
# Use zipcopy to embed the stdlib ZIP into the Ruby binary
../.cosmocc/current/bin/zipcopy ruby-stdlib.zip third_party/ruby/ruby.com
../.cosmocc/current/bin/zipcopy ruby-stdlib.zip third_party/ruby/irb.com
