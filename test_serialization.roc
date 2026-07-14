app [main!] {
    pf: platform "../basic-cli-zig/platform/main.roc",
    carousel: "package/main.roc",
}

import pf.Stdout
import carousel.Carousel

## Regression guard, run via `roc build test_serialization.roc` and executing
## the resulting binary (expects in modules with cross-package imports do not
## run under `roc test` at this time, so this is a small app instead).
##
## `Carousel.State` must stay JSON-encodable AND decodable: consumers embed it
## in page models that round-trip through SSR (the server encodes the model to
## JSON; the client decodes it). A tag union anywhere in `State`/`Config` makes
## the JSON codec underivable, which breaks the consumer's build. Keep `State`
## and `Config` flat (scalars/records only, no tag-union fields).
##
## Notes on the builtin Json module (which replaced roc-json): records that
## contain `F64` fields must be encoded with `Json.to_str_try` (plain `to_str`
## is unavailable because NaN/Infinity have no JSON representation), and both
## `Json.parse` and `Json.to_str_try` need fully concrete types at the call
## site, hence the annotations below.
main! : List(Str) => Try({}, _)
main! = |_args| {
    report!("Config JSON round-trip", config_round_trip({}))?
    report!("State JSON round-trip", state_round_trip({}))?
    Ok({})
}

report! : Str, Try({}, Str) => Try({}, _)
report! = |label, result|
    match result {
        Ok({}) => Stdout.line!("PASS: ${label}")
        Err(reason) => {
            Stdout.line!("FAIL: ${label} (${reason})")?
            Err(Exit(1))
        }
    }

config_round_trip : {} -> Try({}, Str)
config_round_trip = |{}| {
    config = Carousel.default_config
    encoded = Json.to_str_try(config).map_err(|_| "Config failed to encode")?
    decoded : Try(Carousel.Config, _)
    decoded = Json.parse(encoded)
    restored = decoded.map_err(|_| "Config failed to decode")?
    if restored == config {
        Ok({})
    } else {
        Err("Config did not round-trip faithfully")
    }
}

state_round_trip : {} -> Try({}, Str)
state_round_trip = |{}| {
    state = Carousel.init({ id: "guard", config: Carousel.default_config, slide_count: 3 }).map_err(|_| "Carousel.init failed")?
    encoded = Json.to_str_try(state).map_err(|_| "State failed to encode")?
    decoded : Try(Carousel.State, _)
    decoded = Json.parse(encoded)
    restored = decoded.map_err(|_| "State failed to decode")?
    if restored == state {
        Ok({})
    } else {
        Err("State did not round-trip faithfully")
    }
}
