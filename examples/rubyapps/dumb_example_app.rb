def main
  puts 'cosmopolitan is cool with Ruby!'
end

puts "__FILE__ is #{__FILE__} in app"
puts "$0 is #{$0} in app"
if __FILE__ == $0
  main
end

require_relative 'does_not_exist'
require_relative 'dumb_example_helper'

help_me()
