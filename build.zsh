#!/bin/zsh --no-rcs
# Packages src/ into dist/Slack-Quick-Switcher-<version>.alfredworkflow
# after linting the plist and syntax-checking the scripts.
#
#   ./build.zsh            build
#   ./build.zsh --test     run the offline tests first

emulate -L zsh
setopt err_exit
root=${0:A:h}
cd "$root"

[[ ${1:-} == --test ]] && zsh tests/run.zsh

plutil -lint -s src/info.plist
for f in src/scripts/*.zsh; do zsh -n "$f"; done
# Compile-check the jq programs (runtime errors on the dummy input are fine).
for f in src/scripts/*.jq; do
  err=$(jq -n -f "$f" --arg q '' --argjson fuzzy false --argjson now 0 \
          --argjson users '[]' --argjson ext '[]' --argjson convs '[]' --argjson members '[]' \
          --arg team T --arg self U --argjson bots 0 2>&1 >/dev/null || true)
  [[ $err != *'compile error'* ]] || { print -r -- "$f: $err"; exit 1 }
done

version=$(plutil -extract version raw src/info.plist)
out=dist/Slack-Quick-Switcher-$version.alfredworkflow
mkdir -p dist
rm -f -- "$out"
(cd src && zip -q -r -X "../$out" . -x '.*' -x '*/.*')
print -r -- "Built $out"
