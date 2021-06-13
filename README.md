# Mimeapps

D library for finding associations between MIME types and applications, e.g. for deciding which application should be used to open a file.

[![Build Status](https://github.com/FreeSlave/mimeapps/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/FreeSlave/mimeapps/actions/workflows/ci.yml) [![Coverage Status](https://coveralls.io/repos/github/FreeSlave/mimeapps/badge.svg?branch=master)](https://coveralls.io/github/FreeSlave/mimeapps?branch=master)

[Online documentation](https://freeslave.github.io/d-freedesktop/docs/mimeapps.html)

Modern desktop environments on GNU/Linux and BSD flavors implement [MIME Applications Associations](https://www.freedesktop.org/wiki/Specifications/mime-apps-spec/)
to control file associations. The goal of **mimeapps** library is to provide implementation of this specification in D programming language.
Please feel free to propose enchancements or report any related bugs to *Issues* page.

Note: detection of file MIME type is out of the scope of **mimeapps**. You may consider using [mime library](https://github.com/FreeSlave/mime) for this purpose.

## Features

### Implemented

* Reading mimeapps.list and mimeinfo.cache files.
* Detecting default application for MIME type.
* Getting associated applications for MIME type with respect to explicitly removed ones.
* Adding, removing association or setting default application for MIME type.
* Support for desktop-specific mimeapps.list files.

## Examples

### [Mimeapps list](examples/list.d)

List default application and other associated applications for MIME type(s):

    dub examples/list.d text/plain image/png text/html

Also can be used for uri schemes:

    dub examples/list.d x-scheme-handler/http

### [Mimeapps test](examples/test.d)

Parse all mimeapps.list and mimeinfo.cache found on the system. Reports errors to stderr.
Use this example to check if the mimeapps library can parse all related files on your system.

    dub examples/test.d

### [Mimeapps open](examples/open.d)

Detect MIME type of file and open it with default application for found type.

    dub examples/open.d LICENSE_1_0.txt

Add option --ask to list all associated applications before opening the file.

    dub examples/open.d --ask LICENSE_1_0.txt

Pass http url to open in web browser:

    dub examples/open.d --ask https://github.com/FreeSlave/mimeapps

### [Mimeapps update](examples/update.d)

Update mimeapps.list file. If you want to update file associations on your system using this example use *--force* flag, but I would recommend to make a copy first.

    cp $HOME/.config/mimeapps.list /tmp/mimeapps.list
    dub examples/update.d --file=/tmp/mimeapps.list --remove=text/plain:kde4-kwrite.desktop --add=image/jpeg:gthumb.desktop --default=application/pdf:kde4-okular.desktop
