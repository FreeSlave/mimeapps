# Mimeapps

D library for finding associations between MIME types and applications, e.g. for deciding which application should be used to open a file.
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

