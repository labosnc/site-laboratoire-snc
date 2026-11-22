#!/bin/bash
# Met à jour le site à partir du fichier Excel (double-clic dans le Finder).
cd "$(dirname "$0")" || exit 1
export LANG=fr_CA.UTF-8 LC_ALL=fr_CA.UTF-8

if ! command -v git >/dev/null 2>&1 || ! git --version >/dev/null 2>&1; then
  echo "Git est introuvable. Lancez « xcode-select --install » dans le Terminal, puis relancez."
  read -r -p "Appuyez sur Entrée pour fermer."
  exit 1
fi

# Ruby de Homebrew s'il est installé, sinon celui de macOS.
RUBY=""
for r in /opt/homebrew/opt/ruby/bin/ruby /usr/local/opt/ruby/bin/ruby "$(command -v ruby)"; do
  if [ -n "$r" ] && [ -x "$r" ]; then RUBY="$r"; break; fi
done
if [ -z "$RUBY" ]; then
  echo "Ruby est introuvable. Installez-le avec Homebrew : brew install ruby"
  read -r -p "Appuyez sur Entrée pour fermer."
  exit 1
fi

"$RUBY" -Eutf-8:utf-8 scripts/mettre-a-jour.rb "$@"
echo
read -r -p "Appuyez sur Entrée pour fermer."
