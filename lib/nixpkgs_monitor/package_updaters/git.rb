require 'nixpkgs_monitor/package_updaters/base'

module NixPkgsMonitor module PackageUpdaters module Git

  # Generic git-based updater. Discovers new versions using git repository tags.
  class Base < NixPkgsMonitor::PackageUpdaters::Base

    def self.ls_remote
      @repo_cache ||= Hash.new do |repo_cache, repo|
        repo_cache[repo] = %x(GIT_ASKPASS="echo" SSH_ASKPASS= git ls-remote #{repo})
                                .force_encoding("iso-8859-1")
                                .split("\n")
      end
    end

    # Tries to handle the tag as a tarball name.
    # if parsing it as a tarball fails, treats it as a version.
    def self.tag_to_version(tag_line)
      if %r{refs/tags.*/[vr]?(?<tag>\S*?)(\^\{\})?$} =~ tag_line
        if tag =~ /^[vr]?\d/
          return tag
        else
          (name, version) = parse_tarball_name(tag)
          return (version ? version : tag)
        end
      else
        return nil
      end
    end

    def self.repo_contents_to_tags(repo_contents)
      repo_contents.select{ |s| s.include? "refs/tags/" }
                    .map{ |tag| tag_to_version(tag) }
    end

  end


  # Handles fetchgit-based packages.
  # Tries to detect which tag the current revision corresponds to.
  # Otherwise assumes the package is tracking master because
  # there's no easy way to be smarter without checking out the repository.
  # Tries to find a newer tag or if tracking master, newest commit.
  class FetchGit < Base

    def self.covers?(pkg)
      pkg.url and not(pkg.revision.to_s.empty?) and pkg.url.include? "git"
    end


    def self.newest_version_of(pkg)
      return nil unless covers?(pkg)

      repo_contents = ls_remote[pkg.url].select{|s| s.include?("refs/tags") or s.include?("refs/heads/master") }
      tag_line = repo_contents.index{|line| line.include? pkg.revision }

      log.debug "for #{pkg.revision} found #{tag_line}"
      if tag_line # revision refers to a tag?
        return nil if repo_contents[tag_line].include?("refs/heads/master")

        current_version = tag_to_version(repo_contents[tag_line])

        if current_version and usable_version?(current_version)

          versions = repo_contents_to_tags(repo_contents)
          max_version = versions.reduce(current_version) do |v1, v2|
            ( usable_version?(v2) and is_newer?(v2, v1) ) ? v2 : v1
          end
          return (max_version != current_version ? max_version : nil)

        else
          log.warn "failed to parse tag #{repo_contents[tag_line]} for #{pkg.name}. Assuming tracking master"
        end
      end

      # assuming tracking master
      master_line = repo_contents.index{|line| line.include? "refs/heads/master" }
      if master_line
        /^(?<master_commit>\S*)/ =~ repo_contents[master_line]
        log.info "new master commit #{master_commit} for #{pkg.name}:#{pkg.revision}"
        return( master_commit.start_with?(pkg.revision) ? nil : master_commit )
      else
        log.warn "failed to find master for #{pkg.name}"
        return nil
      end

    end

  end


  # Handles GitHub-provided tarballs.
  class GitHub < Base

    def self.covers?(pkg)
      pkg.revision.to_s.empty? and pkg.url  =~ %r{^https?://github.com/} and usable_version?(pkg.version)
    end

    def self.newest_version_of(pkg)
      return nil unless covers?(pkg)
      return nil unless %r{^https?://github.com/(?:downloads/)?(?<owner>[^/]*)/(?<repo>[^/]*)/} =~ pkg.url

      available_versions = repo_contents_to_tags( ls_remote["https://github.com/#{owner}/#{repo}.git"] )
      new_versions(pkg.version.downcase, available_versions, pkg.internal_name)
    end

  end


  # Handles packages which specify meta.repositories.git.
  class MetaGit < Base

    # if meta.repository.git is the same as src.url, defer to FetchGit updater
    def self.covers?(pkg)
      not(pkg.repository_git.to_s.empty?) and (pkg.repository_git != pkg.url) and usable_version?(pkg.version)
    end

    def self.newest_version_of(pkg)
      return nil unless covers?(pkg)

      available_versions = repo_contents_to_tags( ls_remote[pkg.repository_git] )
      new_versions(pkg.version.downcase, available_versions, pkg.internal_name)
    end

  end

  Updaters = [ FetchGit, GitHub, MetaGit ]

end end end
