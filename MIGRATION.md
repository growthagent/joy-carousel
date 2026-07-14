# Migration to the zig-based Roc compiler

The package (package/Carousel.roc, package/main.roc) and the serialization
guard (test_serialization.roc) are ported to the new compiler. The joy-html
URL dependency is replaced with a local path dependency on
../joy-html-zig/package/main.roc.

## Browser tests are pending the joy-zig port

The Playwright browser tests (tests/, test-runner.roc, tests/app) run on the
OLD joy platform embedded in ./joy and cannot be ported yet: the joy-zig
client protocol differs (typed boxed messages handed straight to update!
instead of encoded event name strings plus a payload). Port them together
with the joy-zig migration.

Related protocol note: joy-zig message events carry no payload, so the drag
handlers attached by Carousel.view deliver their event string without the
pointer coordinates the old joy runtime appended. decode_event still accepts
a coordinate payload (and defaults to 0,0 without one); wiring real
coordinates back up is part of the joy-zig port.

## Verification

`roc test` runs nothing (silently) for modules with cross-package imports,
which includes package/Carousel.roc. Use the probe app instead:

    roc build test-apps/carousel_probe.roc && ./carousel_probe
    roc build test_serialization.roc && ./test_serialization

Both print PASS/FAIL lines and exit non-zero on failure.
