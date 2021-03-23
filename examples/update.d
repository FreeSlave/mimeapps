/+dub.sdl:
name "update"
dependency "mimeapps" path="../"
+/

import std.stdio;
import std.getopt;
import std.string;
import std.path;

import mimeapps;
import isfreedesktop;

int assocFormatError()
{
    stderr.writeln("Association must be given in form mimetype:desktopId");
    return 1;
}

int main(string[] args)
{
    string fileName;
    string[] toAdd;
    string[] toRemove;
    string[] toSetDefault;
    bool forced;
    getopt(args, "file", "Input file to update", &fileName,
        "add", "Add association", &toAdd,
        "remove", "Remove association", &toRemove,
        "default", "Set default application", &toSetDefault,
        "force", "Force changing current user override mimeapps.list", &forced
    );

    if (fileName.empty) {
        stderr.writeln("No input file given");
        return 1;
    }

    if (toAdd.empty && toRemove.empty && toSetDefault.empty) {
        stderr.writeln("No update operations given");
        return 1;
    }

    AssociationUpdateQuery query;

    foreach(str; toRemove) {
        auto splitted = str.findSplit(":");
        if (splitted[1].empty) {
            return assocFormatError();
        }
        query.removeAssociation(splitted[0], splitted[2]);
    }

    foreach(str; toAdd) {
        auto splitted = str.findSplit(":");
        if (splitted[1].empty) {
            return assocFormatError();
        }
        query.addAssociation(splitted[0], splitted[2]);
    }

    foreach(str; toSetDefault) {
        auto splitted = str.findSplit(":");
        if (splitted[1].empty) {
            return assocFormatError();
        }
        query.setDefaultApplication(splitted[0], splitted[2]);
    }

    static if (isFreedesktop) {
        auto mimeAppsLists = mimeAppsListPaths();
        if (mimeAppsLists.canFind(buildNormalizedPath(fileName)) && !forced) {
            stderr.writeln("Cowardly refusing to update a system file. Make a copy in other path.");
            return 1;
        }
    }

    updateAssociations(fileName, query);
    return 0;
}
