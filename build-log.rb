require "open-uri"

module BuildLog

  def BuildLog.lint(log)
    package_names = [ "gobject-introspection",

                      # documentation
                      "gtkdoc-check", "gtkdoc-rebase", "gtkdoc-mkpdf",
                      "gtk-doc documentation", "bison", "byacc", "flex", "lex", "pkg-config",
                      "doxygen", "msgfmt", "gmsgfmt", "xgettext", "msgmerge", "gnome-doc-utils",
                      "documentation", "manpages", "txt2html", "rst2html", "xmlto", "asciidoc",

                      # archives
                      "lzma", "zlib", "bzlib",

                      # TODO: something for gif, jpeg etc
                      ]
    lint = log.lines.select do |line|
      linedc = line.downcase
      package_names.find{ |pn| linedc =~ /checking .*#{pn}.*\.\.\..*(no|:)/ or linedc =~ /could not find .*#{pn}/ } or
      linedc.include? 'not installed' or # perl prequisites
      linedc =~ /skipped.* require/ or # perl test dependencies
      linedc =~ /skipped.* no.* available/ or # perl test dependencies
      linedc.=~ /subroutine .* redefined at/ or# perl warning
      linedc =~ /prerequisite .* not found/ or # perl warning
      linedc.include? "module not found" or # perl warning
      linedc =~ /failed.*test/ or # perl test failure
      linedc =~ /skipped:.*only with/ # perl warning
    end

    return lint
  end


  def BuildLog.sanitize(log, substitutes = {})
    sanitized = log.dup
    substitutes.each{ |orig, value| sanitized.gsub!(orig, value) }
    sanitized.gsub(%r{/nix/store/(\S{32})}, '/nix/store/...')
  end


  def BuildLog.get_hydra_log(outpath)
    open("http://hydra.nixos.org/log/#{outpath.sub(%r{^/nix/store/},"")}").read rescue nil
  end

  def BuildLog.get_db_log(outpath)
    build = DB[:builds][:outpath => outpath]
    build && build[:log]
  end

  def BuildLog.get_log(outpath)
    get_db_log(outpath) || get_hydra_log(outpath)
  end

end