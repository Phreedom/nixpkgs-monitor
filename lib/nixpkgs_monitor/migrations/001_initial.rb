Sequel.migration do
  change do

    # updaters

    [ :repository_cpan, :repository_fetchgit, :repository_github,
      :repository_gnome, :repository_gnu, :repository_hackage,
      :repository_kde, :repository_metagit, :repository_npmjs,
      :repository_pypi, :repository_rubygems, :repository_sf,
      :repository_xorg, :gentoodistfiles,
      :distro_arch, :distro_aur, :distro_debian, :distro_gentoo,
    ].each do |updater|
      DB.create_table!(updater) do
        String :pkg_attr
        String :version
        primary_key [ :pkg_attr, :version ]
      end
    end

    create_table(:estimated_coverage) do
      String :pkg_attr, :unique => true, :primary_key => true
      Integer :coverage
    end

    create_table(:tarball_sha256) do
      String :tarball, :unique => true, :primary_key => true
      String :sha256
    end

    create_table(:tarballs) do
      String :pkg_attr
      String :version
      String :tarball
    end

    create_table(:patches) do
      String :pkg_attr
      String :version
      String :tarball
      primary_key [ :pkg_attr, :version, :tarball ]
      Text :patch
      String :drvpath
      String :outpath
    end

    create_table(:builds) do
      String :outpath, :unique => true, :primary_key => true
      String :status
      String :log
    end

    create_table(:cve_match) do
      String :pkg_attr#, :primary_key => true
      String :product
      String :version
      String :CVE
    end

    create_table(:timestamps) do
      String :action, :unique => true, :primary_key => true
      Time :timestamp
      String :message
    end

    # package cache

    create_table!(:packages_nix) do
      String :internal_name, :unique => true, :primary_key => true
      String :name
      String :version
      String :repository_git
      String :branch
      String :url
      String :revision
      String :sha256
      String :position
      String :homepage
      String :drvpath
      String :outpath
    end

    create_table!(:nix_maintainers) do
      String :internal_name
      String :maintainer
    end

    create_table!(:packages_gentoo) do
      String :internal_name, :unique => true, :primary_key => true
      String :name
      String :version
      String :url
      String :version_overlay
      String :version_upstream
      String :revision
    end

    create_table!(:packages_arch) do
      String :internal_name, :unique => true, :primary_key => true
      String :name
      String :version
      String :url
      String :revision
    end

    create_table!(:packages_aur) do
      String :internal_name, :unique => true, :primary_key => true
      String :name
      String :version
      String :url
      String :revision
    end

    create_table!(:packages_debian) do
      String :internal_name, :unique => true, :primary_key => true
      String :name
      String :version
      String :url
      String :revision
    end

    # logs
    [ :nixpkgs_failed_name_parse, :nixpkgs_no_sources, :version_mismatch ].each do |log_name|
      create_table!(log_name) do
        String :pkg_attr, :unique => true, :primary_key => true
      end
    end

  end
end