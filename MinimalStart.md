You need to add the /bin/ directory of build result to $PATH, it is
currently not enough to run updatetool.rb by specifying full path.

updatetool.rb --list-nix initializes the database. It has to be done
first.

Afterwards it is possible to run updatetool.rb --check-updates package.
Then run updatetool.rb --tarballs. Then updatetool.rb --patches.

Then you can extract individual patches by running something like 
sqlite3 db.sqlite "select patch from patches where pkg_attr='package' and version='version';"
