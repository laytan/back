#!/usr/bin/env bash

set -ex

cd docs

rm -rf build
mkdir build

odin doc .. -all-packages -doc-format

cd build

# This is the binary of https://github.com/odin-lang/pkg.odin-lang.org, built by `odin build . -out:odin-doc`
odin-doc ../back.odin-doc ../odin-doc.json

# For GitHub pages, a CNAME file with the intended domain is required.
echo "back.laytan.dev" > CNAME

cd ..

rm back.odin-doc

cd ..
