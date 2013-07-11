require "test/unit"
require "./package-updater.rb"
include PackageUpdater

class TestSimple < Test::Unit::TestCase

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


  def test_version_compare
    #just to see how it looks inside
    puts Updater.tokenize_version('1.3.0.pre.3').inspect
    puts Updater.tokenize_version('2.4.0a').inspect

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