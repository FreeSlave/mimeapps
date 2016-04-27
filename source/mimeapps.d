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

private @trusted void validateMimeType(string mimeType) {
    if (!isValidMimeTypeName(mimeType)) {
        throw new Exception("Invalid MIME type name");
    }
}

static if (isFreedesktop)
{
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
    
    /**
     * Find all known mimeinfo.cache files locations. Found paths are not checked for existence.
     * Returns: Paths of mimeinfo.cache files in the system.
     * Note: This function is available only on Freedesktop.
     */
    @safe string[] mimeInfoCachePaths() nothrow
    {
        return xdgAllDataDirs("applications/mimeinfo.cache");
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
    @trusted override void validateKeyValue(string key, string value) const {
        validateMimeType(key);
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
     *  $(B IniLikeException) if error occured while reading the file or "MIME Cache" group is missing.
     */
    @trusted this(string fileName) 
    {
        this(iniLikeFileReader(fileName), fileName);
    }
    
    /**
     * Read MIME type associations from IniLikeReader, e.g. acquired from iniLikeFileReader or iniLikeStringReader.
     * Throws:
     *  $(B IniLikeException) if error occured while parsing or "MIME Cache" group is missing.
     */
    this(IniLikeReader)(IniLikeReader reader, string fileName = null)
    {
        super(reader, fileName);
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
    @trusted override void addCommentForGroup(string comment, IniLikeGroup currentGroup, string groupName) {
        return;
    }
    
    @trusted override void addKeyValueForGroup(string key, string value, IniLikeGroup currentGroup, string groupName)
    {
        if (currentGroup) {
            if (currentGroup.contains(key)) {
                return;
            }
            currentGroup[key] = value;
        }
    }
    
    @trusted override IniLikeGroup createGroup(string groupName)
    {
        auto existent = group(groupName);
        if (existent !is null) {
            return existent;
        } else {
            if (groupName == "Default Applications") {
                _defaultApps = new MimeAppsGroup(groupName);
                return _defaultApps;
            } else if (groupName == "Added Associations") {
                _addedApps = new MimeAppsGroup(groupName);
                return _addedApps;
            } else if (groupName == "Removed Associations") {
                _removedApps = new MimeAppsGroup(groupName);
                return _removedApps;
            } else {
                return null;
            }
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
     *  $(B IniLikeException) if error occured while reading the file or "MIME Cache" group is missing.
     */
    @trusted this(string fileName) 
    {
        this(iniLikeFileReader(fileName), fileName);
    }
    
    /**
     * Constructs MimeInfoCacheFile with empty MIME Cache group.
     */
    @safe this() {
        super();
        addGroup("MIME Cache");
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
    this(IniLikeReader)(IniLikeReader reader, string fileName = null)
    {
        super(reader, fileName);
        enforce(_mimeCache !is null, new IniLikeException("No \"MIME Cache\" group", 0));
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
    @trusted override void addCommentForGroup(string comment, IniLikeGroup currentGroup, string groupName) {
        return;
    }
    
    @trusted override void addKeyValueForGroup(string key, string value, IniLikeGroup currentGroup, string groupName)
    {
        if (currentGroup) {
            if (currentGroup.contains(key)) {
                return;
            }
            currentGroup[key] = value;
        }
    }
    
    @trusted override IniLikeGroup createGroup(string groupName)
    {
        auto existent = group(groupName);
        if (existent !is null) {
            return existent;
        } else {
            if (groupName == "MIME Cache") {
                _mimeCache = new MimeAppsGroup(groupName);
                return _mimeCache;
            } else {
                return null;
            }
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
    assertThrown!IniLikeException(new MimeInfoCacheFile(iniLikeStringReader(content)));
    
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
    assertThrown!IniLikeException(new MimeInfoCacheFile(iniLikeStringReader(content)));
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
 * See_Also: findAssociatedApplications, findKnownAssociatedApplications, findDefaultApplication
 */
interface IDesktopFileProvider
{
    /**
     * Retrieve DesktopFile by desktopId
     * Returns: Found DesktopFile or null if not found.
     */
    const(DesktopFile) getByDesktopId(string desktopId);
    
    /**
     * Update internal information, e.g. re-read cached .desktop files if needed.
     */
    void update();
}

/**
 * Implementation of desktop file provider.
 */
class DesktopFileProvider : IDesktopFileProvider
{
private:
    import std.datetime : SysTime;
    
    static struct DesktopFileItem
    {
        DesktopFile desktopFile;
        SysTime time;
        string baseDir;
        SysTime baseDirTime;
    }
    
    static struct BaseDirItem
    {
        string path;
        SysTime time;
        bool valid;
    }
    
public:
    /**
     * Construct using applicationsPaths. Automatically calls update.
     * Params:
     *  applicationsPaths = Paths of applications/ directories where .desktop files are stored. These should be all known paths even if they don't exist at the time.
     *  binPaths = Paths where executable files are stored.
     *  options = Options used to read desktop files.
     */
    @trusted this(const(string)[] applicationsPaths, in string[] binPaths, DesktopFile.ReadOptions options = DesktopFile.defaultReadOptions) {
        _baseDirItems = applicationsPaths.map!(p => BaseDirItem(p, SysTime.init, false)).array;
        _readOptions = options;
        _binPaths = binPaths.dup;
        update();
    }
    
    /// ditto, but determine binPaths from PATH environment variable automatically.
    @trusted this(const(string)[] applicationsPaths, DesktopFile.ReadOptions options = DesktopFile.defaultReadOptions) {
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
    
    override void update()
    {
        foreach (ref item; _baseDirItems) {
            try {
                SysTime accessTime;
                getTimes(item.path, accessTime, item.time);
                item.valid = item.path.isDir();
            } catch(Exception e) {
                item.valid = false;
            }
        }
        
        foreach(desktopId, item; _cache) {
            SysTime modifyTime;
            BaseDirItem baseDirItem;
            string filePath = findDesktopFilePath(desktopId, modifyTime, baseDirItem);
            
            if (filePath.length) {
                if (item.time != modifyTime || item.baseDir != baseDirItem.path) {
                    try {
                        auto desktopFile = new DesktopFile(filePath, _readOptions);
                        _cache[desktopId] = DesktopFileItem(desktopFile, modifyTime, baseDirItem.path, baseDirItem.time);
                    } catch(Exception e) {
                        _cache.remove(desktopId);
                    }
                }
            } else {
                _cache.remove(desktopId);
            }
        }
    }
    
private:
    DesktopFileItem getDesktopFileItem(string desktopId)
    {
        SysTime modifyTime;
        BaseDirItem baseDirItem;
        string filePath = findDesktopFilePath(desktopId, modifyTime, baseDirItem);
        if (filePath.length) {
            try {
                auto desktopFile = new DesktopFile(filePath, _readOptions);
                string tryExec = desktopFile.tryExecString();
                if (tryExec.length) {
                    string executable = findExecutable(tryExec, binPaths);
                    if (!executable.empty) {
                        return DesktopFileItem.init;
                    }
                }
                
                return DesktopFileItem(desktopFile, modifyTime, baseDirItem.path, baseDirItem.time);
            } catch(Exception e) {
                return DesktopFileItem.init;
            }
        }
        return DesktopFileItem.init;
    }
    
    string findDesktopFilePath(string desktopId, out SysTime modifyTime, out BaseDirItem dirItem)
    {
        foreach(baseDirItem; _baseDirItems) {
            if (!baseDirItem.valid) {
                continue;
            }
            
            auto filePath = findDesktopFile(desktopId, only(baseDirItem.path));
            if (filePath.length) {
                try {
                    SysTime accessTime;
                    getTimes(filePath, accessTime, modifyTime);
                    dirItem = baseDirItem;
                    return filePath;
                } catch(Exception e) {
                    return null;
                }
            }
        }
        return null;
    }
    
    DesktopFileItem[string] _cache;
    BaseDirItem[] _baseDirItems;
    DesktopFile.ReadOptions _readOptions;
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
{
    return findAssociatedApplicationsImpl(mimeType, mimeAppsListFiles, mimeInfoCacheFiles, desktopFileProvider, FindAssocFlag.ignoreRemovedGroup);
}

/**
 * Find default application for mimeType.
 * Params:
 *  mimeType = MIME type or uri scheme handler in question.
 *  mimeAppsListFiles = Range of MimeAppsListFile objects to use in searching.
 *  mimeInfoCacheFiles = Range of MimeInfoCacheFile objects to use in searching.
 *  desktopFileProvider = desktop file provider instance. Must be non-null.
 * Returns: Found $(B DesktopFile) or null if not found.
 * Note: In real world you probably will need to call this function on parent MIME type if it fails for original mimeType.
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
