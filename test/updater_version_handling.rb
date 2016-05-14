require 'test/unit'
require 'nixpkgs_monitor/package_updaters/base'

class TestSimple < Test::Unit::TestCase

  Updater = NixPkgsMonitor::PackageUpdaters::Base

  def test_usable_version
    assert(Updater.usable_version?('1'));
    assert(Updater.usable_version?('4.5'));
    assert(!Updater.usable_version?('4.5.'));
    assert(!Updater.usable_version?('4..5'));
    assert(!Updater.usable_version?('.4.5'));
    assert(!Updater.usable_version?('4.-5'));
    assert(Updater.usable_version?('2.4.0'));
    assert(Updater.usable_version?('1.3.0.pre'));
    assert(Updater.usable_version?('1.3.0.rc.3'));
    assert(Updater.usable_version?('2.4.0a'));
    assert(!Updater.usable_version?('2-4-0'));
    assert(Updater.usable_version?('2.4.3.5'));
  end


  def test_version_parsing
    assert_equal([1, 3, 0,  -85,  3, -1, -1, -1, -1, -1],
                 Updater.tokenize_version('1.3.0.pre.3'))
    assert_equal([2, 4, 0, -100, -1, -1, -1, -1, -1, -1],
                 Updater.tokenize_version('2.4.0A'))
  end


  def test_version_comparison
    assert(Updater.is_newer?('2','1'))
    assert(Updater.is_newer?('2.2','2.1'))
    assert(Updater.is_newer?('2.1','2'))
    assert(!Updater.is_newer?('2', '2.0'))
    assert(!Updater.is_newer?('2.1.3','2.1.03'))
    assert(!Updater.is_newer?('2.1.3','2.1.4'))

    assert(Updater.is_newer?('1.3.0.1', '1.1.0.3'))
    assert(!Updater.is_newer?('1.1.0.3', '1.3.0.1'))
    assert(Updater.tokenize_version('1.3.0.1'))
  end

end
