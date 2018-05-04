/+dub.sdl:
name "list"
dependency "mimeapps" path="../"
+/

import std.stdio;
import std.algorithm : map;

import desktopfile.paths;
import mimeapps;

void main(string[] args)
{   
    auto mimeTypes = args[1..$];
    
    auto appPaths = applicationsPaths();
    auto provider = new DesktopFileProvider(appPaths);
    auto mimeAppsLists = mimeAppsListFiles();
    auto mimeInfoCaches = mimeInfoCacheFiles();
    
    writeln("Using application paths: ", appPaths);
    writeln("Using mimeapps.list files: ", mimeAppsLists.map!(mimeAppsList => mimeAppsList.fileName));
    writeln("Using mimeinfo.cache files: ", mimeInfoCaches.map!(mimeInfoCache => mimeInfoCache.fileName));
    
    foreach(mimeType; mimeTypes) {
        auto associatedApps = findAssociatedApplications(mimeType, mimeAppsLists, mimeInfoCaches, provider);
        auto defaultApp = findDefaultApplication(mimeType, mimeAppsLists, mimeInfoCaches, provider);
        writefln("Default application for %s: ", mimeType);
        if (defaultApp is null) {
            writeln("\tCould not find default application");
        } else {
            writefln("\t%s", defaultApp.fileName);
        }
        writefln("Applications associated with %s: ", mimeType);
        if(associatedApps.length) {
            foreach(desktopFile; associatedApps) {
                writefln("\t%s", desktopFile.fileName);
            }
        } else {
            writeln("\tCould not find any application");
        }
        writeln();
    }
}
