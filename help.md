# Reports:

## Coverage

The number of different update sources available for a given package.
This report is an estimate. More precise report can only be obtained
during an actual updater run and it isn't being done yet.

## Vulnerability

A list of potential matches against CVE vulnerability database. Unfortunately,
the report is noisy because the matching code has been tuned to give virtually
no false negatives. That is, it tries to never miss a match.

## Outdated:

A list of packages for which newer versions were reported by updaters. The report
generator tries to be smart and guess which version is a major update (most likely
requiring extensive testing) and which one is a minor update(safe to commit if it
compiles).

### Flags

(V) beside the package name: the package is potentially vulnerable

Beside version numbers:

(P) the patch is available and builds fine

(f) the patch is available but failed to build

(p) the patch is available but not yet built

## Package Details

Clicking a package name shows more details including specific CVE matches,
found tarballs, available patches and corresponding build logs and statuses.

## Build logs

There's a buildlog-lint code which tries to detect subtle problems such as
missing dependencies and add helpful warnings at the top of the log. Currently,
it's a proof-of-concept code which detects typical missing documentation-related
dependencies such as doxygen, missing perl dependencies and failed tests.

# Suggested Workflow

Before committing a patch, take a look at its build log to check for irregularities,
even if it compiles and is a minor update.

A patch can be applied using curl 'patch url'|git am

It's recommended to re-set the author fields before pushing to nixpkgs. You can do
this for a of a whole bunch of commits in one go:

    git filter-branch --env-filter 'export GIT_AUTHOR_NAME="Joe Doe" GIT_AUTHOR_EMAIL=joe@example.com' origin/master..master
