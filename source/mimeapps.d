/**
 * Finding associations between MIME types and applications.
 * Authors:
 *  $(LINK2 https://github.com/FreeSlave, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2016
 * License:
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also:
 *  $(LINK2 https://www.freedesktop.org/wiki/Specifications/mime-apps-spec/, MIME Applications Associations)
 */

module mimeapps;

private {
    import std.algorithm;
    import std.array;
    import std.exception;
    import std.file;
    import std.path;
    import std.range;
    import std.traits;

    import xdgpaths;
    import isfreedesktop;
    import findexecutable;
}

public import desktopfile.file;

private @nogc @trusted auto parseMimeTypeName(String)(String name) pure nothrow if (isSomeString!String && is(ElementEncodingType!String : char))
{
    alias Tuple!(String, "media", String, "subtype") MimeTypeName;

    String media;
    String subtype;

    size_t i;
    for (i=0; i<name.length; ++i) {
        if (name[i] == '/') {
            media = name[0..i];
            subtype = name[i+1..$];
            break;
        }
    }

    return MimeTypeName(media, subtype);
}

unittest
{
    auto t = parseMimeTypeName("text/plain");
    assert(t.media == "text" && t.subtype == "plain");

    t = parseMimeTypeName("not mime type");
    assert(t.media == string.init && t.subtype == string.init);
}

private @nogc @trusted bool allSymbolsAreValid(scope const(char)[] name) nothrow pure
{
    import std.ascii : isAlpha, isDigit;
    for (size_t i=0; i<name.length; ++i) {
        char c = name[i];
        if (!(c.isAlpha || c.isDigit || c == '-' || c == '+' || c == '.' || c == '_')) {
            return false;
        }
    }
    return true;
}

private @nogc @safe bool isValidMimeTypeName(scope const(char)[] name) nothrow pure
{
    auto t = parseMimeTypeName(name);
    return t.media.length && t.subtype.length && allSymbolsAreValid(t.media) && allSymbolsAreValid(t.subtype);
}

unittest
{
    assert( isValidMimeTypeName("text/plain"));
    assert( isValidMimeTypeName("text/plain2"));
    assert( isValidMimeTypeName("text/vnd.type"));
    assert( isValidMimeTypeName("x-scheme-handler/http"));
    assert(!isValidMimeTypeName("not mime type"));
    assert(!isValidMimeTypeName("not()/valid"));
    assert(!isValidMimeTypeName("not/valid{}"));
    assert(!isValidMimeTypeName("text/"));
    assert(!isValidMimeTypeName("/plain"));
    assert(!isValidMimeTypeName("/"));
}

private @trusted void validateMimeType(string groupName, string mimeType, string value) {
    if (!isValidMimeTypeName(mimeType)) {
        throw new IniLikeEntryException("Invalid MIME type name", groupName, mimeType, value);
    }
}

static if (isFreedesktop)
{
    version(unittest) {
        import std.process : environment;

        package struct EnvGuard
        {
            this(string env, string newValue) {
                envVar = env;
                envValue = environment.get(env);
                environment[env] = newValue;
            }

            ~this() {
                if (envValue is null) {
                    environment.remove(envVar);
                } else {
                    environment[envVar] = envValue;
                }
            }

            string envVar;
            string envValue;
        }
    }

    private enum mimeAppsList = "mimeapps.list";
    private enum applicationsMimeAppsList = "applications/mimeapps.list";

    /// Get desktop prefixes for mimeapps.list overrides.
    @safe auto getDesktopPrefixes() nothrow
    {
        import std.process : environment;
        import std.uni : toLower;
        import std.utf : byCodeUnit;

        string xdgCurrentDesktop;
        collectException(environment.get("XDG_CURRENT_DESKTOP"), xdgCurrentDesktop);
        return xdgCurrentDesktop.byCodeUnit.splitter(':').map!(prefix => prefix.toLower);
    }

    ///
    unittest
    {
        auto currentDesktopGuard = EnvGuard("XDG_CURRENT_DESKTOP", "LXQT");
        assert(equal(getDesktopPrefixes(), ["lxqt"]));

        environment["XDG_CURRENT_DESKTOP"] = "unity:GNOME";
        assert(equal(getDesktopPrefixes(), ["unity", "gnome"]));
    }

    private @safe string[] getDesktopPrefixesArray() nothrow
    {
        string[] toReturn;
        collectException(getDesktopPrefixes().array, toReturn);
        return toReturn;
    }

    /**
     * Find all writable mimeapps.list files locations including specific for the current desktop.
     * Found paths are not checked for existence or write access.
     *
     * $(BLUE This function is Freedesktop only).
     * See_Also: $(D userMimeAppsListPaths), $(D userAppDataMimeAppsListPaths)
     */
    deprecated @safe string[] writableMimeAppsListPaths() nothrow
    {
        return userMimeAppsListPaths() ~ userAppDataMimeAppsListPaths();
    }

    /// ditto, but using user-provided prefix.
    deprecated @safe string[] writableMimeAppsListPaths(const string[] desktopPrefixes) nothrow
    {
        return userMimeAppsListPaths(desktopPrefixes) ~ userAppDataMimeAppsListPaths(desktopPrefixes);
    }

    /**
     * Find mimeapps.list files locations for user overrides including specific for the current desktop.
     * Found paths are not checked for existence or write access.
     *
     * $(BLUE This function is Freedesktop only).
     * See_Also: $(LINK2 https://specifications.freedesktop.org/mime-apps-spec/latest/ar01s02.html, File name and location)
     */
    @safe string[] userMimeAppsListPaths() nothrow
    {
        return userMimeAppsListPaths(getDesktopPrefixesArray());
    }

    ///
    unittest
    {
        auto configHomeGuard = EnvGuard("XDG_CONFIG_HOME", "/home/user/config");
        auto configDirsGuard = EnvGuard("XDG_CONFIG_DIRS", "/etc/xdg");

        auto dataHomeGuard = EnvGuard("XDG_DATA_HOME", "/home/user/data");
        auto dataDirsGuard = EnvGuard("XDG_DATA_DIRS", "/usr/local/data:/usr/data");

        auto currentDesktopGuard = EnvGuard("XDG_CURRENT_DESKTOP", "unity:GNOME");

        assert(userMimeAppsListPaths() == ["/home/user/config/unity-mimeapps.list", "/home/user/config/gnome-mimeapps.list", "/home/user/config/mimeapps.list"]);
    }

    /// ditto, but using user-provided desktop prefixes (can be empty, in which case desktop-specific mimeapps.list locations are not included).
    @safe string[] userMimeAppsListPaths(const string[] desktopPrefixes) nothrow
    {
        string[] toReturn;
        string configHome = xdgConfigHome();
        if (configHome.length) {
            foreach(string desktopPrefix; desktopPrefixes)
            {
                toReturn ~= buildPath(configHome, desktopPrefix ~ "-" ~ mimeAppsList);
            }
            toReturn ~= buildPath(configHome, mimeAppsList);
        }
        return toReturn;
    }

    /**
     * Find mimeapps.list files deprecated locations for user overrides including specific for the current desktop.
     * Found paths are not checked for existence or write access.
     * These locations are kept for compatibility.
     *
     * $(BLUE This function is Freedesktop only).
     * See_Also: $(LINK2 https://specifications.freedesktop.org/mime-apps-spec/latest/ar01s02.html, File name and location)
     */
    @safe string[] userAppDataMimeAppsListPaths() nothrow
    {
        return userAppDataMimeAppsListPaths(getDesktopPrefixesArray());
    }

    ///
    unittest
    {
        auto dataHomeGuard = EnvGuard("XDG_DATA_HOME", "/home/user/data");
        auto currentDesktopGuard = EnvGuard("XDG_CURRENT_DESKTOP", "unity:GNOME");

        assert(userAppDataMimeAppsListPaths() == ["/home/user/data/applications/unity-mimeapps.list", "/home/user/data/applications/gnome-mimeapps.list", "/home/user/data/applications/mimeapps.list"]);
    }

    /// ditto, but using user-provided desktop prefixes (can be empty, in which case desktop-specific mimeapps.list locations are not included).
    @safe string[] userAppDataMimeAppsListPaths(const string[] desktopPrefixes) nothrow
    {
        string[] toReturn;
        string appHome = xdgDataHome("applications");
        if (appHome.length) {
            foreach(string desktopPrefix; desktopPrefixes)
            {
                toReturn ~= buildPath(appHome, desktopPrefix ~ "-" ~ mimeAppsList);
            }
            toReturn ~= buildPath(appHome, mimeAppsList);
        }
        return toReturn;
    }

    /**
     * Find mimeapps.list files locations for sysadmin and ISV overrides including specific for the current desktop.
     * Found paths are not checked for existence.
     *
     * $(BLUE This function is Freedesktop only).
     * See_Also: $(LINK2 https://specifications.freedesktop.org/mime-apps-spec/latest/ar01s02.html, File name and location)
     */
    @safe string[] vendorMimeAppsListPaths() nothrow
    {
        return vendorMimeAppsListPaths(getDesktopPrefixesArray());
    }

    ///
    unittest
    {
        auto configDirsGuard = EnvGuard("XDG_CONFIG_DIRS", "/etc/xdg");
        auto currentDesktopGuard = EnvGuard("XDG_CURRENT_DESKTOP", "unity:GNOME");

        assert(vendorMimeAppsListPaths() == ["/etc/xdg/unity-mimeapps.list", "/etc/xdg/gnome-mimeapps.list", "/etc/xdg/mimeapps.list"]);
    }

    /// ditto, but using user-provided desktop prefixes (can be empty, in which case desktop-specific mimeapps.list locations are not included).
    @safe string[] vendorMimeAppsListPaths(const string[] desktopPrefixes) nothrow
    {
        string[] toReturn;
        string[] configDirs = xdgConfigDirs();

        foreach(string desktopPrefix; desktopPrefixes)
        {
            foreach(configDir; configDirs)
            {
                toReturn ~= buildPath(configDir, desktopPrefix ~ "-" ~ mimeAppsList);
            }
        }
        foreach(configDir; configDirs)
        {
            toReturn ~= buildPath(configDir, mimeAppsList);
        }
        return toReturn;
    }

    /**
     * Find mimeapps.list files locations for distribution provided defaults including specific for the current desktop.
     * Found paths are not checked for existence.
     *
     * $(BLUE This function is Freedesktop only).
     * See_Also: $(LINK2 https://specifications.freedesktop.org/mime-apps-spec/latest/ar01s02.html, File name and location)
     */
    @safe string[] distributionMimeAppsListPaths() nothrow
    {
        return distributionMimeAppsListPaths(getDesktopPrefixesArray());
    }

    ///
    unittest
    {
        auto dataDirsGuard = EnvGuard("XDG_DATA_DIRS", "/usr/local/data:/usr/data");
        auto currentDesktopGuard = EnvGuard("XDG_CURRENT_DESKTOP", "unity:GNOME");

        assert(distributionMimeAppsListPaths() == [
                "/usr/local/data/applications/unity-mimeapps.list", "/usr/data/applications/unity-mimeapps.list",
                "/usr/local/data/applications/gnome-mimeapps.list", "/usr/data/applications/gnome-mimeapps.list",
                "/usr/local/data/applications/mimeapps.list",       "/usr/data/applications/mimeapps.list"]);
    }

    /// ditto, but using user-provided desktop prefixes (can be empty, in which case desktop-specific mimeapps.list locations are not included).
    @safe string[] distributionMimeAppsListPaths(const string[] desktopPrefixes) nothrow
    {
        string[] toReturn;
        string[] appDataDirs = xdgDataDirs("applications");

        foreach(string desktopPrefix; desktopPrefixes)
        {
            foreach(appDataDir; appDataDirs)
            {
                toReturn ~= buildPath(appDataDir, desktopPrefix ~ "-" ~ mimeAppsList);
            }
        }
        foreach(appDataDir; appDataDirs)
        {
            toReturn ~= buildPath(appDataDir, mimeAppsList);
        }
        return toReturn;
    }

    /**
     * Find all known mimeapps.list files locations.
     * Found paths are not checked for existence.
     *
     * $(BLUE This function is Freedesktop only).
     * Returns: Paths of mimeapps.list files in the system.
     * See_Also: $(LINK2 https://specifications.freedesktop.org/mime-apps-spec/latest/ar01s02.html, File name and location)
     */
    @safe string[] mimeAppsListPaths() nothrow
    {
        return mimeAppsListPaths(getDesktopPrefixesArray());
    }

    /// ditto, but using user-provided desktop prefixes (can be empty, in which case desktop-specific mimeapps.list locations are not included).
    @safe string[] mimeAppsListPaths(const string[] desktopPrefixes) nothrow
    {
        return userMimeAppsListPaths(desktopPrefixes) ~ vendorMimeAppsListPaths(desktopPrefixes) ~
            userAppDataMimeAppsListPaths(desktopPrefixes) ~ distributionMimeAppsListPaths(desktopPrefixes);
    }

    /**
     * Find all known mimeinfo.cache files locations. Found paths are not checked for existence.
     *
     * $(BLUE This function is Freedesktop only).
     * Returns: Paths of mimeinfo.cache files in the system.
     */
    @safe string[] mimeInfoCachePaths() nothrow
    {
        return xdgAllDataDirs("applications/mimeinfo.cache");
    }

    ///
    unittest
    {
        auto dataHomeGuard = EnvGuard("XDG_DATA_HOME", "/home/user/data");
        auto dataDirsGuard = EnvGuard("XDG_DATA_DIRS", "/usr/local/data:/usr/data");

        assert(mimeInfoCachePaths() == [
            "/home/user/data/applications/mimeinfo.cache",
            "/usr/local/data/applications/mimeinfo.cache", "/usr/data/applications/mimeinfo.cache"
        ]);
    }
}

/**
 * $(D inilike.file.IniLikeGroup) subclass for easy access to the list of applications associated with given type.
 */
final class MimeAppsGroup : IniLikeGroup
{
    protected @nogc @safe this(string groupName) nothrow {
        super(groupName);
    }

    /**
     * Split string list of desktop ids into range.
     * See_Also: $(D joinApps)
     */
    static @trusted auto splitApps(string apps) {
        return std.algorithm.splitter(apps, ";").filter!(s => !s.empty);
    }

    ///
    unittest
    {
        assert(splitApps("kde4-kate.desktop;kde4-kwrite.desktop;geany.desktop;").equal(["kde4-kate.desktop", "kde4-kwrite.desktop", "geany.desktop"]));
    }

    /**
     * Join list of desktop ids into string.
     * See_Also: $(D splitApps)
     */
    static @trusted string joinApps(Range)(Range apps, bool trailingSemicolon = true) if (isInputRange!Range && is(ElementType!Range : string))
    {
        auto result = apps.filter!( s => !s.empty ).joiner(";");
        if (result.empty) {
            return null;
        } else {
            return text(result) ~ (trailingSemicolon ? ";" : "");
        }
    }

    ///
    unittest
    {
        assert(joinApps(["kde4-kate.desktop", "kde4-kwrite.desktop", "geany.desktop"]) == "kde4-kate.desktop;kde4-kwrite.desktop;geany.desktop;");
        assert(joinApps((string[]).init) == string.init);
        assert(joinApps(["geany.desktop"], false) == "geany.desktop");
        assert(joinApps(["geany.desktop"], true) == "geany.desktop;");
        assert(joinApps((string[]).init, true) == string.init);
    }

    /**
     * List applications for given mimeType.
     * Returns: Range of $(B Desktop id)s for mimeType.
     */
    @safe auto appsForMimeType(string mimeType) const {
        return splitApps(unescapedValue(mimeType));
    }

    /**
     * Delete desktopId from the list of desktop ids for mimeType.
     */
    @trusted void deleteAssociation(string mimeType, string desktopId)
    {
        auto appsStr = unescapedValue(mimeType);
        if (appsStr.length) {
            const bool hasSemicolon = appsStr[$-1] == ';';
            auto apps = splitApps(appsStr);
            if (apps.canFind(desktopId)) {
                auto without = apps.filter!(d => d != desktopId);
                if (without.empty) {
                    removeEntry(mimeType);
                } else {
                    setUnescapedValue(mimeType, MimeAppsGroup.joinApps(without, hasSemicolon));
                }
            }
        }
    }

    /**
     * Set list of desktop ids for mimeType. This overwrites existing list completely.
     * Can be used to set the list of added assocations rearranged in client code to manage the preference order.
     */
    @safe void setAssocations(Range)(string mimeType, Range desktopIds) if (isInputRange!Range && is(ElementType!Range : string))
    {
        setUnescapedValue(mimeType, joinApps(desktopIds));
    }

protected:
    @trusted override void validateKey(string key, string value) const {
        validateMimeType(groupName(), key, value);
    }
}

/**
 * Class represenation of single mimeapps.list file containing information about MIME type associations and default applications.
 */
final class MimeAppsListFile : IniLikeFile
{
    /**
     * Read mimeapps.list file.
     * Throws:
     *  $(B ErrnoException) if file could not be opened.
     *  $(D inilike.file.IniLikeReadException) if error occured while reading the file or "MIME Cache" group is missing.
     */
    @trusted this(string fileName, ReadOptions readOptions = ReadOptions.init)
    {
        this(iniLikeFileReader(fileName), fileName, readOptions);
    }

    /**
     * Read MIME type associations from $(D inilike.range.IniLikeReader), e.g. acquired from $(D inilike.range.iniLikeFileReader) or $(D inilike.range.iniLikeStringReader).
     * Throws:
     *  $(D inilike.file.IniLikeReadException) if error occured while parsing or "MIME Cache" group is missing.
     */
    this(IniLikeReader)(IniLikeReader reader, string fileName = null, ReadOptions readOptions = ReadOptions.init)
    {
        super(reader, fileName, readOptions);
        _defaultApps = cast(MimeAppsGroup)group("Default Applications");
        _addedApps = cast(MimeAppsGroup)group("Added Associations");
        _removedApps = cast(MimeAppsGroup)group("Removed Associations");
    }

    this()
    {
        super();
    }

    /**
     * Access "Desktop Applications" group of default associations.
     * Returns: $(D MimeAppsGroup) for "Desktop Applications" group or null if file does not have such group.
     * See_Also: $(D addedAssociations)
     */
    @safe inout(MimeAppsGroup) defaultApplications() nothrow inout pure {
        return _defaultApps;
    }

    /**
     * Access "Added Associations" group of explicitly added associations.
     * Returns: $(D MimeAppsGroup) for "Added Associations" group or null if file does not have such group.
     * See_Also: $(D defaultApplications), $(D removedAssociations)
     */
    @safe inout(MimeAppsGroup) addedAssociations() nothrow inout pure {
        return _addedApps;
    }

    /**
     * Access "Removed Associations" group of explicitily removed associations.
     * Returns: $(D MimeAppsGroup) for "Removed Associations" group or null if file does not have such group.
     * See_Also: $(D addedAssociations)
     */
    @safe inout(MimeAppsGroup) removedAssociations() nothrow inout pure {
        return _removedApps;
    }

    /**
     * Set desktopId as default application for mimeType.
     * Set it as first element in the list of added associations.
     * Delete it from removed associations if listed.
     * Note: This only changes the object, but not file itself.
     */
    @trusted void setDefaultApplication(string mimeType, string desktopId)
    {
        if (mimeType.empty || desktopId.empty) {
            return;
        }
        ensureDefaultApplications();
        _defaultApps.setUnescapedValue(mimeType, desktopId);
        ensureAddedAssociations();
        auto added = _addedApps.appsForMimeType(mimeType);
        auto withoutThis = added.filter!(d => d != desktopId);
        auto resorted = only(desktopId).chain(withoutThis);
        _addedApps.setUnescapedValue(mimeType, MimeAppsGroup.joinApps(resorted));

        if (_removedApps !is null) {
            _removedApps.deleteAssociation(mimeType, desktopId);
        }
    }

    ///
    unittest
    {
        MimeAppsListFile appsList = new MimeAppsListFile();
        appsList.setDefaultApplication("text/plain", "geany.desktop");
        assert(appsList.defaultApplications() !is null);
        assert(appsList.addedAssociations() !is null);
        assert(appsList.defaultApplications().appsForMimeType("text/plain").equal(["geany.desktop"]));
        assert(appsList.addedAssociations().appsForMimeType("text/plain").equal(["geany.desktop"]));

        appsList.setDefaultApplication("image/png", null);
        assert(!appsList.defaultApplications().contains("image/png"));

        string contents =
`[Default Applications]
text/plain=kde4-kate.desktop`;

        appsList = new MimeAppsListFile(iniLikeStringReader(contents));
        appsList.setDefaultApplication("text/plain", "geany.desktop");
        assert(appsList.defaultApplications().appsForMimeType("text/plain").equal(["geany.desktop"]));
        assert(appsList.addedAssociations().appsForMimeType("text/plain").equal(["geany.desktop"]));

        contents =
`[Default Applications]
text/plain=kde4-kate.desktop
[Added Associations]
text/plain=kde4-kate.desktop;emacs.desktop;`;

        appsList = new MimeAppsListFile(iniLikeStringReader(contents));
        appsList.setDefaultApplication("text/plain", "geany.desktop");
        assert(appsList.defaultApplications().appsForMimeType("text/plain").equal(["geany.desktop"]));
        assert(appsList.addedAssociations().appsForMimeType("text/plain").equal(["geany.desktop", "kde4-kate.desktop", "emacs.desktop"]));

        contents =
`[Default Applications]
text/plain=emacs.desktop
[Added Associations]
text/plain=emacs.desktop;kde4-kate.desktop;geany.desktop;`;

        appsList = new MimeAppsListFile(iniLikeStringReader(contents));
        appsList.setDefaultApplication("text/plain", "geany.desktop");
        assert(appsList.defaultApplications().appsForMimeType("text/plain").equal(["geany.desktop"]));
        assert(appsList.addedAssociations().appsForMimeType("text/plain").equal(["geany.desktop", "emacs.desktop", "kde4-kate.desktop"]));

        contents =
`[Default Applications]
text/plain=emacs.desktop
[Added Associations]
text/plain=emacs.desktop;kde4-kate.desktop;
[Removed Associations]
text/plain=kde4-okular.desktop;geany.desktop`;

        appsList = new MimeAppsListFile(iniLikeStringReader(contents));
        appsList.setDefaultApplication("text/plain", "geany.desktop");
        assert(appsList.removedAssociations() !is null);
        assert(appsList.defaultApplications().appsForMimeType("text/plain").equal(["geany.desktop"]));
        assert(appsList.addedAssociations().appsForMimeType("text/plain").equal(["geany.desktop", "emacs.desktop", "kde4-kate.desktop"]));
        assert(appsList.removedAssociations().appsForMimeType("text/plain").equal(["kde4-okular.desktop"]));
    }

    /**
     * Add desktopId as association for mimeType.
     * Delete it from removed associations if listed.
     * Note: This only changes the object, but not file itself.
     */
    @trusted void addAssociation(string mimeType, string desktopId)
    {
        if (mimeType.empty || desktopId.empty) {
            return;
        }
        ensureAddedAssociations();
        auto added = _addedApps.appsForMimeType(mimeType);
        if (!added.canFind(desktopId)) {
            _addedApps.setUnescapedValue(mimeType, MimeAppsGroup.joinApps(chain(added, only(desktopId))));
        }
        if (_removedApps) {
            _removedApps.deleteAssociation(mimeType, desktopId);
        }
    }

    ///
    unittest
    {
        MimeAppsListFile appsList = new MimeAppsListFile();
        appsList.addAssociation("text/plain", "geany.desktop");
        assert(appsList.addedAssociations() !is null);
        assert(appsList.addedAssociations().appsForMimeType("text/plain").equal(["geany.desktop"]));

        appsList.addAssociation("image/png", null);
        assert(!appsList.addedAssociations().contains("image/png"));

        string contents =
`[Added Associations]
text/plain=kde4-kate.desktop;emacs.desktop
[Removed Associations]
text/plain=kde4-okular.desktop;geany.desktop;`;

        appsList = new MimeAppsListFile(iniLikeStringReader(contents));
        appsList.addAssociation("text/plain", "geany.desktop");
        assert(appsList.addedAssociations().appsForMimeType("text/plain").equal(["kde4-kate.desktop", "emacs.desktop", "geany.desktop"]));
        assert(appsList.removedAssociations().appsForMimeType("text/plain").equal(["kde4-okular.desktop"]));

        contents =
`[Removed Associations]
text/plain=geany.desktop;`;

        appsList = new MimeAppsListFile(iniLikeStringReader(contents));
        appsList.addAssociation("text/plain", "geany.desktop");
        assert(appsList.addedAssociations().appsForMimeType("text/plain").equal(["geany.desktop"]));
        assert(!appsList.removedAssociations().contains("text/plain"));
    }

    /**
     * Explicitly remove desktopId association for mimeType.
     * Delete it from added associations and default applications.
     * Note: This only changes the object, but not file itself.
     */
    @trusted void removeAssociation(string mimeType, string desktopId)
    {
        if (mimeType.empty || desktopId.empty) {
            return;
        }
        ensureRemovedAssociations();
        auto removed = _removedApps.appsForMimeType(mimeType);
        if (!removed.canFind(desktopId)) {
            _removedApps.setUnescapedValue(mimeType, MimeAppsGroup.joinApps(chain(removed, only(desktopId))));
        }
        if (_addedApps) {
            _addedApps.deleteAssociation(mimeType, desktopId);
        }
        if (_defaultApps) {
            _defaultApps.deleteAssociation(mimeType, desktopId);
        }
    }

    /**
     * Set list of desktop ids as assocations for $(D mimeType). This overwrites existing assocations.
     * Note: This only changes the object, but not file itself.
     * See_Also: $(D MimeAppsGroup.setAssocations)
     */
    @trusted void setAddedAssocations(Range)(string mimeType, Range desktopIds) if (isInputRange!Range && is(ElementType!Range : string))
    {
        ensureAddedAssociations();
        _addedApps.setAssocations(mimeType, desktopIds);
    }

    ///
    unittest
    {
        MimeAppsListFile appsList = new MimeAppsListFile();
        appsList.removeAssociation("text/plain", "geany.desktop");
        assert(appsList.removedAssociations() !is null);
        assert(appsList.removedAssociations().appsForMimeType("text/plain").equal(["geany.desktop"]));

        appsList.removeAssociation("image/png", null);
        assert(!appsList.removedAssociations().contains("image/png"));

        string contents =
`[Default Applications]
text/plain=geany.desktop
[Added Associations]
text/plain=emacs.desktop;geany.desktop;kde4-kate.desktop;`;

        appsList = new MimeAppsListFile(iniLikeStringReader(contents));
        appsList.removeAssociation("text/plain", "geany.desktop");
        assert(appsList.removedAssociations().appsForMimeType("text/plain").equal(["geany.desktop"]));
        assert(appsList.addedAssociations().appsForMimeType("text/plain").equal(["emacs.desktop", "kde4-kate.desktop"]));
        assert(!appsList.defaultApplications().contains("text/plain"));

        contents =
`[Added Associations]
text/plain=geany.desktop;`;

        appsList = new MimeAppsListFile(iniLikeStringReader(contents));
        appsList.removeAssociation("text/plain", "geany.desktop");
        assert(appsList.removedAssociations().appsForMimeType("text/plain").equal(["geany.desktop"]));
        assert(!appsList.addedAssociations().contains("text/plain"));
    }

    ///Create empty "Default Applications" group if it does not exist.
    @trusted final void ensureDefaultApplications() {
        ensureGroupExists(_defaultApps, "Default Applications");
    }

    ///Create empty "Added Associations" group if it does not exist.
    @trusted final void ensureAddedAssociations() {
        ensureGroupExists(_addedApps, "Added Associations");
    }

    ///Create empty "Removed Associations" group if it does not exist.
    @trusted final void ensureRemovedAssociations() {
        ensureGroupExists(_removedApps, "Removed Associations");
    }

protected:
    @trusted override IniLikeGroup createGroupByName(string groupName)
    {
        if (groupName == "Default Applications") {
            return new MimeAppsGroup(groupName);
        } else if (groupName == "Added Associations") {
            return new MimeAppsGroup(groupName);
        } else if (groupName == "Removed Associations") {
            return new MimeAppsGroup(groupName);
        } else {
            return null;
        }
    }
private:
    @trusted final void ensureGroupExists(ref MimeAppsGroup group, string name)
    {
        if (group is null) {
            group = new MimeAppsGroup(name);
            insertGroup(group);
        }
    }

    MimeAppsGroup _addedApps;
    MimeAppsGroup _removedApps;
    MimeAppsGroup _defaultApps;
}

///
unittest
{
    string content =
`[Added Associations]
text/plain=geany.desktop;kde4-kwrite.desktop;
image/png=kde4-gwenview.desktop;gthumb.desktop;

[Removed Associations]
text/plain=libreoffice-writer.desktop;

[Default Applications]
text/plain=kde4-kate.desktop
x-scheme-handler/http=chromium.desktop;iceweasel.desktop;


[Unknown group]
Key=Value`;
    auto mimeAppsList = new MimeAppsListFile(iniLikeStringReader(content));
    assert(mimeAppsList.addedAssociations() !is null);
    assert(mimeAppsList.removedAssociations() !is null);
    assert(mimeAppsList.defaultApplications() !is null);
    assert(mimeAppsList.group("Unknown group") is null);

    assert(mimeAppsList.addedAssociations().appsForMimeType("text/plain").equal(["geany.desktop", "kde4-kwrite.desktop"]));
    assert(mimeAppsList.removedAssociations().appsForMimeType("text/plain").equal(["libreoffice-writer.desktop"]));
    assert(mimeAppsList.defaultApplications().appsForMimeType("x-scheme-handler/http").equal(["chromium.desktop", "iceweasel.desktop"]));

    content =
`[Default Applications]
text/plain=geany.desktop
notmimetype=value
`;
    assertThrown!IniLikeReadException(new MimeAppsListFile(iniLikeStringReader(content)));
    assertNotThrown(mimeAppsList = new MimeAppsListFile(iniLikeStringReader(content), null, IniLikeFile.ReadOptions(IniLikeGroup.InvalidKeyPolicy.save)));
    assert(mimeAppsList.defaultApplications().escapedValue("notmimetype") == "value");
}

/**
 * Class represenation of single mimeinfo.cache file containing information about MIME type associations.
 * Note: Unlike $(D MimeAppsListFile) this class does not provide functions for associations update.
 *  This is because mimeinfo.cache files should be updated by $(B update-desktop-database) utility from
 *  $(LINK2 https://www.freedesktop.org/wiki/Software/desktop-file-utils/, desktop-file-utils).
 */
final class MimeInfoCacheFile : IniLikeFile
{
    /**
     * Read MIME Cache from file.
     * Throws:
     *  $(B ErrnoException) if file could not be opened.
     *  $(D inilike.file.IniLikeReadException) if error occured while reading the file or "MIME Cache" group is missing.
     */
    @trusted this(string fileName, ReadOptions readOptions = ReadOptions.init)
    {
        this(iniLikeFileReader(fileName), fileName, readOptions);
    }

    /**
     * Constructs MimeInfoCacheFile with empty MIME Cache group.
     */
    @safe this() {
        super();
        _mimeCache = new MimeAppsGroup("MIME Cache");
        insertGroup(_mimeCache);
    }

    ///
    unittest
    {
        auto micf = new MimeInfoCacheFile();
        assert(micf.mimeCache() !is null);
    }

    /**
     * Read MIME Cache from $(D inilike.range.IniLikeReader), e.g. acquired from $(D inilike.range.iniLikeFileReader) or $(D inilike.range.iniLikeStringReader).
     * Throws:
     *  $(D inilike.file.IniLikeReadException) if error occured while parsing or "MIME Cache" group is missing.
     */
    this(IniLikeReader)(IniLikeReader reader, string fileName = null, ReadOptions readOptions = ReadOptions.init)
    {
        super(reader, fileName, readOptions);
        _mimeCache = cast(MimeAppsGroup)group("MIME Cache");
        enforce(_mimeCache !is null, new IniLikeReadException("No \"MIME Cache\" group", 0));
    }

    /**
     * Access "MIME Cache" group.
     */
    @safe inout(MimeAppsGroup) mimeCache() nothrow inout pure {
        return _mimeCache;
    }

    /**
     * Alias for easy access to "MIME Cache" group.
     */
    alias mimeCache this;

protected:
    @trusted override IniLikeGroup createGroupByName(string groupName)
    {
        if (groupName == "MIME Cache") {
            return new MimeAppsGroup(groupName);
        } else {
            return null;
        }
    }
private:
    MimeAppsGroup _mimeCache;
}

///
unittest
{
    string content =
`[Some group]
Key=Value
`;
    assertThrown!IniLikeReadException(new MimeInfoCacheFile(iniLikeStringReader(content)));

    content =
`[MIME Cache]
text/plain=geany.desktop;kde4-kwrite.desktop;
image/png=kde4-gwenview.desktop;gthumb.desktop;
`;

    auto mimeInfoCache = new MimeInfoCacheFile(iniLikeStringReader(content));
    assert(mimeInfoCache.appsForMimeType("text/plain").equal(["geany.desktop", "kde4-kwrite.desktop"]));
    assert(mimeInfoCache.appsForMimeType("image/png").equal(["kde4-gwenview.desktop", "gthumb.desktop"]));
    assert(mimeInfoCache.appsForMimeType("application/nonexistent").empty);

    content =
`[MIME Cache]
text/plain=geany.desktop;
notmimetype=value
`;
    assertThrown!IniLikeReadException(new MimeInfoCacheFile(iniLikeStringReader(content)));
    assertNotThrown(mimeInfoCache = new MimeInfoCacheFile(iniLikeStringReader(content), null, IniLikeFile.ReadOptions(IniLikeGroup.InvalidKeyPolicy.save)));
    assert(mimeInfoCache.mimeCache.escapedValue("notmimetype") == "value");
}

/**
 * Create $(D MimeAppsListFile) objects for paths.
 * Returns: Array of $(D MimeAppsListFile) objects read from paths. If some could not be read it's not included in the results.
 */
@trusted MimeAppsListFile[] mimeAppsListFiles(const(string)[] paths) nothrow
{
    return paths.map!(function(string path) {
        MimeAppsListFile file;
        collectException(new MimeAppsListFile(path), file);
        return file;
    }).filter!(file => file !is null).array;
}

///
unittest
{
    assert(mimeAppsListFiles(["test/applications/mimeapps.list"]).length == 1);
}

static if (isFreedesktop)
{
    /**
     * ditto, but automatically read $(D MimeAppsListFile) objects from determined system paths.
     *
     * $(BLUE This function is Freedesktop only).
     */
    @safe MimeAppsListFile[] mimeAppsListFiles() nothrow {
        return mimeAppsListFiles(mimeAppsListPaths());
    }
}

/**
 * Create $(D MimeInfoCacheFile) objects for paths.
 * Returns: Array of $(D MimeInfoCacheFile) objects read from paths. If some could not be read it's not included in the results.
 */
@trusted MimeInfoCacheFile[] mimeInfoCacheFiles(const(string)[] paths) nothrow
{
    return paths.map!(function(string path) {
        MimeInfoCacheFile file;
        collectException(new MimeInfoCacheFile(path), file);
        return file;
    }).filter!(file => file !is null).array;
}

///
unittest
{
    assert(mimeInfoCacheFiles(["test/applications/mimeinfo.cache"]).length == 1);
}

static if (isFreedesktop)
{
    /**
     * ditto, but automatically read MimeInfoCacheFile objects from determined system paths.
     *
     * $(BLUE This function is Freedesktop only).
     */
    @safe MimeInfoCacheFile[] mimeInfoCacheFiles() nothrow {
        return mimeInfoCacheFiles(mimeInfoCachePaths());
    }
}

/**
 * Interface for desktop file provider.
 * See_Also: $(D findAssociatedApplications), $(D findKnownAssociatedApplications), $(D findDefaultApplication)
 */
interface IDesktopFileProvider
{
    /**
     * Retrieve $(D desktopfile.file.DesktopFile) by desktopId
     * Returns: Found $(D desktopfile.file.DesktopFile) or null if not found.
     */
    const(DesktopFile) getByDesktopId(string desktopId);
}

/**
 * Implementation of simple desktop file provider.
 */
class DesktopFileProvider : IDesktopFileProvider
{
private:
    static struct DesktopFileItem
    {
        DesktopFile desktopFile;
        string baseDir;
    }

public:
    /**
     * Construct using given application paths.
     * Params:
     *  applicationsPaths = Paths of applications/ directories where .desktop files are stored. These should be all known paths even if they don't exist at the time.
     *  binPaths = Paths where executable files are stored.
     *  options = Options used to read desktop files.
     */
    @trusted this(in string[] applicationsPaths, in string[] binPaths, DesktopFile.DesktopReadOptions options = DesktopFile.DesktopReadOptions.init) {
        _baseDirs = applicationsPaths.dup;
        _readOptions = options;
        _binPaths = binPaths.dup;
    }

    /// ditto, but determine binPaths from $(B PATH) environment variable automatically.
    @trusted this(in string[] applicationsPaths, DesktopFile.DesktopReadOptions options = DesktopFile.DesktopReadOptions.init) {
        this(applicationsPaths, binPaths().array, options);
    }

    /**
     * Get DesktopFile by desktop id.
     *
     * This implementation searches $(B applicationsPaths) given in constructor to find, parse and cache .desktop file.
     * If found file has $(D TryExec) value it also checks if executable can be found in $(B binPaths).
     * Note: Exec value is left unchecked.
     */
    override const(DesktopFile) getByDesktopId(string desktopId)
    {
        auto itemIn = desktopId in _cache;
        if (itemIn) {
            return itemIn.desktopFile;
        } else {
            auto foundItem = getDesktopFileItem(desktopId);
            if (foundItem.desktopFile !is null) {
                _cache[desktopId] = foundItem;
                return foundItem.desktopFile;
            }
        }
        return null;
    }
private:
    DesktopFileItem getDesktopFileItem(string desktopId)
    {
        string baseDir;
        string filePath = findDesktopFilePath(desktopId, baseDir);
        if (filePath.length) {
            try {
                auto desktopFile = new DesktopFile(filePath, _readOptions);
                string tryExec = desktopFile.tryExecValue();
                if (tryExec.length) {
                    string executable = findExecutable(tryExec, _binPaths);
                    if (executable.empty) {
                        return DesktopFileItem.init;
                    }
                }

                return DesktopFileItem(desktopFile, baseDir);
            } catch(Exception e) {
                return DesktopFileItem.init;
            }
        }
        return DesktopFileItem.init;
    }

    string findDesktopFilePath(string desktopId, out string dir)
    {
        foreach(baseDir; _baseDirs) {
            auto filePath = findDesktopFile(desktopId, only(baseDir));
            if (filePath.length) {
                dir = baseDir;
                return filePath;
            }
        }
        return null;
    }

    DesktopFileItem[string] _cache;
    string[] _baseDirs;
    DesktopFile.DesktopReadOptions _readOptions;
    string[] _binPaths;
}

private enum FindAssocFlag {
    none = 0,
    onlyFirst = 1,
    ignoreRemovedGroup = 2
}

private string[] listAssociatedApplicationsImpl(ListRange, CacheRange)(string mimeType, ListRange mimeAppsListFiles, CacheRange mimeInfoCacheFiles, FindAssocFlag flag = FindAssocFlag.none)
{
    string[] removed;
    string[] desktopIds;

    foreach(mimeAppsListFile; mimeAppsListFiles) {
        if (mimeAppsListFile is null) {
            continue;
        }

        auto removedAppsGroup = mimeAppsListFile.removedAssociations();
        if (removedAppsGroup !is null && !(flag & FindAssocFlag.ignoreRemovedGroup)) {
            removed ~= removedAppsGroup.appsForMimeType(mimeType).array;
        }
        auto addedAppsGroup = mimeAppsListFile.addedAssociations();
        if (addedAppsGroup !is null) {
            foreach(desktopId; addedAppsGroup.appsForMimeType(mimeType)) {
                if (removed.canFind(desktopId) || desktopIds.canFind(desktopId)) {
                    continue;
                }
                desktopIds ~= desktopId;
            }
        }
    }

    foreach(mimeInfoCacheFile; mimeInfoCacheFiles) {
        if (mimeInfoCacheFile is null) {
            continue;
        }

        foreach(desktopId; mimeInfoCacheFile.appsForMimeType(mimeType)) {
            if (removed.canFind(desktopId) || desktopIds.canFind(desktopId)) {
                continue;
            }
            desktopIds ~= desktopId;
        }
    }

    return desktopIds;
}

private const(DesktopFile)[] findAssociatedApplicationsImpl(ListRange, CacheRange)(string mimeType, ListRange mimeAppsListFiles, CacheRange mimeInfoCacheFiles, IDesktopFileProvider desktopFileProvider, FindAssocFlag flag = FindAssocFlag.none)
{
    const(DesktopFile)[] desktopFiles;
    foreach(desktopId; listAssociatedApplicationsImpl(mimeType, mimeAppsListFiles, mimeInfoCacheFiles, flag)) {
        auto desktopFile = desktopFileProvider.getByDesktopId(desktopId);
        if (desktopFile && desktopFile.desktopEntry.escapedValue("Exec").length != 0) {
            if (flag & FindAssocFlag.onlyFirst) {
                return [desktopFile];
            }
            desktopFiles ~= desktopFile;
        }
    }
    return desktopFiles;
}
/**
 * List associated applications for given MIME type.
 * Params:
 *  mimeType = MIME type or uri scheme handler in question.
 *  mimeAppsListFiles = Range of $(D MimeAppsListFile) objects to use in searching.
 *  mimeInfoCacheFiles = Range of $(D MimeInfoCacheFile) objects to use in searching.
 * Returns: Array of desktop ids of applications that are capable of opening of given MIME type or url of given scheme.
 * Note: It does not check if returned desktop ids point to valid .desktop files.
 * See_Also: $(D findAssociatedApplications)
 */
string[] listAssociatedApplications(ListRange, CacheRange)(string mimeType, ListRange mimeAppsListFiles, CacheRange mimeInfoCacheFiles) if(isForwardRange!ListRange && is(ElementType!ListRange : const(MimeAppsListFile))
    && isForwardRange!CacheRange && is(ElementType!CacheRange : const(MimeInfoCacheFile)))
{
    return listAssociatedApplicationsImpl(mimeType, mimeAppsListFiles, mimeInfoCacheFiles);
}

/**
 * List all known associated applications for given MIME type, including explicitly removed by user.
 * Params:
 *  mimeType = MIME type or uri scheme handler in question.
 *  mimeAppsListFiles = Range of $(D MimeAppsListFile) objects to use in searching.
 *  mimeInfoCacheFiles = Range of $(D MimeInfoCacheFile) objects to use in searching.
 * Returns: Array of desktop ids of applications that are capable of opening of given MIME type or url of given scheme.
 * Note: It does not check if returned desktop ids point to valid .desktop files.
 * See_Also: $(D listAssociatedApplications), $(D findKnownAssociatedApplications)
 */
string[] listKnownAssociatedApplications(ListRange, CacheRange)(string mimeType, ListRange mimeAppsListFiles, CacheRange mimeInfoCacheFiles)
if(isForwardRange!ListRange && is(ElementType!ListRange : const(MimeAppsListFile))
    && isForwardRange!CacheRange && is(ElementType!CacheRange : const(MimeInfoCacheFile)))
{
    return listAssociatedApplicationsImpl(mimeType, mimeAppsListFiles, mimeInfoCacheFiles, FindAssocFlag.ignoreRemovedGroup);
}

/**
 * List explicitily set default applications for given MIME type.
 * Params:
 *  mimeType = MIME type or uri scheme handler in question.
 *  mimeAppsListFiles = Range of $(D MimeAppsListFile) objects to use in searching.
 * Returns: Array of desktop ids of default applications.
 * Note: It does not check if returned desktop ids point to valid .desktop files.
 * See_Also: $(D findDefaultApplication)
 */
string[] listDefaultApplications(ListRange)(string mimeType, ListRange mimeAppsListFiles)
if(isForwardRange!ListRange && is(ElementType!ListRange : const(MimeAppsListFile)))
{
    string[] defaultApplications;
    foreach(mimeAppsListFile; mimeAppsListFiles) {
        if (mimeAppsListFile is null) {
            continue;
        }
        auto defaultAppsGroup = mimeAppsListFile.defaultApplications();
        if (defaultAppsGroup !is null) {
            foreach(desktopId; defaultAppsGroup.appsForMimeType(mimeType)) {
                defaultApplications ~= desktopId;
            }
        }
    }
    return defaultApplications;
}

/**
 * Find associated applications for given MIME type.
 * Params:
 *  mimeType = MIME type or uri scheme handler in question.
 *  mimeAppsListFiles = Range of $(D MimeAppsListFile) objects to use in searching.
 *  mimeInfoCacheFiles = Range of $(D MimeInfoCacheFile) objects to use in searching.
 *  desktopFileProvider = Desktop file provider instance. Must be non-null.
 * Returns: Array of found $(D desktopfile.file.DesktopFile) objects capable of opening file of given MIME type or url of given scheme.
 * Note: If no applications found for this mimeType, you may consider to use this function on parent MIME type.
 * See_Also: $(LINK2 https://specifications.freedesktop.org/mime-apps-spec/latest/ar01s04.html, Adding/removing associations), $(D findKnownAssociatedApplications), $(D listAssociatedApplications)
 */
const(DesktopFile)[] findAssociatedApplications(ListRange, CacheRange)(string mimeType, ListRange mimeAppsListFiles, CacheRange mimeInfoCacheFiles, IDesktopFileProvider desktopFileProvider)
if(isForwardRange!ListRange && is(ElementType!ListRange : const(MimeAppsListFile))
    && isForwardRange!CacheRange && is(ElementType!CacheRange : const(MimeInfoCacheFile)))
in {
    assert(desktopFileProvider !is null);
}
body {
    return findAssociatedApplicationsImpl(mimeType, mimeAppsListFiles, mimeInfoCacheFiles, desktopFileProvider);
}

///
version(mimeappsFileTest) unittest
{
    auto desktopProvider = new DesktopFileProvider(["test/applications"]);
    auto mimeAppsList = new MimeAppsListFile("test/applications/mimeapps.list");
    auto mimeInfoCache = new MimeInfoCacheFile("test/applications/mimeinfo.cache");
    assert(findAssociatedApplications("text/plain", [null, mimeAppsList], [null, mimeInfoCache], desktopProvider)
        .map!(d => d.displayName()).equal(["Geany", "Kate", "Emacs"]));
    assert(findAssociatedApplications("application/nonexistent", [mimeAppsList], [mimeInfoCache], desktopProvider).length == 0);
    assert(findAssociatedApplications("application/x-data", [mimeAppsList], [mimeInfoCache], desktopProvider).length == 0);
}

/**
 * Find all known associated applications for given MIME type, including explicitly removed by user.
 * Params:
 *  mimeType = MIME type or uri scheme handler in question.
 *  mimeAppsListFiles = Range of $(D MimeAppsListFile) objects to use in searching.
 *  mimeInfoCacheFiles = Range of $(D MimeInfoCacheFile) objects to use in searching.
 *  desktopFileProvider = Desktop file provider instance. Must be non-null.
 * Returns: Array of found $(D desktopfile.file.DesktopFile) objects capable of opening file of given MIME type or url of given scheme.
 * See_Also: $(D findAssociatedApplications), $(D listKnownAssociatedApplications)
 */
const(DesktopFile)[] findKnownAssociatedApplications(ListRange, CacheRange)(string mimeType, ListRange mimeAppsListFiles, CacheRange mimeInfoCacheFiles, IDesktopFileProvider desktopFileProvider)
if(isForwardRange!ListRange && is(ElementType!ListRange : const(MimeAppsListFile))
    && isForwardRange!CacheRange && is(ElementType!CacheRange : const(MimeInfoCacheFile)))
in {
    assert(desktopFileProvider !is null);
}
body {
    return findAssociatedApplicationsImpl(mimeType, mimeAppsListFiles, mimeInfoCacheFiles, desktopFileProvider, FindAssocFlag.ignoreRemovedGroup);
}

///
version(mimeappsFileTest) unittest
{
    auto desktopProvider = new DesktopFileProvider(["test/applications"]);
    auto mimeAppsList = new MimeAppsListFile("test/applications/mimeapps.list");
    auto mimeInfoCache = new MimeInfoCacheFile("test/applications/mimeinfo.cache");
    assert(findKnownAssociatedApplications("text/plain", [null, mimeAppsList], [null, mimeInfoCache], desktopProvider)
        .map!(d => d.displayName()).equal(["Geany", "Kate", "Emacs", "Okular"]));
}

/**
 * Find default application for given MIME type.
 * Params:
 *  mimeType = MIME type or uri scheme handler in question.
 *  mimeAppsListFiles = Range of $(D MimeAppsListFile) objects to use in searching.
 *  mimeInfoCacheFiles = Range of $(D MimeInfoCacheFile) objects to use in searching.
 *  desktopFileProvider = Desktop file provider instance. Must be non-null.
 * Returns: Found $(D desktopfile.file.DesktopFile) or null if not found.
 * Note: You may consider calling this function on parent MIME types (recursively until application is found) if it fails for the original mimeType.
 *      Retrieving parent MIME types is out of the scope of this library. $(LINK2 https://github.com/FreeSlave/mime, MIME library) is available for that purpose.
 *      Check the $(LINK2 https://github.com/FreeSlave/mimeapps/blob/master/examples/open.d, Open example).
 * See_Also: $(LINK2 https://specifications.freedesktop.org/mime-apps-spec/latest/ar01s03.html, Default Application)
 */
const(DesktopFile) findDefaultApplication(ListRange, CacheRange)(string mimeType, ListRange mimeAppsListFiles, CacheRange mimeInfoCacheFiles, IDesktopFileProvider desktopFileProvider)
if(isForwardRange!ListRange && is(ElementType!ListRange : const(MimeAppsListFile))
    && isForwardRange!CacheRange && is(ElementType!CacheRange : const(MimeInfoCacheFile)))
in {
    assert(desktopFileProvider !is null);
}
body {
    foreach(desktopId; listDefaultApplications(mimeType, mimeAppsListFiles)) {
        auto desktopFile = desktopFileProvider.getByDesktopId(desktopId);
        if (desktopFile !is null && desktopFile.desktopEntry.escapedValue("Exec").length != 0) {
            return desktopFile;
        }
    }

    auto desktopFiles = findAssociatedApplicationsImpl(mimeType, mimeAppsListFiles, mimeInfoCacheFiles, desktopFileProvider, FindAssocFlag.onlyFirst);
    return desktopFiles.length ? desktopFiles.front : null;
}

///
version(mimeappsFileTest) unittest
{
    auto desktopProvider = new DesktopFileProvider(["test/applications"]);
    auto mimeAppsList = new MimeAppsListFile("test/applications/mimeapps.list");
    auto mimeInfoCache = new MimeInfoCacheFile("test/applications/mimeinfo.cache");
    assert(findDefaultApplication("text/plain", [null, mimeAppsList], [null, mimeInfoCache], desktopProvider).displayName() == "Geany");
    assert(findDefaultApplication("image/png", [mimeAppsList], [mimeInfoCache], desktopProvider).displayName() == "Gwenview");
    assert(findDefaultApplication("application/pdf", [mimeAppsList], [mimeInfoCache], desktopProvider).displayName() == "Okular");
    assert(findDefaultApplication("application/nonexistent", [mimeAppsList], [mimeInfoCache], desktopProvider) is null);
    assert(findDefaultApplication("application/x-data", [mimeAppsList], [mimeInfoCache], desktopProvider) is null);
}

/**
 * Struct used for construction of file assocation update query.
 * This allows to reuse the same query many times or for many mimeapps.list files.
 */
struct AssociationUpdateQuery
{
    // Operation on MIME type application assocication.
    private static struct Operation
    {
        // Type of operation
        enum Type : ubyte {
            add,
            remove,
            setDefault,
            setAdded
        }

        string mimeType;
        string desktopId;
        Type type;
    }

    /**
     * See_Also: $(D MimeAppsListFile.addAssociation)
     */
    @safe ref typeof(this) addAssociation(string mimeType, string desktopId) return nothrow
    {
        _operations ~= Operation(mimeType, desktopId, Operation.Type.add);
        return this;
    }
    /**
     * See_Also: $(D MimeAppsListFile.setAddedAssocations)
     */
    @safe ref typeof(this) setAddedAssocations(Range)(string mimeType, Range desktopIds) return if (isInputRange!Range && is(ElementType!Range : string))
    {
        _operations ~= Operation(mimeType, MimeAppsGroup.joinApps(desktopIds), Operation.Type.setAdded);
        return this;
    }
    /**
     * See_Also: $(D MimeAppsListFile.removeAssociation)
     */
    @safe ref typeof(this) removeAssociation(string mimeType, string desktopId) return nothrow
    {
        _operations ~= Operation(mimeType, desktopId, Operation.Type.remove);
        return this;
    }
    /**
     * See_Also: $(D MimeAppsListFile.setDefaultApplication)
     */
    @safe ref typeof(this) setDefaultApplication(string mimeType, string desktopId) return nothrow
    {
        _operations ~= Operation(mimeType, desktopId, Operation.Type.setDefault);
        return this;
    }

    /**
     * Apply query to $(D MimeAppsListFile).
     */
    @safe void apply(scope MimeAppsListFile file) const
    {
        foreach(op; _operations)
        {
            final switch(op.type)
            {
                case Operation.Type.add:
                    file.addAssociation(op.mimeType, op.desktopId);
                    break;
                case Operation.Type.remove:
                    file.removeAssociation(op.mimeType, op.desktopId);
                    break;
                case Operation.Type.setDefault:
                    file.setDefaultApplication(op.mimeType, op.desktopId);
                    break;
                case Operation.Type.setAdded:
                    file.setAddedAssocations(op.mimeType, MimeAppsGroup.splitApps(op.desktopId));
                    break;
            }
        }
    }
private:
    Operation[] _operations;
}

///
unittest
{
    AssociationUpdateQuery query;
    query.addAssociation("text/plain", "geany.desktop");
    query.removeAssociation("text/plain", "kde4-okular.desktop");
    query.setDefaultApplication("text/plain", "kde4-kate.desktop");
    query.setAddedAssocations("image/png", ["kde4-gwenview.desktop", "gthumb.desktop"]);

    auto file = new MimeAppsListFile();
    query.apply(file);
    file.addedAssociations().appsForMimeType("text/plain").equal(["kde4-kate.desktop", "geany.desktop"]);
    file.defaultApplications().appsForMimeType("text/plain").equal(["kde4-kate.desktop"]);
    file.removedAssociations().appsForMimeType("text/plain").equal(["kde4-okular.desktop"]);
    file.addedAssociations().appsForMimeType("image/png").equal(["kde4-gwenview.desktop", "gthumb.desktop"]);
}

/**
 * Apply query for file with fileName. This should be mimeapps.list file.
 * If file does not exist it will be created.
 * Throws:
 *   $(D inilike.file.IniLikeReadException) if errors occured during the file reading.
 *   $(B ErrnoException) if errors occured during the file writing.
 */
@trusted void updateAssociations(string fileName, ref scope const AssociationUpdateQuery query)
{
    MimeAppsListFile file;
    if (fileName.exists) {
        file = new MimeAppsListFile(fileName);
    } else {
        file = new MimeAppsListFile();
    }
    query.apply(file);
    file.saveToFile(fileName);
}

static if (isFreedesktop)
{
    /**
     * Change MIME Applications Associations for the current user by applying the provided query.
     *
     * For compatibility purposes it overwrites user overrides in the deprecated location too.
     *
     * $(BLUE This function is Freedesktop only).
     * Note: It will not overwrite desktop-specific overrides.
     * See_Also: $(D userMimeAppsListPaths), $(D userAppDataMimeAppsListPaths)
     */
    @safe void updateAssociations(ref scope const AssociationUpdateQuery query)
    {
        foreach(fileName; userMimeAppsListPaths(string[].init) ~ userAppDataMimeAppsListPaths(string[].init)) {
            updateAssociations(fileName, query);
        }
    }
}
