# Debian watchfiles playground

This was an attempt at estimating the quality of update
coverage provided by Debian watchfiles.


## How to replicate the experiment

All these tools expect a debian repository checkout:
  wget  -r -np http://ftp.debian.org/debian/pool/ -A '*debian*'

update.pl is a hacked version of Debian's uscan tool modified to
produce the list of all available tarballs and not only the most recent one.

unpack_watchfiles.rb extracts all available watchfiles from debian repos to watchfiles dir

get_urls.rb obtains all available tarballs using watchfiles and puts the lists into deb_urls dir


## Some stats

Total packages:
find ftp.debian.org/ -iname '*.debian.tar.gz'|wc -l
23007

Packages may not be unique, that is several versions
of the same package may be in the repo.

Total watchfiles(extracted using a simple script):
find watchfiles/|wc -l
20347

Watchfiles that returned some URLs:
find deb_urls/|wc -l
16400

Watchfiles tend to be present for more popular/important packages,
which also tend to have several versions in the repos at once.
Due to this skew, the sheer number of watchfiles covers less
unique packages than it seems at first.


## Why debian watchfiles suck. Lessons learned

* Maintainers are (lazy) people
* Maintainers probably have other ways to watch for release such as RSS, MLs 
or personal contacts. debian is huge and probably can afford a nontechnical
solution to this problem.
* Writing resilient and reliable watchfiles requires skill and understanding of 
what can break. It can be practically obtained only when you deal with a large
sample of tarball names.
* Expecting hundreds of maintainers acquire this knowledge independently is 
not reasonable.
* Upstream needs to actually be aware of the fact that the releases are 
watched by software and take care to not break it.
* Educating upstream is even less practical thus watchfiles themselves are 
subject to bit rot, especially for long-tail packages.