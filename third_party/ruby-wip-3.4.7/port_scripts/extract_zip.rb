
# does CoPilot work?

# recursively copy from provided dir to current working dir
def recursively(dir)
  # Check if source directory exists
  unless File.directory?(dir)
    puts "Error: Source directory '#{dir}' does not exist"
    return false
  end
  
  # Get absolute path of current working directory
  destination_dir = Dir.pwd
  
  puts "Copying from: #{dir}"
  puts "Copying to: #{destination_dir}"
  
  # Use Find module for recursive directory traversal
  require 'find'
  
  Find.find(dir) do |source_path|
    # Calculate relative path from source directory
    relative_path = source_path.sub(/^#{Regexp.escape(dir)}\/?/, '')
    next if relative_path.empty? # Skip the root directory itself
    
    destination_path = File.join(destination_dir, relative_path)
    
    if File.directory?(source_path)
      # Create directory in destination
      FileUtils.mkdir_p(destination_path) unless File.exist?(destination_path)
      puts "Created directory: #{relative_path}"
    else
      # Copy file
      FileUtils.cp(source_path, destination_path, preserve: true)
      puts "Copied file: #{relative_path}"
    end
  end
  
  puts "Recursive copy completed successfully!"
  true
rescue => e
  puts "Error during copy: #{e.message}"
  false
end

require 'fileutils'

recursively(ARGV[0]) if ARGV.length == 1
