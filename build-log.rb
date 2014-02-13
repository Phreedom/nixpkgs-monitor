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

end