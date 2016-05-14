require 'nixpkgs_monitor/package_updaters/distro'
require 'nixpkgs_monitor/package_updaters/gentoo_distfiles'
require 'nixpkgs_monitor/package_updaters/git'
require 'nixpkgs_monitor/package_updaters/repository'

module NixPkgsMonitor module PackageUpdaters

  Updaters = Distro::Updaters +
             Git::Updaters +
             Repository::Updaters +
             [ GentooDistfiles ]

end end
