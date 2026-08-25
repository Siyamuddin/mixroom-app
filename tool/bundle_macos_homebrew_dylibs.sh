#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/Mixroom.app" >&2
  exit 64
fi

app_path="$1"
frameworks_path="$app_path/Contents/Frameworks"

if [[ ! -d "$frameworks_path" ]]; then
  echo "App framework directory not found: $frameworks_path" >&2
  exit 66
fi

work_path="$(mktemp -d "${TMPDIR:-/tmp}/mixroom-dylibs.XXXXXX")"
dependencies_path="$work_path/dependencies.txt"
seen_path="$work_path/seen.txt"
library_sources_path="$work_path/library-sources.txt"

cleanup() {
  rm -rf "$work_path"
}
trap cleanup EXIT

touch "$dependencies_path" "$seen_path" "$library_sources_path"

is_homebrew_dependency() {
  case "$1" in
    /opt/homebrew/opt/*|/opt/homebrew/Cellar/*|/usr/local/opt/*|/usr/local/Cellar/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

record_dependencies() {
  local binary_path="$1"
  local dependency_path

  while IFS= read -r dependency_path; do
    if is_homebrew_dependency "$dependency_path"; then
      printf '%s\n' "$dependency_path" >> "$dependencies_path"
    fi
  done < <(otool -L "$binary_path" 2>/dev/null | awk 'NR > 1 { print $1 }')
}

collect_dependency() {
  local dependency_path="$1"
  local child_path

  if grep -Fqx "$dependency_path" "$seen_path"; then
    return
  fi
  if [[ ! -f "$dependency_path" ]]; then
    echo "Required Homebrew library is missing on the build machine: $dependency_path" >&2
    exit 1
  fi

  printf '%s\n' "$dependency_path" >> "$seen_path"
  while IFS= read -r child_path; do
    if is_homebrew_dependency "$child_path"; then
      collect_dependency "$child_path"
    fi
  done < <(otool -L "$dependency_path" | awk 'NR > 1 { print $1 }')
}

find "$app_path/Contents" -type f -print0 | while IFS= read -r -d '' candidate_path; do
  if file "$candidate_path" | grep -q 'Mach-O'; then
    record_dependencies "$candidate_path"
  fi
done

sort -u "$dependencies_path" -o "$dependencies_path"
while IFS= read -r dependency_path; do
  [[ -n "$dependency_path" ]] && collect_dependency "$dependency_path"
done < "$dependencies_path"

sort -u "$seen_path" -o "$seen_path"
while IFS= read -r dependency_path; do
  library_name="$(basename "$dependency_path")"
  existing_source="$(awk -F '\t' -v name="$library_name" '$1 == name { print $2; exit }' "$library_sources_path")"

  if [[ -n "$existing_source" ]] && ! cmp -s "$dependency_path" "$existing_source"; then
    echo "Conflicting dependency sources share the name $library_name:" >&2
    echo "  $existing_source" >&2
    echo "  $dependency_path" >&2
    exit 1
  fi

  if [[ -z "$existing_source" ]]; then
    printf '%s\t%s\n' "$library_name" "$dependency_path" >> "$library_sources_path"
  fi
done < "$seen_path"

while IFS= read -r dependency_path; do
  library_name="$(basename "$dependency_path")"
  bundled_path="$frameworks_path/$library_name"

  [[ ! -f "$bundled_path" ]] || chmod u+w "$bundled_path"
  cp -L "$dependency_path" "$bundled_path"
  chmod u+w "$bundled_path"
done < "$seen_path"

find "$app_path/Contents" -type f -print0 | while IFS= read -r -d '' candidate_path; do
  if ! file "$candidate_path" | grep -q 'Mach-O'; then
    continue
  fi

  while IFS= read -r dependency_path; do
    library_name="$(basename "$dependency_path")"
    if otool -L "$candidate_path" 2>/dev/null | awk 'NR > 1 { print $1 }' | grep -Fqx "$dependency_path"; then
      install_name_tool -change "$dependency_path" "@rpath/$library_name" "$candidate_path"
    fi
  done < "$seen_path"
done

while IFS= read -r dependency_path; do
  library_name="$(basename "$dependency_path")"
  bundled_path="$frameworks_path/$library_name"
  install_name_tool -id "@rpath/$library_name" "$bundled_path"
done < "$seen_path"

: > "$dependencies_path"
find "$app_path/Contents" -type f -print0 | while IFS= read -r -d '' candidate_path; do
  if file "$candidate_path" | grep -q 'Mach-O'; then
    record_dependencies "$candidate_path"
  fi
done

sort -u "$dependencies_path" -o "$dependencies_path"

if [[ -s "$dependencies_path" ]]; then
  echo "Unresolved Homebrew dependencies remain:" >&2
  cat "$dependencies_path" >&2
  exit 1
fi

echo "Bundled $(wc -l < "$seen_path" | tr -d ' ') Homebrew libraries into $frameworks_path"
