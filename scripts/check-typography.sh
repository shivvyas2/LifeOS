#!/bin/zsh
# Fails if a font is declared anywhere but the scale.
#
# The app once carried 376 hand-written font calls across 28 sizes, because
# nothing stopped a screen inventing its own. `LifeOSType` is the scale now, and
# this is what keeps it the only one: adding a step is a deliberate edit to
# Typography.swift, not something that happens by accident on a Tuesday.
#
# Run from the repo root. Exits non-zero on any violation.

set -u
cd "$(dirname "$0")/.."

SCALE="LifeOSKit/Sources/DesignSystem/Typography.swift"
FAIL=0

check() {
  local title=$1 pattern=$2
  local hits
  hits=$(grep -rn --include='*.swift' "$pattern" LIfeOS LifeOSKit/Sources 2>/dev/null | grep -v "^$SCALE:") || true
  if [[ -n "$hits" ]]; then
    printf '\n%s\n%s\n' "$title" "$hits"
    FAIL=1
  fi
}

# A literal point size outside the scale. Computed sizes are allowed: an icon
# drawn at a fraction of its container is not type and has no step to pick.
check "Literal font sizes outside the scale (use a LifeOSType step):" \
  '\.system(size: [0-9]'

check "UIKit fonts outside the scale (use LifeOSType.UIKitScale):" \
  '\(systemFont\|monospacedSystemFont\)(ofSize:'

# Rounded is for numerals and lives behind LifeOSType.numeral. A rounded word
# beside a sans word is the drift the scale exists to stop.
check "Rounded or serif faces declared outside the scale:" \
  'design: \.\(rounded\|serif\)'

# Apple's semantic sizes are a second scale nobody chose, and they do not line
# up with ours.
check "Apple semantic text styles (use a LifeOSType step):" \
  '\.font(\.\(largeTitle\|title[0-9]*\|headline\|subheadline\|body\|callout\|footnote\|caption[0-9]*\))'

if [[ $FAIL -eq 0 ]]; then
  printf 'Typography: every font comes from LifeOSType.\n'
else
  printf '\nTypography check failed.\n'
fi
exit $FAIL
