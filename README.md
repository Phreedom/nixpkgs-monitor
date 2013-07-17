# nixpkgs-monitor

NixPkgs package status, freshness and security status monitor

## updatetool.rb

(re)generates package caches using --list-{arch,deb,nix,gentoo}

Checks updates for a single package or all packages.

Generates coverage reports:
* what packages don't seem to be covered by updaters
* what packages are covered by updaters and how many updaters cover each given package

Coverage report is an estimate. More precise report can only be obtained during update.

Reports look somewhat ugly.

### database

updatetool.rb puts coverage, version mismatch and updater reports into a database(db.sqlite).

Coverage report is in estimated_coverage table, version mismatch report is in
version_mismatch table and updater reports are in repository_* and distro_* tables.

## comparepackages.rb

Matches packages in one distro to packages in another one.
To be used for experimentation only.
Probably you don't care that it exists.

## Debian watchfiles tools

Scripts and a writeup of an experiment to see just how useful Debian watchfiles are.

## How to install

Have Nix? Just run:

  nix-env -i nixpkgs-monitor-dev -f . -I /etc/nixos/
