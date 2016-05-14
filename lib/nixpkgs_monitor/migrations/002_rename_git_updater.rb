Sequel.migration do
  change do

    # rename tables to match updater renames
    DB.rename_table(:repository_fetchgit, :git_fetchgit)
    DB.rename_table(:repository_github, :git_github)
    DB.rename_table(:repository_metagit, :git_metagit)

  end
end
