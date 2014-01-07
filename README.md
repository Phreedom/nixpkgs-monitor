# nixpkgs-monitor

NixPkgs package quality, freshness, security monitoring and improvement tool.

## NixOS module

After checking out the nixpkgs-monitor repository, add to the configuration:

  require = [ /path/to/nixpkgs-monitor/service.nix ];
  services.nixpkgs-monitor.enable = true;

This sets up 2 systemd units:
* nixpkgs-monitor-site, a web interface. It will return errors until the first updater run is finished.
* nixpkgs-monitor-updater, a job which does the full update checker, patch generator and builder run. You need to run it manually or via cron.

## How to install and use as a regular user

Have Nix? Just run:

  nix-env -if .

## updatetool.rb

Does all the dirty jobs: obtains package metada, finds updates, vulnerabilities, generates patches and attempts to build them.

### A typical workflow

cd to the working directory. The cache DB will be stored here along with the needed repository checkouts.

(Re)generate package caches: --list-{arch,deb,nix,gentoo}
Fetch CVE data: --cve-update

After package cache is populated, generate all essential reports:
--coverage --check-updates --cve-check
Nix package cache should be populated before this step; the rest is optional, but strongly recommended

Fetch tarballs and generate patches: --tarballs --patches

Attempt building the generated patches: --build

All the mentioned actions except for build: --all.
A good idea before running the build step is to trigger a web interface refresh.

## nixpkgs-monitor-site

Provides a nice web interface to browse the reports, patches, build logs and such.
By default runs on http://localhost:4567. Must be run from the same directory as the updatetool.

The web interface caches some of the data in RAM, and must be kicked by requesting /refresh
or restarted after updatetool run finishes.

## database

updatetool.rb puts package cache, coverage, version mismatch and updater reports into a database(db.sqlite).

Coverage report is in estimated_coverage table, version mismatch report is in
version_mismatch table and updater reports are in repository_* and distro_* tables.

Package caches are in packages_* tables.

Tarball candidates are in tarballs table.

Tarball hashes or '404' if download failed are in tarball_sha256 table.
404 records can be dropped using updatetool.rb --redownload.

Generated patches along with derivation paths are in patches table.

You can extract individual patches by running something like 
SELECT patch FROM patches WHERE pkg_attr='package' AND version='version';

Build logs and statuses are in builds table.

Potential CVE matches are in cve_match table.

## comparepackages.rb

Matches packages in one distro to packages in another one.
To be used for experimentation only. Unmaintained.
Probably you don't care that it exists.

## Debian watchfiles tools

Scripts and a writeup of an experiment to see just how useful Debian watchfiles are.
Spoiler: not very useful :(
