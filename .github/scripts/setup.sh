#!/usr/bin/env bash
# Everything ./tests.roc needs beyond a Roc compiler: Playwright and Chromium,
# which the browser specs drive. Run by suite.yml's `setup`, once Roc is
# installed.
#
# On Linux and macOS both come from Nix, out of the nixpkgs the flake locks,
# so a runner has the very Playwright and Chromium of the dev shell. The
# Chromium brings its own libraries, so nothing goes through apt, whose
# mirrors have hung these legs for an hour at a time. The Roc compiler is
# still the downloaded nightly the suite installed, Nix only supplies the
# browser.
#
# Nix has no Windows, so a Windows runner takes Playwright from npm.
set -euo pipefail

if [ "$RUNNER_OS" = Windows ]; then
  # Keep the version in step with the dev shell's playwright-test
  # (`nix develop -c playwright --version`). roc-playwright talks to
  # Playwright's private driver protocol, which upstream may change in any
  # release, so a runner and a developer machine disagreeing about the
  # version means they are testing two different protocols.
  npm install -g "playwright@1.63.0"
  playwright install chromium
  playwright --version
  exit 0
fi

curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
  | sh -s -- install --no-confirm
# shellcheck disable=SC1091
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

# --inputs-from makes `nixpkgs` the revision flake.lock pins.
paths=$(nix build --inputs-from . --no-link --print-out-paths \
  nixpkgs#playwright-test nixpkgs#playwright-driver.browsers)
playwright=$(printf '%s\n' "$paths" | grep -- '-playwright-test-')
browsers=$(printf '%s\n' "$paths" | grep -- '-playwright-browsers')

# For the steps after this one, the same as the dev shell's shellHook.
echo "$playwright/bin" >> "$GITHUB_PATH"
{
  echo "PLAYWRIGHT_BROWSERS_PATH=$browsers"
  echo "PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true"
} >> "$GITHUB_ENV"

"$playwright/bin/playwright" --version
