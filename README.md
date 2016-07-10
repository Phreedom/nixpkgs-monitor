# nixpkgs-monitor

A tool to monitor and improve NixPkgs packages quality, freshness and security.

## NixOS module

After checking out the nixpkgs-monitor repository, add this to configuration.nix:

    require = [ /path/to/nixpkgs-monitor/service.nix ];
    services.nixpkgs-monitor.enable = true;

This sets up 3 systemd units:
* __nixpkgs-monitor-site__, a web interface. It will return errors until the first updater run is finished.
* __nixpkgs-monitor-updater__, a job that does the full update checker, patch generator and builder run.
You need to run it manually or via cron or timers.
* __nixpkgs-monitor-updater-drop-negative-cache__, a maintenance job that drops failed tarball downloads and builds from the cache.
Should be run from time to time to recover from intermittent failures such as: disk getting full, connectivity troubles, upstream services going down.

## How to install and use as a regular user

Have Nix? Just run:

    nix-env -if .

## nixpkgs-monitor executable

Does all the dirty work: obtains package metada, finds updates, vulnerabilities, downloads tarballs, generates patches and attempts to build them.

### A typical workflow

cd to the working directory. The cache DB will be stored here along with the needed repository checkouts.

(Re)generate package caches: `--list-{arch,deb,nix,gentoo}`    
Fetch CVE data: `--cve-update`

After package cache is populated, generate all essential reports:
`--coverage --check-updates --cve-check`    
Nix package cache should be populated before this step; the rest is optional, but strongly recommended

Fetch tarballs and generate patches: `--tarballs --patches`

Attempt building the generated patches: `--build`

All the mentioned actions except for build: `--all`.    
A good idea before running the build step is to trigger a web interface refresh.

## nixpkgs-monitor-site executable

Provides a nice web interface to browse the reports, patches, build logs and such.
By default runs on http://localhost:4567. Must be run from the same directory as nixpkgs-monitor tool.

The web interface caches some of the data in RAM, and must be kicked by requesting `/refresh`
or restarted after nixpkgs-monitor run finishes.

## database

nixpkgs-monitor puts package cache, coverage, version mismatch and updater reports into
a database(db.sqlite by default).

Coverage report is in `estimated_coverage` table, version mismatch report is in
`version_mismatch` table and updater reports are in `repository_*` and `distro_*` tables.

Package caches are in `packages_*` tables.

Tarball candidates are in tarballs table.

Tarball hashes or '404' for failed downloads are in `tarball_sha256` table.
404 records can be dropped using `nixpkgs-monitor --redownload`.

Generated patches along with derivation paths are in patches table.

You can extract individual patches by running something like
`SELECT patch FROM patches WHERE pkg_attr='package' AND version='version';`

Build logs and statuses are in builds table. Failed build records can be
dropped using `nixpkgs-monitor --rebuild` if you suspect intermittent build
failures caused by eg disk being full or network going down.

Potential CVE matches are in `cve_match` table.

## comparepackages.rb

Matches packages in one distro to packages in another one.
To be used for experimentation only. Unmaintained.
Probably you don't care that it exists.

## Debian watchfiles tools

Scripts and a writeup of an experiment to see just how useful Debian watchfiles are.
Spoiler: not very useful :(
