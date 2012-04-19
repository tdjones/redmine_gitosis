begin
  gem 'delayed_job', '~>2.0.7'
  require 'delayed/tasks'
rescue LoadError
  STDERR.puts "The 'delayed_job' gem is missing. Please install version ~> 2.0.7"
end
