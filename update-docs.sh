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

if [ -z "$(git status --porcelain --untracked-files=no)" ]; then
    echo 'no updates!'
else
    git add docs
    git commit -m 'Update documentation'
    echo 'committed! now push the gh-pages branch.'
fi

git checkout master

# Since docs is ignored on master, switching will have blown away our
# copy. Restore it.
tar xf docs.tar
rm docs.tar
