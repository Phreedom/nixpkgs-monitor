Dir['watchfiles/*.watch'].reject{ |f| File.directory?(f) }.each do |f|
  puts f
  urls = %x(perl update.pl --watchfile #{f} --package a --upstream-version 0)
  File.write("deb_urls/#{File.basename(f)[/(.*)\.watch/, 1]}.urls", urls) if urls.length>0
  STDERR.puts "no watch in #{f}" unless urls.length>0
  puts "no watch in #{f}" unless urls.length>0
end
