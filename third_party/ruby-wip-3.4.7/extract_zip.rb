#!/usr/bin/env ruby
# Extract files from embedded ZIP filesystem to current directory

require 'fileutils'

zip_prefix = ARGV[0] || '/zip'

# Find all files in the ZIP filesystem
Dir.glob("#{zip_prefix}/**/*", File::FNM_DOTMATCH).each do |path|
  next if File.directory?(path)

  # Get relative path (strip /zip prefix)
  relative_path = path.sub(/^#{Regexp.escape(zip_prefix)}\//, '')

  # Skip if it's just "." or ".."
  next if relative_path == '.' || relative_path == '..'

  # Create directory structure
  FileUtils.mkdir_p(File.dirname(relative_path)) if File.dirname(relative_path) != '.'

  # Copy the file
  FileUtils.cp(path, relative_path)
  # puts "Extracted: #{relative_path}"
end

puts "ZIP extraction complete"
