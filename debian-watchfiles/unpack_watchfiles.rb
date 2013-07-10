Dir['**/*debian.tar.gz'].reject{ |f| File.directory?(f) }.each do |f|
#  puts f
  watchfile = %x(tar xvf #{f} debian/watch -O)
  File.write("watchfiles/#{File.basename(f)[/(.*)\.debian\.tar\.gz/, 1]}.watch", watchfile) if watchfile.length>0
  puts "no watch in #{f}" unless watchfile.length>0
end
