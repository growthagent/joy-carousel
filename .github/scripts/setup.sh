#!/usr/bin/env bash
# Everything ./tests.roc needs beyond a Roc compiler: Playwright and Chromium,
# which the browser specs drive. Run by suite.yml's `setup`, once Roc is
# installed.
set -euo pipefail

# Keep the version in step with the dev shell's playwright-test
# (`nix develop -c playwright --version`). roc-playwright talks to Playwright's
# private driver protocol, which upstream may change in any release, so a
# runner and a developer machine disagreeing about the version means they are
# testing two different protocols.
PLAYWRIGHT_VERSION=1.61.1

npm install -g "playwright@$PLAYWRIGHT_VERSION"

# Only a Linux runner is missing the system libraries the browser needs.
if [ "$RUNNER_OS" = Linux ]; then
  playwright install --with-deps chromium
else
  playwright install chromium
fi

playwright --version

