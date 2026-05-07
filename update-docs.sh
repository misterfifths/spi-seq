#!/usr/bin/env bash

set -euo pipefail

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo 'working directory has changes! stash them first.'
    exit 1
fi

yard doc

tar cf docs.tar docs

git checkout gh-pages

tar xf docs.tar
rm docs.tar

git add docs
git commit -m 'Update documentation'
git checkout master

echo 'done! now push the gh-pages branch.'
