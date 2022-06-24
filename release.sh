#!/bin/bash

# IMPORTANT: the following assumptions are made
# * the GH repo is on the origin remote
# * the gh-pages branch is named so locally
# * the git config user.signingkey is properly set

# You will need
# pip install coverage nose rsa wheel

# TODO
# release notes
# make hash on local files

set -e

skip_tests=true
gpg_sign_commits=""
buildserver='localhost:8142'

while true
do
case "$1" in
    --run-tests)
        skip_tests=false
        shift
    ;;
    --gpg-sign-commits|-S)
        gpg_sign_commits="-S"
        shift
    ;;
    --buildserver)
        buildserver="$2"
        shift 2
    ;;
    --*)
        echo "ERROR: unknown option $1"
        return 1
    ;;
    *)
        break
    ;;
esac
done

version="$(curl https://api.github.com/repos/p3g4asus/yt-dlp/releases/latest -s | jq .tag_name -r)"
major_version=$(echo "$version" | sed -n 's#^\([0-9]*\.[0-9]*\.[0-9]*\).*#\1#p')
#if test "$major_version" '!=' "$(date '+%Y.%m.%d')"; then
#    echo "$version does not start with today's date!"
#    return 1
#fi

if test -z "$major_version"; then
    echo "major_version is empty!"
    return 1
fi

if [ ! -z "`git tag | grep "$version"`" ]; then echo 'version already present'; return 0; fi

cd yt-dlp
git checkout $version
if [ ! -z "`git status --porcelain | grep -v CHANGELOG`" ]; then echo 'ERROR: the working directory is not clean; commit or stash changes'; return 1; fi
useless_files=$(find yt_dlp -type f -not -name '*.py')
if [ ! -z "$useless_files" ]; then echo "ERROR: Non-.py files in yt_dlp: $useless_files"; return 1; fi
if ! type pandoc >/dev/null 2>/dev/null; then echo 'ERROR: pandoc is missing'; return 1; fi
if ! python3 -c 'import rsa' 2>/dev/null; then echo 'ERROR: python3-rsa is missing'; return 1; fi
if ! python3 -c 'import wheel' 2>/dev/null; then echo 'ERROR: wheel is missing'; return 1; fi

cd ..
git add -A
git diff-index --quiet HEAD || git commit $gpg_sign_commits -m "release $version"
MASTER=$(git rev-parse --abbrev-ref HEAD)
git push origin $MASTER:master

/bin/echo -e "\n### patching in files for youtubedl-android support"
patch -p1 < patches/ffmpeg.py.patch
patch -p1 < patches/embedthumbnail.py.patch

cd yt-dlp
/bin/echo -e "\n### First of all, testing..."
make clean
if $skip_tests ; then
    echo 'SKIPPING TESTS'
else
    nosetests --verbose --with-coverage --cover-package=yt_dlp --cover-html test --stop || return 1
fi

/bin/echo -e "\n### OK, now it is time to build the binaries..."
REV=$(git rev-parse HEAD)
make lazy-extractors
make yt-dlp yt-dlp.tar.gz
mkdir -p "build/$version"
sed '1d' yt-dlp > yt_dlp.zip
mv yt-dlp "build/$version"
mv yt_dlp.zip "build/$version"
mv yt-dlp.tar.gz "build/$version/yt-dlp-$version.tar.gz"
RELEASE_FILES="yt-dlp yt-dlp-$version.tar.gz"
PP=$(pwd)
echo "BV=build/$version/ RF=$RELEASE_FILES PP=$PP"
cd build/$version/
md5sum yt-dlp yt-dlp-$version.tar.gz > MD5SUMS
sha1sum yt-dlp yt-dlp-$version.tar.gz > SHA1SUMS
sha256sum yt-dlp yt-dlp-$version.tar.gz > SHA2-256SUMS
sha512sum yt-dlp yt-dlp-$version.tar.gz > SHA2-512SUMS
cd ../..

ROOT=$(pwd)
python3 ../create-github-release.py Changelog.md $version "$ROOT/build/$version"

rm -rf build

make clean

/bin/echo -e "\n### DONE!"
