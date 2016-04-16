# Mimeapps

D library for finding associations between MIME types and applications, e.g. for deciding which application should be used to open a file.

[![Build Status](https://travis-ci.org/MyLittleRobo/mimeapps.svg?branch=master)](https://travis-ci.org/MyLittleRobo/mimeapps) [![Coverage Status](https://coveralls.io/repos/github/MyLittleRobo/mimeapps/badge.svg?branch=master)](https://coveralls.io/github/MyLittleRobo/mimeapps?branch=master)

Specification: [MIME Applications Associations](https://www.freedesktop.org/wiki/Specifications/mime-apps-spec/)

Note: detection of file MIME type is out of the scope of **mimeapps**. You may consider using [this library](https://github.com/MyLittleRobo/mime) for this purpose.

## Features

### Implemented

* Reading mimeapps.list and mimeinfo.cache files.
* Detecting default application for MIME type.
* Getting all associated applications for MIME type.

### Missing

* Adding, removing association or setting default application for MIME type.

### Missing

## Generating documentation

Ddoc:

    dub build --build=docs
    
Ddox:

    dub build --build=ddox
    
## Running tests

    dub test

## Examples

### [Mimeapps list](examples/list/source/app.d)

List default application and other associated applications for MIME type(s):

    dub run :list -- text/plain image/png text/html

Also can be used for uri schemes:

    dub run :list -- x-scheme-handler/http

### [Mimeapps test](examples/test/source/app.d)

Parse all mimeapps.list and mimeinfo.cache found on the system. Reports errors to stderr.
Use this example to check if the mimeapps library can parse all related files on your system.

    dub run :test
    
### [Mimeapps open](examples/test/source/app.d)

Detect MIME type of file and open it with default application for found type.

    dub run :open -- LICENSE_1_0.txt

Add option --ask to list all associated applications before opening the file.

    dub run :open -- --ask LICENSE_1_0.txt

