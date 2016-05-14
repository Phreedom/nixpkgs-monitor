require 'nixpkgs_monitor/package_updaters/repository/cpan'
require 'nixpkgs_monitor/package_updaters/repository/gnome'
require 'nixpkgs_monitor/package_updaters/repository/gnu'
require 'nixpkgs_monitor/package_updaters/repository/hackage'
require 'nixpkgs_monitor/package_updaters/repository/kde'
require 'nixpkgs_monitor/package_updaters/repository/npmjs'
require 'nixpkgs_monitor/package_updaters/repository/pypi'
require 'nixpkgs_monitor/package_updaters/repository/rubygems'
require 'nixpkgs_monitor/package_updaters/repository/sf'
require 'nixpkgs_monitor/package_updaters/repository/xorg'

module NixPkgsMonitor module PackageUpdaters module Repository

  Updaters = [ CPAN, GNOME, GNU, Hackage, KDE, NPMJS, Pypi, Rubygems, SF, Xorg ]

end end end
