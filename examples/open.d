/+dub.sdl:
name "open"
dependency "mimeapps" path="../"
dependency "mime" version="~>0.5.2"
+/

import std.stdio;
import std.getopt;
import std.string : stripRight, startsWith;

import std.conv : to;
import std.typecons : rebindable, Rebindable;

import std.regex;

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

    auto provider = new DesktopFileProvider(applicationsPaths());
    auto mimeAppsLists = mimeAppsListFiles();
    auto mimeInfoCaches = mimeInfoCacheFiles();

    auto urlRegex = regex(`([a-z]+)://.*`);

    foreach(filePath; files) {
        Rebindable!(const(MimeType)) mimeType;
        string mimeTypeName;
        auto matchResult = matchFirst(filePath, urlRegex);
        if (!matchResult.empty) {
            mimeTypeName = "x-scheme-handler/" ~ matchResult[1];
        } else {
            mimeType = mimeDatabase.mimeTypeForFile(filePath);
            if (mimeType) {
                mimeTypeName = mimeType.name;
            }
        }
        if (mimeTypeName.empty) {
            stderr.writefln("Could not detect MIME type for %s", filePath);
            continue;
        }

        auto findDefaultApplicationForParents(const(MimeType) mimeType)
        {
            foreach(parent; mimeType.parents()) {
                writefln("Trying to find default application for %s...", parent);
                auto defaultApp = findDefaultApplication(parent, mimeAppsLists, mimeInfoCaches, provider).rebindable;
                if (defaultApp) {
                    mimeTypeName = parent;
                    writefln("Found default application for parent type %s", parent);
                    return defaultApp;
                }
            }
            foreach(parent; mimeType.parents()) {
                auto parentMimeType = mimeDatabase.mimeType(parent);
                if (parentMimeType !is null && parentMimeType.parents().length) {
                    auto defaultApp = findDefaultApplicationForParents(parentMimeType);
                    if (defaultApp)
                        return defaultApp;
                }
            }
            return Rebindable!(const(DesktopFile)).init;
        }

        auto defaultApp = findDefaultApplication(mimeTypeName, mimeAppsLists, mimeInfoCaches, provider).rebindable;
        if (!defaultApp && mimeType !is null && mimeType.parents().length) {
            writefln("Could not find default application for MIME type %s, but it has parent types. Will try them.", mimeTypeName);
            defaultApp = findDefaultApplicationForParents(mimeType);
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
