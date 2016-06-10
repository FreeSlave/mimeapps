/**
 * Finding associations between MIME types and applications.
 * Authors: 
 *  $(LINK2 https://github.com/MyLittleRobo, Roman Chistokhodov)
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

private @nogc @trusted bool allSymbolsAreValid(const(char)[] name) nothrow pure
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

private @nogc @safe bool isValidMimeTypeName(const(char)[] name) nothrow pure
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
            this(string env) {
                envVar = env;
                envValue = environment.get(env);
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
    
    /**
     * Find all known mimeapps.list files locations. Found paths are not checked for existence.
     * Returns: Paths of mimeapps.list files in the system.
     * Note: This function is available only on Freedesktop.
     * See_Also: $(LINK2 https://specifications.freedesktop.org/mime-apps-spec/latest/ar01s02.html, File name and location)
     */
    @safe string[] mimeAppsListPaths() nothrow
    {
        enum mimeAppsList = "mimeapps.list";
        enum applicationsMimeAppsList = "applications/mimeapps.list";
        string configHome = xdgConfigHome(mimeAppsList);
        string appHome = xdgDataHome(applicationsMimeAppsList);
        
        string[] configPaths = xdgConfigDirs(mimeAppsList);
        string[] appPaths = xdgDataDirs(applicationsMimeAppsList);
        
        string[] toReturn;
        if (configHome.length) {
            toReturn ~= configHome;
        }
        if (appHome.length) {
            toReturn ~= appHome;
        }
        return toReturn ~ configPaths ~ appPaths;
    }
    
    ///
    unittest
    {
        auto dataHomeGuard = EnvGuard("XDG_DATA_HOME");
        auto dataDirsGuard = EnvGuard("XDG_DATA_DIRS");
        
        auto configHomeGuard = EnvGuard("XDG_CONFIG_HOME");
        auto configDirsGuard = EnvGuard("XDG_CONFIG_DIRS");
        
        environment["XDG_DATA_HOME"] = "/home/user/data";
        environment["XDG_DATA_DIRS"] = "/usr/local/data:/usr/data";
        
        environment["XDG_CONFIG_HOME"] = "/home/user/config";
        environment["XDG_CONFIG_DIRS"] = "/etc/xdg";
        
        assert(mimeAppsListPaths() == [
            "/home/user/config/mimeapps.list", "/home/user/data/applications/mimeapps.list", "/etc/xdg/mimeapps.list",
            "/usr/local/data/applications/mimeapps.list", "/usr/data/applications/mimeapps.list"
        ]);
    }
    
    /**
     * Find all known mimeinfo.cache files locations. Found paths are not checked for existence.
     * Returns: Paths of mimeinfo.cache files in the system.
     * Note: This function is available only on Freedesktop.
     */
    @safe string[] mimeInfoCachePaths() nothrow
    {
        return xdgAllDataDirs("applications/mimeinfo.cache");
    }
    
    ///
    unittest
    {
        auto dataHomeGuard = EnvGuard("XDG_DATA_HOME");
        auto dataDirsGuard = EnvGuard("XDG_DATA_DIRS");
        
        environment["XDG_DATA_HOME"] = "/home/user/data";
        environment["XDG_DATA_DIRS"] = "/usr/local/data:/usr/data";
        
        assert(mimeInfoCachePaths() == [
            "/home/user/data/applications/mimeinfo.cache", 
            "/usr/local/data/applications/mimeinfo.cache", "/usr/data/applications/mimeinfo.cache"
        ]);
    }
}

/**
 * IniLikeGroup subclass for easy access to the list of applications associated with given type.
 */
final class MimeAppsGroup : IniLikeGroup
{
    protected @nogc @safe this(string groupName) nothrow {
        super(groupName);
    }
    
    /**
     * Split string list of desktop ids into range.
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
     * List applications for given mimeType.
     * Returns: Range of $(B Desktop id)s for mimeType.
     */
    @safe auto appsForMimeType(string mimeType) const {
        return splitApps(value(mimeType));
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
     *  $(B IniLikeReadException) if error occured while reading the file or "MIME Cache" group is missing.
     */
    @trusted this(string fileName, ReadOptions readOptions = ReadOptions.init) 
    {
        this(iniLikeFileReader(fileName), fileName, readOptions);
    }
    
    /**
     * Read MIME type associations from IniLikeReader, e.g. acquired from iniLikeFileReader or iniLikeStringReader.
     * Throws:
     *  $(B IniLikeReadException) if error occured while parsing or "MIME Cache" group is missing.
     */
    this(IniLikeReader)(IniLikeReader reader, string fileName = null, ReadOptions readOptions = ReadOptions.init)
    {
        super(reader, fileName);
        _defaultApps = cast(MimeAppsGroup)group("Default Applications");
        _addedApps = cast(MimeAppsGroup)group("Added Associations");
        _removedApps = cast(MimeAppsGroup)group("Removed Associations");
    }
    
    /**
     * Access "Desktop Applications" group.
     * Returns: MimeAppsGroup for "Desktop Applications" group or null if file does not have such group.
     */
    @safe inout(MimeAppsGroup) defaultApplications() nothrow inout {
        return _defaultApps;
    }
    
    /**
     * Access "Added Associations" group.
     * Returns: MimeAppsGroup for "Added Associations" group or null if file does not have such group.
     */
    @safe inout(MimeAppsGroup) addedAssociations() nothrow inout {
        return _addedApps;
    }
    
    /**
     * Access "Removed Associations" group.
     * Returns: MimeAppsGroup for "Removed Associations" group or null if file does not have such group.
     */
    @safe inout(MimeAppsGroup) removedAssociations() nothrow inout {
        return _removedApps;
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
`;
    auto mimeAppsList = new MimeAppsListFile(iniLikeStringReader(content));
    assert(mimeAppsList.addedAssociations() !is null);
    assert(mimeAppsList.removedAssociations() !is null);
    assert(mimeAppsList.defaultApplications() !is null);
    
    assert(mimeAppsList.addedAssociations().appsForMimeType("text/plain").equal(["geany.desktop", "kde4-kwrite.desktop"]));
    assert(mimeAppsList.removedAssociations().appsForMimeType("text/plain").equal(["libreoffice-writer.desktop"]));
    assert(mimeAppsList.defaultApplications().appsForMimeType("x-scheme-handler/http").equal(["chromium.desktop", "iceweasel.desktop"]));
}

/**
 * Class represenation of single mimeinfo.cache file containing information about MIME type associations.
 */
final class MimeInfoCacheFile : IniLikeFile
{    
    /**
     * Read MIME Cache from file.
     * Throws:
     *  $(B ErrnoException) if file could not be opened.
     *  $(B IniLikeReadException) if error occured while reading the file or "MIME Cache" group is missing.
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
     * Read MIME Cache from IniLikeReader, e.g. acquired from iniLikeFileReader or iniLikeStringReader.
     * Throws:
     *  $(B IniLikeException) if error occured while parsing or "MIME Cache" group is missing.
     */
    this(IniLikeReader)(IniLikeReader reader, string fileName = null, ReadOptions readOptions = ReadOptions.init)
    {
        super(reader, fileName);
        _mimeCache = cast(MimeAppsGroup)group("MIME Cache");
        enforce(_mimeCache !is null, new IniLikeReadException("No \"MIME Cache\" group", 0));
    }
    
    /**
     * Access "MIME Cache" group.
     */
    @safe inout(MimeAppsGroup) mimeCache() nothrow inout {
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
}

/**
 * Create MimeAppsListFile objects for paths.
 * Returns: Array of MimeAppsListFile objects read from paths. If some could not be read it's not included in the results.
 */
@trusted MimeAppsListFile[] mimeAppsListFiles(const(string)[] paths) nothrow
{
    return paths.map!(function(string path) {
        MimeAppsListFile file;
        collectException(new MimeAppsListFile(path), file);
        return file;
    }).filter!(file => file !is null).array;
}

static if (isFreedesktop)
{
    /**
     * ditto, but automatically read MimeAppsListFile objects from determined system paths.
     * Note: Available only on Freedesktop.
     */
    @safe MimeAppsListFile[] mimeAppsListFiles() nothrow {
        return mimeAppsListFiles(mimeAppsListPaths());
    }
}

/**
 * Create MimeInfoCacheFile objects for paths.
 * Returns: Array of MimeInfoCacheFile objects read from paths. If some could not be read it's not included in the results.
 */
@trusted MimeInfoCacheFile[] mimeInfoCacheFiles(const(string)[] paths) nothrow
{
    return paths.map!(function(string path) {
        MimeInfoCacheFile file;
        collectException(new MimeInfoCacheFile(path), file);
        return file;
    }).filter!(file => file !is null).array;
}

static if (isFreedesktop)
{
    /**
     * ditto, but automatically read MimeInfoCacheFile objects from determined system paths.
     * Note: Available only on Freedesktop.
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
     * Retrieve DesktopFile by desktopId
     * Returns: Found DesktopFile or null if not found.
     */
    const(DesktopFile) getByDesktopId(string desktopId);
}

/**
 * Implementation of desktop file provider.
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
     * Construct using applicationsPaths.
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
    
    /// ditto, but determine binPaths from PATH environment variable automatically.
    @trusted this(const(string)[] applicationsPaths, DesktopFile.DesktopReadOptions options = DesktopFile.DesktopReadOptions.init) {
        this(applicationsPaths, binPaths().array, options);
    }
    
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
                    string executable = findExecutable(tryExec, binPaths);
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

private const(DesktopFile)[] findAssociatedApplicationsImpl(ListRange, CacheRange)(string mimeType, ListRange mimeAppsListFiles, CacheRange mimeInfoCacheFiles, IDesktopFileProvider desktopFileProvider, FindAssocFlag flag = FindAssocFlag.none)
{
    string[] removed;
    const(DesktopFile)[] desktopFiles;
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
                if (removed.canFind(desktopId)) {
                    continue;
                }
                auto desktopFile = desktopFileProvider.getByDesktopId(desktopId);
                if (desktopFile) {
                    if (flag & FindAssocFlag.onlyFirst) {
                        return [desktopFile];
                    }
                    desktopFiles ~= desktopFile;
                }
                removed ~= desktopId;
            }
        }
    }
    
    foreach(mimeInfoCacheFile; mimeInfoCacheFiles) {
        if (mimeInfoCacheFile is null) {
            continue;
        }
        
        foreach(desktopId; mimeInfoCacheFile.appsForMimeType(mimeType)) {
            if (removed.canFind(desktopId)) {
                continue;
            }
            auto desktopFile = desktopFileProvider.getByDesktopId(desktopId);
            if (desktopFile) {
                if (flag & FindAssocFlag.onlyFirst) {
                    return [desktopFile];
                }
                desktopFiles ~= desktopFile;
            }
            removed ~= desktopId;
        }
    }
    
    return desktopFiles;
}

/**
 * Find associated applications for mimeType.
 * Params:
 *  mimeType = MIME type or uri scheme handler in question.
 *  mimeAppsListFiles = Range of MimeAppsListFile objects to use in searching.
 *  mimeInfoCacheFiles = Range of MimeInfoCacheFile objects to use in searching.
 *  desktopFileProvider = desktop file provider instance.
 * Returns: Array of found $(B DesktopFile) object capable of opening file of given MIME type or url of given scheme.
 * Note: If no applications found for this mimeType, you may consider to use this function on parent MIME type.
 * See_Also: $(LINK2 https://specifications.freedesktop.org/mime-apps-spec/latest/ar01s03.html, Adding/removing associations)
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
unittest
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
 * Find all known associated applications for mimeType, including explicitly removed by user.
 * Params:
 *  mimeType = MIME type or uri scheme handler in question.
 *  mimeAppsListFiles = Range of MimeAppsListFile objects to use in searching.
 *  mimeInfoCacheFiles = Range of MimeInfoCacheFile objects to use in searching.
 *  desktopFileProvider = desktop file provider instance.
 * Returns: Array of found $(B DesktopFile) object capable of opening file of given MIME type or url of given scheme.
 */
const(DesktopFile)[] findKnownAssociatedApplications(ListRange, CacheRange)(string mimeType, ListRange mimeAppsListFiles, CacheRange mimeInfoCacheFiles, IDesktopFileProvider desktopFileProvider)
in {
    assert(desktopFileProvider !is null);
}
body {
    return findAssociatedApplicationsImpl(mimeType, mimeAppsListFiles, mimeInfoCacheFiles, desktopFileProvider, FindAssocFlag.ignoreRemovedGroup);
}

///
unittest
{
    auto desktopProvider = new DesktopFileProvider(["test/applications"]);
    auto mimeAppsList = new MimeAppsListFile("test/applications/mimeapps.list");
    auto mimeInfoCache = new MimeInfoCacheFile("test/applications/mimeinfo.cache");
    assert(findKnownAssociatedApplications("text/plain", [null, mimeAppsList], [null, mimeInfoCache], desktopProvider)
        .map!(d => d.displayName()).equal(["Geany", "Kate", "Emacs", "Okular"]));
}

/**
 * Find default application for mimeType.
 * Params:
 *  mimeType = MIME type or uri scheme handler in question.
 *  mimeAppsListFiles = Range of MimeAppsListFile objects to use in searching.
 *  mimeInfoCacheFiles = Range of MimeInfoCacheFile objects to use in searching.
 *  desktopFileProvider = desktop file provider instance. Must be non-null.
 * Returns: Found $(B DesktopFile) or null if not found.
 * Note: You probably will need to call this function on parent MIME type if it fails for original mimeType.
 * See_Also: $(LINK2 https://specifications.freedesktop.org/mime-apps-spec/latest/ar01s04.html, Default Application)
 */
const(DesktopFile) findDefaultApplication(ListRange, CacheRange)(string mimeType, ListRange mimeAppsListFiles, CacheRange mimeInfoCacheFiles, IDesktopFileProvider desktopFileProvider)
if(isForwardRange!ListRange && is(ElementType!ListRange : const(MimeAppsListFile)) 
    && isForwardRange!CacheRange && is(ElementType!CacheRange : const(MimeInfoCacheFile)))
in {
    assert(desktopFileProvider !is null);
}
body {
    foreach(mimeAppsListFile; mimeAppsListFiles) {
        if (mimeAppsListFile is null) {
            continue;
        }
        auto defaultAppsGroup = mimeAppsListFile.defaultApplications();
        if (defaultAppsGroup !is null) {
            foreach(desktopId; defaultAppsGroup.appsForMimeType(mimeType)) {
                auto desktopFile = desktopFileProvider.getByDesktopId(desktopId);
                if (desktopFile !is null) {
                    return desktopFile;
                }
            }
        }
    }
    
    auto desktopFiles = findAssociatedApplicationsImpl(mimeType, mimeAppsListFiles, mimeInfoCacheFiles, desktopFileProvider, FindAssocFlag.onlyFirst);
    return desktopFiles.length ? desktopFiles.front : null;
}

///
unittest
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
