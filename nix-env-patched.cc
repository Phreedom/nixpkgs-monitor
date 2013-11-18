
#include <names.hh>
#include <globals.hh>
#include <misc.hh>
#include <shared.hh>
#include <eval.hh>
#include <eval-inline.hh>
#include <get-drvs.hh>
#include <attr-path.hh>
#include <common-opts.hh>
#include <xml-writer.hh>
#include <store-api.hh>
//#include "user-env.hh"
#include <util.hh>

#include <cerrno>
#include <ctime>
#include <algorithm>
#include <iostream>
#include <sstream>

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>


using namespace nix;
using std::cout;


typedef enum {
    srcNixExprDrvs,
    srcNixExprs,
    srcStorePaths,
    srcProfile,
    srcAttrPath,
    srcUnknown
} InstallSourceType;


struct InstallSourceInfo
{
    InstallSourceType type;
    Path nixExprPath; /* for srcNixExprDrvs, srcNixExprs */
    Path profile; /* for srcProfile */
    string systemFilter; /* for srcNixExprDrvs */
    Bindings autoArgs;
};


struct Globals
{
    InstallSourceInfo instSource;
    Path profile;
    EvalState state;
    bool dryRun;
    bool preserveInstalled;
    bool removeAll;
    string forceName;
    bool prebuiltOnly;
};


typedef void (* Operation) (Globals & globals,
    Strings args, Strings opFlags, Strings opArgs);


void printHelp()
{
    showManPage("nix-env");
}


static string needArg(Strings::iterator & i,
    Strings & args, const string & arg)
{
    if (i == args.end()) throw UsageError(
        format("`%1%' requires an argument") % arg);
    return *i++;
}


static bool isNixExpr(const Path & path, struct stat & st)
{
    return S_ISREG(st.st_mode) || (S_ISDIR(st.st_mode) && pathExists(path + "/default.nix"));
}


static void getAllExprs(EvalState & state,
    const Path & path, StringSet & attrs, Value & v)
{
    Strings names = readDirectory(path);
    StringSet namesSorted(names.begin(), names.end());

    foreach (StringSet::iterator, i, namesSorted) {
        /* Ignore the manifest.nix used by profiles.  This is
           necessary to prevent it from showing up in channels (which
           are implemented using profiles). */
        if (*i == "manifest.nix") continue;

        Path path2 = path + "/" + *i;

        struct stat st;
        if (stat(path2.c_str(), &st) == -1)
            continue; // ignore dangling symlinks in ~/.nix-defexpr

        if (isNixExpr(path2, st) && (!S_ISREG(st.st_mode) || hasSuffix(path2, ".nix"))) {
            /* Strip off the `.nix' filename suffix (if applicable),
               otherwise the attribute cannot be selected with the
               `-A' option.  Useful if you want to stick a Nix
               expression directly in ~/.nix-defexpr. */
            string attrName = *i;
            if (hasSuffix(attrName, ".nix"))
                attrName = string(attrName, 0, attrName.size() - 4);
            if (attrs.find(attrName) != attrs.end()) {
                printMsg(lvlError, format("warning: name collision in input Nix expressions, skipping `%1%'") % path2);
                continue;
            }
            attrs.insert(attrName);
            /* Load the expression on demand. */
            Value & vFun(*state.allocValue());
            Value & vArg(*state.allocValue());
            state.getBuiltin("import", vFun);
            mkString(vArg, path2);
            mkApp(*state.allocAttr(v, state.symbols.create(attrName)), vFun, vArg);
        }
        else if (S_ISDIR(st.st_mode))
            /* `path2' is a directory (with no default.nix in it);
               recurse into it. */
            getAllExprs(state, path2, attrs, v);
    }
}


static void loadSourceExpr(EvalState & state, const Path & path, Value & v)
{
    struct stat st;
    if (stat(path.c_str(), &st) == -1)
        throw SysError(format("getting information about `%1%'") % path);

    if (isNixExpr(path, st)) {
        state.evalFile(path, v);
        return;
    }

    /* The path is a directory.  Put the Nix expressions in the
       directory in a set, with the file name of each expression as
       the attribute name.  Recurse into subdirectories (but keep the
       set flat, not nested, to make it easier for a user to have a
       ~/.nix-defexpr directory that includes some system-wide
       directory). */
    if (S_ISDIR(st.st_mode)) {
        state.mkAttrs(v, 16);
        state.mkList(*state.allocAttr(v, state.symbols.create("_combineChannels")), 0);
        StringSet attrs;
        getAllExprs(state, path, attrs, v);
        v.attrs->sort();
    }
}


static void loadDerivations(EvalState & state, Path nixExprPath,
    string systemFilter, Bindings & autoArgs,
    const string & pathPrefix, DrvInfos & elems)
{
    Value vRoot;
    loadSourceExpr(state, nixExprPath, vRoot);

    Value & v(*findAlongAttrPath(state, pathPrefix, autoArgs, vRoot));

    getDerivations(state, v, pathPrefix, autoArgs, elems, true);

    /* Filter out all derivations not applicable to the current
       system. */
    for (DrvInfos::iterator i = elems.begin(), j; i != elems.end(); i = j) {
        j = i; j++;
        if (systemFilter != "*" && i->system != systemFilter)
            elems.erase(i);
    }
}


static Path getHomeDir()
{
    Path homeDir(getEnv("HOME", ""));
    if (homeDir == "") throw Error("HOME environment variable not set");
    return homeDir;
}


static Path getDefNixExprPath()
{
    return getHomeDir() + "/.nix-defexpr";
}


static int getPriority(EvalState & state, const DrvInfo & drv)
{
    MetaValue value = drv.queryMetaInfo(state, "priority");
    int prio = 0;
    if (value.type == MetaValue::tpInt) prio = value.intValue;
    else if (value.type == MetaValue::tpString)
        /* Backwards compatibility.  Priorities used to be strings
           before we had support for integer meta field. */
        string2Int(value.stringValue, prio);
    return prio;
}


static int comparePriorities(EvalState & state,
    const DrvInfo & drv1, const DrvInfo & drv2)
{
    return getPriority(state, drv2) - getPriority(state, drv1);
}


static DrvInfos filterBySelector(EvalState & state, const DrvInfos & allElems,
    const Strings & args, bool newestOnly)
{
    DrvNames selectors = drvNamesFromArgs(args);
    if (selectors.empty())
        selectors.push_back(DrvName("*"));

    DrvInfos elems;
    set<unsigned int> done;

    foreach (DrvNames::iterator, i, selectors) {
        typedef list<std::pair<DrvInfo, unsigned int> > Matches;
        Matches matches;
        unsigned int n = 0;
        for (DrvInfos::const_iterator j = allElems.begin();
             j != allElems.end(); ++j, ++n)
        {
            DrvName drvName(j->name);
            if (i->matches(drvName)) {
                i->hits++;
                matches.push_back(std::pair<DrvInfo, unsigned int>(*j, n));
            }
        }

        /* If `newestOnly', if a selector matches multiple derivations
           with the same name, pick the one matching the current
           system.  If there are still multiple derivations, pick the
           one with the highest priority.  If there are still multiple
           derivations, pick the one with the highest version.
           Finally, if there are still multiple derivations,
           arbitrarily pick the first one. */
        if (newestOnly) {

            /* Map from package names to derivations. */
            typedef map<string, std::pair<DrvInfo, unsigned int> > Newest;
            Newest newest;
            StringSet multiple;

            for (Matches::iterator j = matches.begin(); j != matches.end(); ++j) {
                DrvName drvName(j->first.name);
                int d = 1;

                Newest::iterator k = newest.find(drvName.name);

                if (k != newest.end()) {
                    d = j->first.system == k->second.first.system ? 0 :
                        j->first.system == settings.thisSystem ? 1 :
                        k->second.first.system == settings.thisSystem ? -1 : 0;
                    if (d == 0)
                        d = comparePriorities(state, j->first, k->second.first);
                    if (d == 0)
                        d = compareVersions(drvName.version, DrvName(k->second.first.name).version);
                }

                if (d > 0) {
                    newest[drvName.name] = *j;
                    multiple.erase(j->first.name);
                } else if (d == 0) {
                    multiple.insert(j->first.name);
                }
            }

            matches.clear();
            for (Newest::iterator j = newest.begin(); j != newest.end(); ++j) {
                if (multiple.find(j->second.first.name) != multiple.end())
                    printMsg(lvlInfo,
                        format("warning: there are multiple derivations named `%1%'; using the first one")
                        % j->second.first.name);
                matches.push_back(j->second);
            }
        }

        /* Insert only those elements in the final list that we
           haven't inserted before. */
        for (Matches::iterator j = matches.begin(); j != matches.end(); ++j)
            if (done.find(j->second) == done.end()) {
                done.insert(j->second);
                elems.push_back(j->first);
            }
    }

    /* Check that all selectors have been used. */
    foreach (DrvNames::iterator, i, selectors)
        if (i->hits == 0 && i->fullName != "*")
            throw Error(format("selector `%1%' matches no derivations")
                % i->fullName);

    return elems;
}


static bool isPath(const string & s)
{
    return s.find('/') != string::npos;
}


static void queryInstSources(EvalState & state,
    InstallSourceInfo & instSource, const Strings & args,
    DrvInfos & elems, bool newestOnly)
{
    InstallSourceType type = instSource.type;
    if (type == srcUnknown && args.size() > 0 && isPath(args.front()))
        type = srcStorePaths;

    switch (type) {

        /* Get the available user environment elements from the
           derivations specified in a Nix expression, including only
           those with names matching any of the names in `args'. */
        case srcUnknown:
        case srcNixExprDrvs: {

            /* Load the derivations from the (default or specified)
               Nix expression. */
            DrvInfos allElems;
            loadDerivations(state, instSource.nixExprPath,
                instSource.systemFilter, instSource.autoArgs, "", allElems);

            elems = filterBySelector(state, allElems, args, newestOnly);

            break;
        }

        /* Get the available user environment elements from the Nix
           expressions specified on the command line; these should be
           functions that take the default Nix expression file as
           argument, e.g., if the file is `./foo.nix', then the
           argument `x: x.bar' is equivalent to `(x: x.bar)
           (import ./foo.nix)' = `(import ./foo.nix).bar'. */
        case srcNixExprs: {

            Value vArg;
            loadSourceExpr(state, instSource.nixExprPath, vArg);

            foreach (Strings::const_iterator, i, args) {
                Expr * eFun = state.parseExprFromString(*i, absPath("."));
                Value vFun, vTmp;
                state.eval(eFun, vFun);
                mkApp(vTmp, vFun, vArg);
                getDerivations(state, vTmp, "", instSource.autoArgs, elems, true);
            }

            break;
        }

        /* The available user environment elements are specified as a
           list of store paths (which may or may not be
           derivations). */
        case srcStorePaths: {

            for (Strings::const_iterator i = args.begin();
                 i != args.end(); ++i)
            {
                Path path = followLinksToStorePath(*i);

                DrvInfo elem;
                elem.attrs = new Bindings;
                string name = baseNameOf(path);
                string::size_type dash = name.find('-');
                if (dash != string::npos)
                    name = string(name, dash + 1);

                if (isDerivation(path)) {
                    elem.setDrvPath(path);
                    elem.setOutPath(findOutput(derivationFromPath(*store, path), "out"));
                    if (name.size() >= drvExtension.size() &&
                        string(name, name.size() - drvExtension.size()) == drvExtension)
                        name = string(name, 0, name.size() - drvExtension.size());
                }
                else elem.setOutPath(path);

                elem.name = name;

                elems.push_back(elem);
            }

            break;
        }

        case srcAttrPath: {
            Value vRoot;
            loadSourceExpr(state, instSource.nixExprPath, vRoot);
            foreach (Strings::const_iterator, i, args) {
                Value & v(*findAlongAttrPath(state, *i, instSource.autoArgs, vRoot));
                getDerivations(state, v, "", instSource.autoArgs, elems, true);
            }
            break;
        }
    }
}


static bool keep(MetaInfo & meta)
{
    MetaValue value = meta["keep"];
    return value.type == MetaValue::tpString && value.stringValue == "true";
}


static bool cmpChars(char a, char b)
{
    return toupper(a) < toupper(b);
}


static bool cmpElemByName(const DrvInfo & a, const DrvInfo & b)
{
    return lexicographical_compare(
        a.name.begin(), a.name.end(),
        b.name.begin(), b.name.end(), cmpChars);
}


typedef list<Strings> Table;


void printTable(Table & table)
{
    unsigned int nrColumns = table.size() > 0 ? table.front().size() : 0;

    vector<unsigned int> widths;
    widths.resize(nrColumns);

    foreach (Table::iterator, i, table) {
        assert(i->size() == nrColumns);
        Strings::iterator j;
        unsigned int column;
        for (j = i->begin(), column = 0; j != i->end(); ++j, ++column)
            if (j->size() > widths[column]) widths[column] = j->size();
    }

    foreach (Table::iterator, i, table) {
        Strings::iterator j;
        unsigned int column;
        for (j = i->begin(), column = 0; j != i->end(); ++j, ++column) {
            string s = *j;
            replace(s.begin(), s.end(), '\n', ' ');
            cout << s;
            if (column < nrColumns - 1)
                cout << string(widths[column] - s.size() + 2, ' ');
        }
        cout << std::endl;
    }
}


/* This function compares the version of an element against the
   versions in the given set of elements.  `cvLess' means that only
   lower versions are in the set, `cvEqual' means that at most an
   equal version is in the set, and `cvGreater' means that there is at
   least one element with a higher version in the set.  `cvUnavail'
   means that there are no elements with the same name in the set. */

typedef enum { cvLess, cvEqual, cvGreater, cvUnavail } VersionDiff;

static VersionDiff compareVersionAgainstSet(
    const DrvInfo & elem, const DrvInfos & elems, string & version)
{
    DrvName name(elem.name);

    VersionDiff diff = cvUnavail;
    version = "?";

    for (DrvInfos::const_iterator i = elems.begin(); i != elems.end(); ++i) {
        DrvName name2(i->name);
        if (name.name == name2.name) {
            int d = compareVersions(name.version, name2.version);
            if (d < 0) {
                diff = cvGreater;
                version = name2.version;
            }
            else if (diff != cvGreater && d == 0) {
                diff = cvEqual;
                version = name2.version;
            }
            else if (diff != cvGreater && diff != cvEqual && d > 0) {
                diff = cvLess;
                if (version == "" || compareVersions(version, name2.version) < 0)
                    version = name2.version;
            }
        }
    }

    return diff;
}


static string colorString(const string & s)
{
    if (!isatty(STDOUT_FILENO)) return s;
    return "\e[1;31m" + s + "\e[0m";
}


static void opQuery(Globals & globals,
    Strings args, Strings opFlags, Strings opArgs)
{
    typedef vector< map<string, string> > ResultSet;
    Strings remaining;
    string attrPath;

    bool printStatus = false;
    bool printName = true;
    bool printAttrPath = false;
    bool printSystem = false;
    bool printDrvPath = false;
    bool printOutPath = false;
    bool printDescription = false;
    bool printMeta = false;
    bool compareVersions = false;
    bool xmlOutput = false;

    enum { sInstalled, sAvailable } source = sInstalled;

    const Symbol  sRepositories(globals.state.symbols.create("repositories")),
                  sGit(globals.state.symbols.create("git")),
                  sSrc(globals.state.symbols.create("src")),
                  sRev(globals.state.symbols.create("rev")),
                  sUrl(globals.state.symbols.create("url")),
                  sUrls(globals.state.symbols.create("urls")),
                  sOutputHash(globals.state.symbols.create("outputHash"));
    
    settings.readOnlyMode = true; /* makes evaluation a bit faster */

    for (Strings::iterator i = args.begin(); i != args.end(); ) {
        string arg = *i++;
        if (arg == "--status" || arg == "-s") printStatus = true;
        else if (arg == "--no-name") printName = false;
        else if (arg == "--system") printSystem = true;
        else if (arg == "--description") printDescription = true;
        else if (arg == "--compare-versions" || arg == "-c") compareVersions = true;
        else if (arg == "--drv-path") printDrvPath = true;
        else if (arg == "--out-path") printOutPath = true;
        else if (arg == "--meta") printMeta = true;
        else if (arg == "--installed") source = sInstalled;
        else if (arg == "--available" || arg == "-a") source = sAvailable;
        else if (arg == "--xml") xmlOutput = true;
        else if (arg == "--attr-path" || arg == "-P") printAttrPath = true;
        else if (arg == "--attr" || arg == "-A")
            attrPath = needArg(i, args, arg);
        else if (arg[0] == '-')
            throw UsageError(format("unknown flag `%1%'") % arg);
        else remaining.push_back(arg);
    }


    /* Obtain derivation information from the specified source. */
    DrvInfos availElems, installedElems;

    if (source == sAvailable || compareVersions)
        loadDerivations(globals.state, globals.instSource.nixExprPath,
            globals.instSource.systemFilter, globals.instSource.autoArgs,
            attrPath, availElems);

    DrvInfos elems = filterBySelector(globals.state,
        source == sInstalled ? installedElems : availElems,
        remaining, false);

    DrvInfos & otherElems(source == sInstalled ? availElems : installedElems);


    /* Sort them by name. */
    /* !!! */
    vector<DrvInfo> elems2;
    for (DrvInfos::iterator i = elems.begin(); i != elems.end(); ++i)
        elems2.push_back(*i);
    sort(elems2.begin(), elems2.end(), cmpElemByName);


    /* We only need to know the installed paths when we are querying
       the status of the derivation. */
    PathSet installed; /* installed paths */

    if (printStatus) {
        for (DrvInfos::iterator i = installedElems.begin();
             i != installedElems.end(); ++i)
            installed.insert(i->queryOutPath(globals.state));
    }


    /* Query which paths have substitutes. */
    PathSet validPaths, substitutablePaths;
    if (printStatus || globals.prebuiltOnly) {
        PathSet paths;
        foreach (vector<DrvInfo>::iterator, i, elems2)
            try {
                paths.insert(i->queryOutPath(globals.state));
            } catch (AssertionError & e) {
                printMsg(lvlTalkative, format("skipping derivation named `%1%' which gives an assertion failure") % i->name);
                i->setFailed();
            }
        validPaths = store->queryValidPaths(paths);
        substitutablePaths = store->querySubstitutablePaths(paths);
    }


    /* Print the desired columns, or XML output. */
    Table table;
    std::ostringstream dummy;
    XMLWriter xml(true, *(xmlOutput ? &cout : &dummy));
    XMLOpenElement xmlRoot(xml, "items");

    foreach (vector<DrvInfo>::iterator, i, elems2) {
        try {
            if (i->hasFailed()) continue;

            startNest(nest, lvlDebug, format("outputting query result `%1%'") % i->attrPath);

            if (globals.prebuiltOnly &&
                validPaths.find(i->queryOutPath(globals.state)) == validPaths.end() &&
                substitutablePaths.find(i->queryOutPath(globals.state)) == substitutablePaths.end())
                continue;

            /* For table output. */
            Strings columns;

            /* For XML output. */
            XMLAttrs attrs;

            if (printStatus) {
                Path outPath = i->queryOutPath(globals.state);
                bool hasSubs = substitutablePaths.find(outPath) != substitutablePaths.end();
                bool isInstalled = installed.find(outPath) != installed.end();
                bool isValid = validPaths.find(outPath) != validPaths.end();
                if (xmlOutput) {
                    attrs["installed"] = isInstalled ? "1" : "0";
                    attrs["valid"] = isValid ? "1" : "0";
                    attrs["substitutable"] = hasSubs ? "1" : "0";
                } else
                    columns.push_back(
                        (string) (isInstalled ? "I" : "-")
                        + (isValid ? "P" : "-")
                        + (hasSubs ? "S" : "-"));
            }

            if (xmlOutput)
                attrs["attrPath"] = i->attrPath;
            else if (printAttrPath)
                columns.push_back(i->attrPath);

            if (xmlOutput)
                attrs["name"] = i->name;
            else if (printName)
                columns.push_back(i->name);

            if (compareVersions) {
                /* Compare this element against the versions of the
                   same named packages in either the set of available
                   elements, or the set of installed elements.  !!!
                   This is O(N * M), should be O(N * lg M). */
                string version;
                VersionDiff diff = compareVersionAgainstSet(*i, otherElems, version);

                char ch;
                switch (diff) {
                    case cvLess: ch = '>'; break;
                    case cvEqual: ch = '='; break;
                    case cvGreater: ch = '<'; break;
                    case cvUnavail: ch = '-'; break;
                    default: abort();
                }

                if (xmlOutput) {
                    if (diff != cvUnavail) {
                        attrs["versionDiff"] = ch;
                        attrs["maxComparedVersion"] = version;
                    }
                } else {
                    string column = (string) "" + ch + " " + version;
                    if (diff == cvGreater) column = colorString(column);
                    columns.push_back(column);
                }
            }

            if (xmlOutput) {
                if (i->system != "") attrs["system"] = i->system;
            }
            else if (printSystem)
                columns.push_back(i->system);

            if (printDrvPath) {
                string drvPath = i->queryDrvPath(globals.state);
                if (xmlOutput) {
                    if (drvPath != "") attrs["drvPath"] = drvPath;
                } else
                    columns.push_back(drvPath == "" ? "-" : drvPath);
            }

            if (printOutPath && !xmlOutput) {
                DrvInfo::Outputs outputs = i->queryOutputs(globals.state);
                string s;
                foreach (DrvInfo::Outputs::iterator, j, outputs) {
                    if (!s.empty()) s += ';';
                    if (j->first != "out") { s += j->first; s += "="; }
                    s += j->second;
                }
                columns.push_back(s);
            }

            if (printDescription) {
                MetaInfo meta = i->queryMetaInfo(globals.state);
                MetaValue value = meta["description"];
                string descr = value.type == MetaValue::tpString ? value.stringValue : "";
                if (xmlOutput) {
                    if (descr != "") attrs["description"] = descr;
                } else
                    columns.push_back(descr);
            }

            if (xmlOutput) {
                if (printOutPath || printMeta) {
                    XMLOpenElement item(xml, "item", attrs);
                    if (printOutPath) {
                        DrvInfo::Outputs outputs = i->queryOutputs(globals.state);
                        foreach (DrvInfo::Outputs::iterator, j, outputs) {
                            XMLAttrs attrs2;
                            attrs2["name"] = j->first;
                            attrs2["path"] = j->second;
                            xml.writeEmptyElement("output", attrs2);
                        }
                    }
                    if (printMeta) {
                        MetaInfo meta = i->queryMetaInfo(globals.state);
                        for (MetaInfo::iterator j = meta.begin(); j != meta.end(); ++j) {
                            XMLAttrs attrs2;
                            attrs2["name"] = j->first;
                            if (j->second.type == MetaValue::tpString) {
                                attrs2["type"] = "string";
                                attrs2["value"] = j->second.stringValue;
                                xml.writeEmptyElement("meta", attrs2);
                            } else if (j->second.type == MetaValue::tpInt) {
                                attrs2["type"] = "int";
                                attrs2["value"] = (format("%1%") % j->second.intValue).str();
                                xml.writeEmptyElement("meta", attrs2);
                            } else if (j->second.type == MetaValue::tpStrings) {
                                attrs2["type"] = "strings";
                                XMLOpenElement m(xml, "meta", attrs2);
                                foreach (Strings::iterator, k, j->second.stringValues) {
                                    XMLAttrs attrs3;
                                    attrs3["value"] = *k;
                                    xml.writeEmptyElement("string", attrs3);
                               }
                            }
                        }

                        // meta.repositories special case handling
                        Bindings::iterator meta_raw = i->attrs->find(globals.state.sMeta);
                        if (meta_raw != i->attrs->end()) {
                            globals.state.forceAttrs(*meta_raw->value);
                            Bindings::iterator repositories = meta_raw->value->attrs->find(sRepositories);
                            if (repositories != meta_raw->value->attrs->end()) {
                                globals.state.forceAttrs(*repositories->value);
                                Bindings::iterator git = repositories->value->attrs->find(sGit);
                                if (git != repositories->value->attrs->end()) {
                                    globals.state.forceValue(*git->value);
                                    if (git->value->type == tString) {
                                        XMLAttrs attrs4;
                                        attrs4["name"] = "repositories.git";
                                        attrs4["type"] = "string";
                                        attrs4["value"] = git->value->string.s;
                                        xml.writeEmptyElement("meta", attrs4);
                                    }
                                }
                            }
                        }

                        // src attr special case handling
                        Bindings::iterator src = i->attrs->find(sSrc);
                        if (src != i->attrs->end()) {
                            globals.state.forceValue(*src->value);
                            if (src->value->type == tAttrs) {
                                Bindings::iterator urls = src->value->attrs->find(sUrls);
                                if (urls != src->value->attrs->end()) {
                                    globals.state.forceList(*urls->value);
                                    if (urls->value->list.length > 0) {
                                        XMLAttrs attrs5;
                                        Value *url = urls->value->list.elems[0];

                                        attrs5["name"] = "src.url";
                                        attrs5["type"] = "string";
                                        attrs5["value"] = globals.state.forceStringNoCtx(*url);
                                        xml.writeEmptyElement("meta", attrs5);
                                    }
                                }
                                Bindings::iterator url = src->value->attrs->find(sUrl);
                                if (url != src->value->attrs->end()) {
                                   XMLAttrs attrs6;
                                   attrs6["name"] = "src.repo";
                                   attrs6["type"] = "string";
                                   attrs6["value"] = globals.state.forceStringNoCtx(*url->value);
                                   xml.writeEmptyElement("meta", attrs6);
                                }
                                Bindings::iterator rev = src->value->attrs->find(sRev);
                                if (rev != src->value->attrs->end()) {
                                   globals.state.forceValue(*rev->value);
                                   XMLAttrs attrs7;
                                   attrs7["name"] = "src.rev";
                                   attrs7["type"] = "string";
                                   if (rev->value->type == tString) {
                                       attrs7["value"] = rev->value->string.s;
                                   } else if (rev->value->type == tInt) {
                                       attrs7["value"] = (format("%1%") % rev->value->integer).str();
                                   }
                                   xml.writeEmptyElement("meta", attrs7);
                                }
                                Bindings::iterator sha256 = src->value->attrs->find(sOutputHash);
                                if (sha256 != src->value->attrs->end()) {
                                   XMLAttrs attrs6;
                                   attrs6["name"] = "src.sha256";
                                   attrs6["type"] = "string";
                                   attrs6["value"] = globals.state.forceStringNoCtx(*sha256->value);
                                   xml.writeEmptyElement("meta", attrs6);
                                }
                            }
                        }
                    }
                } else
                    xml.writeEmptyElement("item", attrs);
            } else
                table.push_back(columns);

            cout.flush();

        } catch (AssertionError & e) {
            printMsg(lvlTalkative, format("skipping derivation named `%1%' which gives an assertion failure") % i->name);
        }
    }

    if (!xmlOutput) printTable(table);
}


static const int prevGen = -2;


void run(Strings args)
{
    Strings opFlags, opArgs, remaining;
    Operation op = 0;

    Globals globals;

    globals.instSource.type = srcUnknown;
    globals.instSource.nixExprPath = getDefNixExprPath();
    globals.instSource.systemFilter = "*";

    globals.dryRun = false;
    globals.preserveInstalled = false;
    globals.removeAll = false;
    globals.prebuiltOnly = false;

    for (Strings::iterator i = args.begin(); i != args.end(); ) {
        string arg = *i++;

        Operation oldOp = op;

        if (parseOptionArg(arg, i, args.end(),
                     globals.state, globals.instSource.autoArgs))
            ;
        else if (parseSearchPathArg(arg, i, args.end(), globals.state))
            ;
        else if (arg == "--force-name") // undocumented flag for nix-install-package
            globals.forceName = needArg(i, args, arg);
        else if (arg == "--query" || arg == "-q")
            op = opQuery;
        else if (arg == "--file" || arg == "-f")
            globals.instSource.nixExprPath = lookupFileArg(globals.state, needArg(i, args, arg));
        else if (arg == "--dry-run") {
            printMsg(lvlInfo, "(dry run; not doing anything)");
            globals.dryRun = true;
        }
        else if (arg == "--system-filter")
            globals.instSource.systemFilter = needArg(i, args, arg);
        else {
            remaining.push_back(arg);
            if (arg[0] == '-') {
                opFlags.push_back(arg);
                if (arg == "--from-profile") { /* !!! hack */
                    if (i != args.end()) opFlags.push_back(*i++);
                }
            } else opArgs.push_back(arg);
        }

        if (oldOp && oldOp != op)
            throw UsageError("only one operation may be specified");
    }

    if (!op) throw UsageError("no operation specified");

    if (globals.profile == "")
        globals.profile = getEnv("NIX_PROFILE", "");

    if (globals.profile == "") {
        Path profileLink = getHomeDir() + "/.nix-profile";
        globals.profile = pathExists(profileLink)
            ? absPath(readLink(profileLink), dirOf(profileLink))
            : canonPath(settings.nixStateDir + "/profiles/default");
    }

    store = openStore();

    op(globals, remaining, opFlags, opArgs);

    globals.state.printStats();
}


string programId = "nix-env";
