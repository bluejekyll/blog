#!/bin/bash

set -e

cd $1

pushd bulma/sass

for i in $(find . -type f -name '*.sass') ; do
  dir_name=$(dirname $i)
  file_name=$(basename $i)
  new_name=${dir_name}/_${file_name}
  echo "renaming $i to ${new_name}"

  sed 's|\(@import "\)\(.*\)\("\)|\1_\2\3|' $i > $new_name
  rm $i
done

popd

pushd bulma

sed 's|\(_.*\)|_\1|' bulma.sass > _bulma.sass
rm bulma.sass

popd