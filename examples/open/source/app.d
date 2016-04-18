import std.stdio;
import std.getopt;
import std.string : stripRight, startsWith;

import std.conv : to;
import std.typecons : rebindable, Rebindable;

import desktopfile.paths;
import mimeapps;
import mime.database;
import mime.paths;
import mime.type;

void main(string[] args)
{
    bool ask;
    getopt(args, "ask", "Ask before starting open file in an application", &ask);
    auto files = args[1..$];
    
    auto mimeDatabase = new MimeDatabase(mimePaths());
    alias MimeDatabase.Match M;
    auto match = M.globPatterns|M.magicRules|M.inodeType|M.textFallback|M.octetStreamFallback|M.emptyFileFallback;
    
    auto provider = new DesktopFileProvider(applicationsPaths());
    auto mimeAppsLists = mimeAppsListFiles();
    auto mimeInfoCaches = mimeInfoCacheFiles();
    
    foreach(filePath; files) {
        Rebindable!(const(MimeType)) mimeType;
        string mimeTypeName;
        if (filePath.startsWith("http://")) {
            mimeTypeName = "x-scheme-handler/http";
        } else if (filePath.startsWith("https://")) {
            mimeTypeName = "x-scheme-handler/https";
        } else {
            mimeType = mimeDatabase.mimeTypeForFile(filePath, match);
            if (mimeType) {
                mimeTypeName = mimeType.name;
            }
        }
        
        if (mimeTypeName.empty) {
            stderr.writefln("Could not detect MIME type for %s", filePath);
            continue;
        }
        
        auto defaultApp = findDefaultApplication(mimeTypeName, mimeAppsLists, mimeInfoCaches, provider).rebindable;
        if (!defaultApp && mimeType !is null && mimeType.parents().length) {
            writefln("Could not find default application for MIME type %s, but it has parent types. Will try them.", mimeTypeName);
            foreach(parent; mimeType.parents()) {
                defaultApp = findDefaultApplication(parent, mimeAppsLists, mimeInfoCaches, provider).rebindable;
                if (defaultApp) {
                    mimeTypeName = parent;
                    writefln("Found default application for parent type %s", parent);
                }
            }
        }
        
        if (defaultApp) {
            if (ask) {
                auto associatedApps = findAssociatedApplications(mimeTypeName, mimeAppsLists, mimeInfoCaches, provider);
                
                writefln("Choose application to open '%s' of type %s", filePath, mimeTypeName);
                writefln("\t0: %s (%s) - default", defaultApp.displayName, defaultApp.fileName);
                foreach(i, app; associatedApps) {
                    writefln("\t%s: %s (%s)", i+1, associatedApps[i].displayName, associatedApps[i].fileName);
                }
                
                bool ok;
                do {
                    string input = readln().stripRight;
                    if (input.length) {
                        try {
                            auto index = input.to!size_t;
                            if (index > associatedApps.length) {
                                throw new Exception("wrong number");
                            }
                            ok = true;
                            if (index == 0) {
                                defaultApp.startApplication(filePath);
                            } else {
                                associatedApps[index-1].startApplication(filePath);
                            }
                        } catch(Exception e) {
                            writefln("Please type a number from 0 to %s (%s)", associatedApps.length, e.msg);
                        }
                    }
                } while(!ok);
                
            } else {
                defaultApp.startApplication(filePath);
            }
        } else {
            stderr.writefln("Could not find default application for MIME type %s detected from file %s", mimeTypeName, filePath);
        }
    }
}
