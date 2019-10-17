# frozen_string_literal: true

require_relative "lib/aargs"
require "pp"

# Hit the ground running with no configuation at all
aargs = Aargs.new.parse("look", "how", "--easy", "--this=is", "to", "use!")

puts "prologue: #{aargs.prologue}"
puts "it's so easy!" if aargs.easy?
puts "this #{aargs.this} it!"
puts "epilogue: #{aargs.epilogue}"

# prologue: ["look", "how"]
# it's so easy!
# this is it!
# epilogue: ["to", "use!"]

# Expose the same API for use in the IRB
aargs = Aargs.new.parse("look", "how", :easy, this: "is")

puts "prologue: #{aargs.prologue}"
puts "it's so easy!" if aargs.easy?
puts "this #{aargs.this} it!"

# prologue: ["look", "how"]
# it's so easy!
# this is it!

# Epilogues are supported in IRB style, too!
aargs = Aargs.new.parse("look", "how", :easy, { this: "is" }, "to", "use!")
puts "epilogue: #{aargs.epilogue}"
# epilogue: ["to", "use!"]

# This is great for development, but you'll probably want something more reliable,
# as this is a pretty permissive setup:
puts aargs.help
# Usage: examples.rb [PROLOGUE ... [PROLOGUE]] [aargs] [EPILOGUE ... [EPILOGUE]]

# Let's look at a more complete example.
aargs = Aargs.new(prologue: [:mode], flag_configs: { src: "file to operate on" })
puts aargs.help
# Usage: examples.rb MODE --src=VALUE
# --src=VALUE : file to operate on
