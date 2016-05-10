require 'package_updaters/distro'
require 'package_updaters/gentoo_distfiles'
require 'package_updaters/git'
require 'package_updaters/repository'

module PackageUpdaters

  Updaters = Distro::Updaters +
             Git::Updaters +
             Repository::Updaters +
             [ GentooDistfiles ]

end
