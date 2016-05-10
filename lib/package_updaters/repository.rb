require 'package_updaters/repository/cpan'
require 'package_updaters/repository/gnome'
require 'package_updaters/repository/gnu'
require 'package_updaters/repository/hackage'
require 'package_updaters/repository/kde'
require 'package_updaters/repository/npmjs'
require 'package_updaters/repository/pypi'
require 'package_updaters/repository/rubygems'
require 'package_updaters/repository/sf'
require 'package_updaters/repository/xorg'

module PackageUpdaters
  module Repository

    Updaters = [ CPAN, GNOME, GNU, Hackage, KDE, NPMJS, Pypi, Rubygems, SF, Xorg ]

  end
end
