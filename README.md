# Mimeapps

D library for finding associations between MIME types and applications, e.g. for deciding which application should be used to open a file.

[![Build Status](https://travis-ci.org/MyLittleRobo/mimeapps.svg?branch=master)](https://travis-ci.org/MyLittleRobo/mimeapps) [![Coverage Status](https://coveralls.io/repos/github/MyLittleRobo/mimeapps/badge.svg?branch=master)](https://coveralls.io/github/MyLittleRobo/mimeapps?branch=master)

See [MIME Applications Associations](https://www.freedesktop.org/wiki/Specifications/mime-apps-spec/).

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

    dub run :list -- text/plain image/png text/html x-scheme-handler/http

Also can be used for uri schemes:

    dub run :list -- x-scheme-handler/http

### [Mimeapps test](examples/test/source/app.d)

Parse all mimeapps.list and mimeinfo.cache found on the system. Reports errors to stderr.
Use this example to check if the mimeapps library can parse all related files on your system.

    dub run :test
    