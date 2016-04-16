import std.stdio;
import std.algorithm;
import std.file;
import mimeapps;

void main()
{
    auto mimeListPaths = mimeAppsListPaths();
    auto mimeCachePaths = mimeInfoCachePaths();
    
    writeln("Using mimeapps.list files: ", mimeListPaths);
    writeln("Using mimeinfo.cache files: ", mimeCachePaths);
    
    foreach(path; mimeListPaths.filter!(p => p.exists)) {
        try {
            new MimeAppsListFile(path);
        } catch(IniLikeException e) {
            stderr.writefln("Error reading %s: at %s: %s", path, e.lineNumber, e.msg);
        } catch(Exception e) {
            stderr.writefln("Error reading %s: %s", path, e.msg);
        }
    }
    
    foreach(path; mimeCachePaths.filter!(p => p.exists)) {
        try {
            new MimeInfoCacheFile(path);
        } catch(IniLikeException e) {
            stderr.writefln("Error reading %s: at %s: %s", path, e.lineNumber, e.msg);
        } catch(Exception e) {
            stderr.writefln("Error reading %s: %s", path, e.msg);
        }
    }
}
