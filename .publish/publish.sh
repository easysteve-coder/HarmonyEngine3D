#!/bin/zsh
# Exports the committed state of the private HarmonyEngine3D repository into
# this public repository, minus internal material, and creates one commit.
# Modelled on Planarium-public/.publish/publish.sh.
#
#   .publish/publish.sh            # prepare and commit, no push
#   .publish/publish.sh --push     # additionally push to origin/main
#
# Only HEAD of the private repo is exported (git archive), never the working
# tree: uncommitted or untracked files there cannot leak.
set -euo pipefail

PUBLIC="${0:A:h:h}"
PRIVATE="${HE3D_PRIVATE:-${PUBLIC:h}/HarmonyEngine3D}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Paths of the private repo that are published. Everything else stays private
# (agent handoffs and rules, internal reviews, personal notes, reference images).
INCLUDE=(
  LICENSE
  THIRD-PARTY-NOTICES.md
  CHANGELOG.md
  ROADMAP.md
  ARCHITECTURE.md
  SYNTH_ARCHITECTURE_PLAN.md
  HarmonyNetwork_Spec_v1.md
  "DesignerKit — HarmonyWeb-Viewer User Guide.md"
  "DesignerKit — HarmonyWeb-Viewer Bedienungsanleitung.md"
  "Harmonic Radar — Bedienungsanleitung.md"
  Package.swift
  Sources
  Tests
)
EXCLUDE=(
  Sources/HarmonyEngine3D/Resources/.DS_Store
)

git -C "$PRIVATE" diff --quiet HEAD -- "${INCLUDE[@]}" || \
  print -u2 "Hinweis: uncommittete Änderungen in veröffentlichten Pfaden werden NICHT übernommen."

SUBJECT="$(git -C "$PRIVATE" log -1 --format=%s)"
git -C "$PRIVATE" archive HEAD -- "${INCLUDE[@]}" | tar -x -C "$STAGE"
for p in "${EXCLUDE[@]}"; do rm -rf -- "$STAGE/$p"; done

# Guard: nothing personal or internal may leave.
if grep -rIlE '/Users/[a-z]|@gmx\.|fritz\.box|192\.168\.|\.ts\.net|gh[op]_[A-Za-z0-9]{20}|Syncthing|SynologyDrive' "$STAGE" \
     | grep -v 'Tests/' ; then
  print -u2 "Abbruch: persönliche oder interne Angabe im Export (siehe oben)."; exit 1
fi
if [[ -e "$STAGE/.agent_handoff" || -e "$STAGE/AGENTS.md" || -e "$STAGE/CLAUDE.md" ]]; then
  print -u2 "Abbruch: interne Datei im Export."; exit 1
fi

# Replace the published tree; keep files that exist only in the public repo
# (README.md, .gitignore, .publish).
cd "$PUBLIC"
for p in "${INCLUDE[@]}"; do rm -rf -- "$p"; done
rsync -a "$STAGE"/ "$PUBLIC"/

git add -A
if git diff --cached --quiet; then
  print "Nichts zu veröffentlichen."
  exit 0
fi
git commit -q -m "$SUBJECT"
print "Commit angelegt: $(git log -1 --format='%h %s')"

if [[ "${1:-}" == "--push" ]]; then
  git push -u origin main
fi
