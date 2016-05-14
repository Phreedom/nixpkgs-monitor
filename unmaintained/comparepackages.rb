# currently defunct

require 'optparse'
require 'set'
require './distro-package.rb'

# levenshtein distance
# taken from  https://github.com/threedaymonk/text/blob/master/lib/text/levenshtein.rb
def distance(str1, str2)
  prepare =
    if "ruby".respond_to?(:encoding)
      lambda { |str| str.encode(Encoding::UTF_8).unpack("U*") }
    else
      rule = $KCODE.match(/^U/i) ? "U*" : "C*"
      lambda { |str| str.unpack(rule) }
    end

  s, t = [str1, str2].map(&prepare)
  n = s.length
  m = t.length
  return m if n.zero?
  return n if m.zero?

  d = (0..m).to_a
  x = nil

  n.times do |i|
    e = i + 1
    m.times do |j|
      cost = (s[i] == t[j]) ? 0 : 1
      x = [
        d[j+1] + 1, # insertion
        e + 1, # deletion
        d[j] + cost # substitution
      ].min
      d[j] = e
      e = x
    end
    d[m] = x
  end

  return x
end

def src_distance(str1,str2)
  url1 = $1 if str1 =~ /:\/\/[^\/]*(\/.*)/
  url2 = $1 if str2 =~ /:\/\/[^\/]*(\/.*)/

  return 10000 unless url1 and url2
  return distance(url1, url2)
end


known_missing = Set.new ["dvdrip","ogle", "lha",  "xlogo", "beep", ]

OptionParser.new do |o|

  o.on("--match-arch", "Try matching Arch packages to Nix packages") do
    arch_list = DistroPackage::Arch.list
    nix_list = DistroPackage::Nix.list

    missing = (Set.new(arch_list.keys) - Set.new(nix_list.keys)) - known_missing
    found = (Set.new(arch_list.keys) - missing) - known_missing
    puts "Found #{found.count} packages: #{found.inspect}"
    puts "known missing #{known_missing.count} packages : #{known_missing}"
    puts "Missing #{missing.count} packages: #{missing.inspect}"

    found.each do |pkg|
      puts pkg
      arch_url = arch_list[pkg].url
      nix_url = nix_list[pkg].url
      next if arch_url == 'none' or nix_url == 'none'
      puts "#{nix_url} #{arch_url} #{src_distance(nix_url,arch_url)}"
    end

    puts "TRYING TO FIND MATCHES BY URL ONLY"
    missing.each do |pkg|
      puts pkg
      arch_url = arch_list[pkg].url
      nix_list.each_value do |nixpkg|
	nix_url = nixpkg.url
        next if arch_url == 'none' or nix_url == 'none'
	
	if src_distance(nix_url,arch_url)<8
	  puts " found match #{pkg} #{nixpkg.name} "
	end
      end
    end

  end


  o.on("--match-deb", "Try matching Nix packages to Debian packages") do
    deb_list = DistroPackage::Deb.generate_list
    nix_list = DistroPackage::Nix.list
    unmatched = (Set.new(nix_list.keys) - Set.new(deb_list.keys))
    matched = Set.new(nix_list.keys)- unmatched
    puts "Matched #{matched.count} packages: #{matched.inspect}"
    puts "Unmatched #{unmatched.count} packages: #{unmatched.inspect}"
  end

  o.on("-h", "--help", "Show this message") do
    puts o
    exit
  end

  o.parse(ARGV)
end
