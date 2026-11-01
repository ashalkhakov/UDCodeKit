#!/usr/bin/env bash
# The SQL extension's client libraries, carried by UDCode's packages so that
# their users need not install them: libpq (PostgreSQL's, the PostgreSQL
# Licence) and MariaDB Connector/C's libmariadb (LGPL 2.1, a separate shared
# library, unmodified; it speaks to MySQL too), with what they link that a
# machine need not have (OpenSSL, and on macOS Kerberos' GSSAPI, which
# Homebrew's libpq links), MariaDB's authentication plug-ins (MySQL 8's
# caching_sha2_password among them) in mariadb/plugin beside them, and each
# one's licence in the app's Licenses folder. The extension looks for them
# there first (UDSQLLibrary's ownDirectory), then for the system's.
#
#   scripts/sql-clients.sh macos <UDCode.app>   Homebrew's, into Contents/
#       Frameworks, their references rewritten to each other (@loader_path)
#       and signed again (ad hoc, or SIGN_IDENTITY), the app too
#       (Makefile.apple's install)
#   scripts/sql-clients.sh appimage <AppDir>    the system's (Ubuntu's libpq5,
#       libmariadb3), into usr/lib: linuxdeploy brings what they link
#       (appimage.conf's PREPARE)
#   scripts/sql-clients.sh windows <stage>      MSYS2's, beside UDCode.exe in
#       <stage>/app/UDCode.app, with every DLL they link that MSYS2 provides
#       (windows.conf's PREPARE)
#
# Not found, it says so and carries nothing (a developer's machine without
# them); in CI (CI set) that is an error.
set -euo pipefail

mode=${1:?usage: sql-clients.sh macos|appimage|windows <dir>}
dir=${2:?usage: sql-clients.sh macos|appimage|windows <dir>}

missing() {
  if [ -n "${CI:-}" ]; then echo "::error::sql-clients: $*" >&2; exit 1; fi
  echo "sql-clients: $*; UDCode will use the system's client libraries" >&2
  exit 0
}

# The Licenses folder's README: what is carried, its version, its licence and
# where its source is (LGPL 2.1's requirement for libmariadb). Lines of
# "name|version|licence|source|files" on stdin.
readme() {
  {
    echo "The SQL extension's client libraries, and what they link, as UDCode carries"
    echo "them: each a shared library of its own, unmodified (on macOS but for the"
    echo "names they find each other by), its licence in this folder. UDCode loads"
    echo "them when a connection needs them; each can be replaced by another build of"
    echo "the same library, put in its place."
    echo
    while IFS='|' read -r name version licence source files; do
      echo "$name $version"
      echo "  licence: $licence (${name}.txt)"
      echo "  source:  $source"
      echo "  files:   $files"
      echo
    done
  } > "$1/README.txt"
}

macos() {
  local app=$1
  local frameworks=$app/Contents/Frameworks licenses=$app/Contents/Resources/Licenses
  command -v brew > /dev/null || missing "no Homebrew"
  local libpq mariadb
  libpq=$(brew --prefix libpq 2>/dev/null)/lib/libpq.5.dylib
  mariadb=$(brew --prefix mariadb-connector-c 2>/dev/null)/lib/libmariadb.3.dylib
  [ -f "$libpq" ] || missing "no libpq (brew install libpq)"
  [ -f "$mariadb" ] || missing "no MariaDB Connector/C (brew install mariadb-connector-c)"
  local plugins=$(dirname "$mariadb")/mariadb/plugin
  # MariaDB's authentication plug-ins; not its remote_io (libcurl) or zstd
  # (compression, which UDCode doesn't ask for).
  local roots=("$libpq" "$mariadb")
  for p in caching_sha2_password sha256_password client_ed25519 parsec dialog mysql_clear_password auth_gssapi_client; do
    [ -f "$plugins/$p.so" ] && roots+=("$plugins/$p.so")
  done

  mkdir -p "$frameworks/mariadb/plugin" "$licenses"
  # (macOS's bash is 3.2: no associative arrays, so what is known is kept in
  # files)
  local work; work=$(mktemp -d)
  mkdir -p "$work/seen" "$work/kegs"
  # Each file and what it links, but the system's, copied: a library into
  # Frameworks under the name it is referred to by, a plug-in into
  # mariadb/plugin; and each one's Homebrew formula (keg), for its licence.
  local queue=("${roots[@]}") file real base dest keg id dep
  while [ ${#queue[@]} -gt 0 ]; do
    file=${queue[0]}; queue=("${queue[@]:1}")
    base=$(basename "$file")
    [ ! -e "$work/seen/$base" ] || continue
    touch "$work/seen/$base"
    real=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$file")
    dest=$frameworks/$base
    case "$file" in *.so) dest=$frameworks/mariadb/plugin/$base ;; esac
    cp -f "$real" "$dest"; chmod u+w "$dest"
    echo "$dest" >> "$work/copied"
    keg=$(printf '%s\n' "$real" | sed -n 's|.*/Cellar/\([^/]*\)/\([^/]*\)/.*|\1 \2|p')
    [ -n "$keg" ] || { echo "sql-clients: $real is in no Homebrew keg" >&2; exit 1; }
    printf '%s ' "$base" >> "$work/kegs/${keg% *}"
    echo "$keg" >> "$work/kegs.list"
    id=$(otool -D "$real" | sed -n 2p)
    for dep in $(otool -L "$real" | tail -n +2 | awk '{print $1}'); do
      [ "$dep" != "$id" ] || continue
      case "$dep" in
        /usr/lib/*|/System/*) ;;
        /*) queue+=("$dep") ;;
        @loader_path/*) queue+=("$(dirname "$real")/${dep#@loader_path/}") ;;
        *) echo "sql-clients: $real links $dep, which this script doesn't follow" >&2; exit 1 ;;
      esac
    done
  done

  # References rewritten: each library's own name @rpath/<name> (the SQL
  # bundle's runpath is the app's Frameworks), what it links beside it
  # (@loader_path); Homebrew's runpaths dropped. Then each signed again.
  local identity=${SIGN_IDENTITY:--} up args rpath
  while read -r dest; do
    up=""
    case "$dest" in */mariadb/plugin/*) up="../../" ;; esac
    args=()
    id=$(otool -D "$dest" | sed -n 2p)
    [ -z "$id" ] || args+=(-id "@rpath/$(basename "$dest")")
    for dep in $(otool -L "$dest" | tail -n +2 | awk '{print $1}'); do
      [ "$dep" != "$id" ] || continue
      case "$dep" in /usr/lib/*|/System/*) continue ;; esac
      args+=(-change "$dep" "@loader_path/$up$(basename "$dep")")
    done
    for rpath in $(otool -l "$dest" | awk '/cmd LC_RPATH/{getline; getline; print $2}'); do
      args+=(-delete_rpath "$rpath")
    done
    [ ${#args[@]} = 0 ] || install_name_tool "${args[@]}" "$dest" 2>&1 | { grep -v 'will invalidate the code signature' >&2 || true; }
    codesign --force --sign "$identity" --timestamp=none "$dest" 2>&1 | { grep -v "replacing existing signature" >&2 || true; }
  done < "$work/copied"

  # Each formula's licence, and the README.
  local name version prefix text f
  sort -u "$work/kegs.list" | while read -r name version; do
    prefix=$(brew --cellar)/$name/$version
    text=""
    for f in LICENSE.txt LICENSE COPYRIGHT COPYING.LIB NOTICE COPYING; do
      [ -f "$prefix/$f" ] && { text=$prefix/$f; break; }
    done
    [ -n "$text" ] || { echo "sql-clients: no licence in $prefix" >&2; exit 1; }
    cp -f "$text" "$licenses/$name.txt"
    python3 - "$prefix" "$name" "$(cat "$work/kegs/$name")" <<'PY'
import json, sys, subprocess
prefix, name, files = sys.argv[1:4]
sbom = json.load(open(prefix + "/sbom.spdx.json"))
package = next(p for p in sbom["packages"] if p.get("name") == name)
info = json.loads(subprocess.run(["brew", "info", "--json=v2", name], capture_output=True, text=True, check=True).stdout)
licence = info["formulae"][0].get("license") or "see its text"
if not isinstance(licence, str): licence = json.dumps(licence)
print("|".join([name, package.get("versionInfo", "?"), licence, package.get("downloadLocation", "?"), files.strip()]))
PY
  done | readme "$licenses"
  echo "sql-clients: $(sed "s|^$frameworks/||" "$work/copied" | tr '\n' ' ')"
  rm -rf "$work"

  # The app sealed again over what it now carries, its entitlements kept.
  codesign --force --sign "$identity" --timestamp=none --preserve-metadata=entitlements,requirements,flags "$app" 2>&1 | { grep -v "replacing existing signature" >&2 || true; }
}

appimage() {
  local appdir=$1
  local lib=$appdir/usr/lib
  local app; app=$(find "$appdir/usr" -maxdepth 3 -type d -name UDCode.app | head -n 1)
  [ -n "$app" ] || { echo "sql-clients: no UDCode.app in $appdir" >&2; exit 1; }
  local licenses=$app/Resources/Licenses
  local libpq mariadb
  libpq=$(/sbin/ldconfig -p | awk '/libpq\.so\.5 /{print $NF; exit}')
  mariadb=$(/sbin/ldconfig -p | awk '/libmariadb\.so\.3 /{print $NF; exit}')
  [ -n "$libpq" ] || missing "no libpq.so.5 (apt install libpq5)"
  [ -n "$mariadb" ] || missing "no libmariadb.so.3 (apt install libmariadb3)"
  mkdir -p "$lib/mariadb/plugin" "$licenses"
  cp -fL "$libpq" "$lib/libpq.so.5"
  cp -fL "$mariadb" "$lib/libmariadb.so.3"
  # Debian's plug-in directory (libmariadb3's); its authentication plug-ins
  local plugins; plugins=$(dirname "$(readlink -f "$mariadb")")/libmariadb3/plugin
  for p in caching_sha2_password sha256_password client_ed25519 parsec dialog mysql_clear_password auth_gssapi_client; do
    [ -f "$plugins/$p.so" ] && cp -fL "$plugins/$p.so" "$lib/mariadb/plugin/"
  done
  # Each package's copyright file (its licence, Debian's way), theirs and
  # those of what they link (which linuxdeploy brings, but the C library's),
  # and the README.
  local files=("$lib/libpq.so.5" "$lib/libmariadb.so.3" "$lib"/mariadb/plugin/*.so)
  # (merged /usr: dpkg knows a file by one of its two paths)
  local packages f
  packages=$( { readlink -f "$libpq" "$mariadb"
                ldd "${files[@]}" 2>/dev/null | awk '$2 == "=>" && $3 ~ /^\// {print $3}' | xargs -r readlink -f; } \
              | sort -u | while read -r f; do dpkg -S "$f" 2>/dev/null || dpkg -S "${f#/usr}" 2>/dev/null || true; done \
              | cut -d: -f1 | sort -u | grep -v '^libc6$' || true)
  local name version source licence
  for name in $packages; do
    cp -f "/usr/share/doc/$name/copyright" "$licenses/$name.txt"
    version=$(dpkg-query -W -f '${Version}' "$name")
    source=$(dpkg-query -W -f '${source:Package}' "$name")
    case "$name" in
      libpq5) licence=PostgreSQL ;;
      libmariadb3) licence=LGPL-2.1-or-later ;;
      libssl3) licence=Apache-2.0 ;;
      *) licence="as its copyright file says" ;;
    esac
    echo "$name|$version|$licence|Ubuntu's $source $version (apt-get source $source; https://launchpad.net/ubuntu/+source/$source)|$(dpkg -L "$name" | grep '\.so' | xargs -r -n1 basename | sort -u | tr '\n' ' ')"
  done | readme "$licenses"
  # What they link (OpenSSL, GSSAPI, LDAP...) is linuxdeploy's to bring, as
  # for any library in usr/lib (appimage.sh's PREPARE).
  echo "sql-clients: $(cd "$lib" && ls libpq.so.5 libmariadb.so.3 mariadb/plugin | tr '\n' ' ')"
}

windows() {
  local stage=$1
  local app=$stage/app/UDCode.app
  [ -f "$app/UDCode.exe" ] || { echo "sql-clients: no $app/UDCode.exe" >&2; exit 1; }
  local prefix=${MINGW_PREFIX:-/clang64}
  local licenses=$app/Resources/Licenses
  # A folder of their own, not UDCode.exe's: Windows looks in an exe's folder
  # first, and these (zlib1, libiconv-2, OpenSSL...) would stand in for the
  # GNUstep runtime's own. UDSQLConnection loads them by their path there.
  local clients=$app/SQLClients
  [ -f "$prefix/bin/libpq.dll" ] || missing "no libpq.dll (pacman -S ${MINGW_PACKAGE_PREFIX:-mingw-w64-clang-x86_64}-postgresql)"
  [ -f "$prefix/bin/libmariadb.dll" ] || missing "no libmariadb.dll (pacman -S ${MINGW_PACKAGE_PREFIX:-mingw-w64-clang-x86_64}-libmariadbclient)"
  local objdump; objdump=$(command -v llvm-objdump || command -v objdump)
  mkdir -p "$clients/mariadb/plugin" "$licenses"
  local queue=("$prefix/bin/libpq.dll" "$prefix/bin/libmariadb.dll")
  for p in "$prefix"/lib/mariadb/plugin/*.dll; do [ -f "$p" ] && queue+=("$p"); done
  local -A seen=() packages=()
  local order=()
  # Each DLL and what it imports from MSYS2 (what is not in its bin is
  # Windows'), beside UDCode.exe, where Windows looks first for what a DLL
  # loaded by its path imports (LOAD_WITH_ALTERED_SEARCH_PATH)
  while [ ${#queue[@]} -gt 0 ]; do
    local file=${queue[0]}; queue=("${queue[@]:1}")
    local base; base=$(basename "$file")
    local key; key=$(printf '%s' "$base" | tr 'A-Z' 'a-z')
    [ -z "${seen[$key]:-}" ] || continue
    seen[$key]=1
    case "$file" in
      */lib/mariadb/plugin/*) cp -f "$file" "$clients/mariadb/plugin/" ;;
      *) cp -f "$file" "$clients/" ;;
    esac
    local package; package=$(pacman -Qqo "$file" 2>/dev/null | head -n 1 || true)
    if [ -n "$package" ] && [ -z "${packages[$package]:-}" ]; then
      packages[$package]=$base; order+=("$package")
    elif [ -n "$package" ]; then
      packages[$package]="${packages[$package]} $base"
    fi
    for dll in $("$objdump" -p "$file" | sed -n 's/^[[:space:]]*DLL Name: //p' | tr -d '\r'); do
      local found; found=$(find "$prefix/bin" -maxdepth 1 -iname "$dll" | head -n 1)
      [ -n "$found" ] && queue+=("$found")
    done
  done
  # Each package's licence (MSYS2 keeps them in share/licenses) and the README.
  for package in "${order[@]}"; do
    local short=${package#"${MINGW_PACKAGE_PREFIX:-mingw-w64-clang-x86_64}-"}
    # its files, those in folders too (gettext-runtime's intl/, libasprintf/)
    local texts=()
    [ -d "$prefix/share/licenses/$short" ] && mapfile -t texts < <(find "$prefix/share/licenses/$short" -type f | sort)
    if [ ${#texts[@]} -gt 0 ]; then
      cat "${texts[@]}" > "$licenses/$short.txt"
    else
      echo "See https://packages.msys2.org/packages/$package" > "$licenses/$short.txt"
    fi
    local info; info=$(pacman -Qi "$package")
    local version licence base
    version=$(printf '%s\n' "$info" | sed -n 's/^Version *: //p')
    licence=$(printf '%s\n' "$info" | sed -n 's/^Licenses *: //p')
    base=$(printf '%s\n' "$info" | sed -n 's/^Base *: //p')
    echo "$short|$version|$licence|MSYS2's ${base:-$short} $version: https://packages.msys2.org/base/${base:-$short} (its PKGBUILD names the upstream source)|${packages[$package]}"
  done | readme "$licenses"
  echo "sql-clients: $(cd "$clients" && ls *.dll mariadb/plugin 2>/dev/null | tr '\n' ' ')"
}

case "$mode" in
  macos) macos "$dir" ;;
  appimage) appimage "$dir" ;;
  windows) windows "$dir" ;;
  *) echo "usage: sql-clients.sh macos|appimage|windows <dir>" >&2; exit 1 ;;
esac
