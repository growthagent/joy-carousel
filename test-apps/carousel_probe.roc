app [main!] {
    pf: platform "../../basic-cli-zig/platform/main.roc",
    html: "../../joy-html-zig/package/main.roc",
    carousel: "../package/main.roc",
}

import pf.Stdout
import html.Html exposing [Html]
import carousel.Carousel

## Behavior probe for the carousel package, run via
## `roc build test-apps/carousel_probe.roc` and executing the binary.
## The in-module expects in package/Carousel.roc do not run under `roc test`
## because of its cross-package import of joy-html-zig, so this app exercises
## the public surface end to end and prints one PASS/FAIL line per check.
main! : List(Str) => Try({}, _)
main! = |_args| {
    failed = print_checks!(build_checks({}), 0, Bool.False)?
    if failed {
        Err(Exit(1))
    } else {
        Ok({})
    }
}

print_checks! : List({ label : Str, ok : Bool }), U64, Bool => Try(Bool, _)
print_checks! = |checks, idx, any_failed|
    match checks.get(idx) {
        Ok(check) => {
            if check.ok {
                Stdout.line!("PASS: ${check.label}")?
            } else {
                Stdout.line!("FAIL: ${check.label}")?
            }
            print_checks!(checks, idx + 1, any_failed or !check.ok)
        }
        Err(_) => Ok(any_failed)
    }

build_checks : {} -> List({ label : Str, ok : Bool })
build_checks = |{}| {
    init_ok =
        match Carousel.init({ id: "probe", config: Carousel.default_config, slide_count: 3 }) {
            Ok(state) => state.id == "probe" and state.active_index == 0 and state.slide_count == 3 and state.is_dragging == Bool.False
            Err(_) => Bool.False
        }

    init_rejects_zero_slides =
        match Carousel.init({ id: "probe", config: Carousel.default_config, slide_count: 0 }) {
            Err(NoSlides) => Bool.True
            _ => Bool.False
        }

    init_rejects_pipe_id =
        match Carousel.init({ id: "bad|id", config: Carousel.default_config, slide_count: 3 }) {
            Err(InvalidCarouselId(bad_id)) => bad_id == "bad|id"
            _ => Bool.False
        }

    init_rejects_out_of_bounds =
        match Carousel.init({ id: "probe", config: { ..Carousel.default_config, initial_slide: 5 }, slide_count: 3 }) {
            Err(InitialSlideOutOfBounds(bounds)) => bounds.initial_slide == 5 and bounds.slide_count == 3
            _ => Bool.False
        }

    set_slide_count_clamps =
        match Carousel.init({ id: "probe", config: { ..Carousel.default_config, initial_slide: 4 }, slide_count: 5 }) {
            Ok(state) =>
                match Carousel.set_slide_count(state, 3) {
                    Ok(new_state) => new_state.slide_count == 3 and new_state.active_index == 2
                    Err(_) => Bool.False
                }
            Err(_) => Bool.False
        }

    set_slide_count_rejects_zero =
        match Carousel.init({ id: "probe", config: Carousel.default_config, slide_count: 3 }) {
            Ok(state) =>
                match Carousel.set_slide_count(state, 0) {
                    Err(NoSlides) => Bool.True
                    Ok(_) => Bool.False
                }
            Err(_) => Bool.False
        }

    drag_advances_slide =
        match Carousel.init({ id: "probe", config: Carousel.default_config, slide_count: 3 }) {
            Ok(state) => {
                state1 = Carousel.update(state, MouseDown(200.0, 50.0))
                state2 = Carousel.update(state1, MouseMove(100.0, 50.0))
                state3 = Carousel.update(state2, MouseUp(100.0, 50.0))
                state3.active_index == 1 and state3.is_dragging == Bool.False
            }
            Err(_) => Bool.False
        }

    small_drag_stays =
        match Carousel.init({ id: "probe", config: Carousel.default_config, slide_count: 3 }) {
            Ok(state) => {
                state1 = Carousel.update(state, TouchStart(100.0, 50.0))
                state2 = Carousel.update(state1, TouchMove(70.0, 50.0))
                state3 = Carousel.update(state2, TouchEnd(70.0, 50.0))
                state3.active_index == 0 and state3.is_dragging == Bool.False
            }
            Err(_) => Bool.False
        }

    nav_events_move =
        match Carousel.init({ id: "probe", config: Carousel.default_config, slide_count: 5 }) {
            Ok(state) => {
                at1 = Carousel.update(state, NextSlide)
                at3 = Carousel.update(at1, GoToSlide(3))
                at2 = Carousel.update(at3, PrevSlide)
                still2 = Carousel.update(at2, GoToSlide(10))
                at1.active_index == 1 and at3.active_index == 3 and at2.active_index == 2 and still2.active_index == 2
            }
            Err(_) => Bool.False
        }

    encode_decode_round_trip =
        match Carousel.init({ id: "probe-carousel", config: Carousel.default_config, slide_count: 3 }) {
            Ok(state) => {
                encoded = Carousel.encode_event(state, GoToSlide(2))
                match Carousel.decode_event(encoded, []) {
                    Ok(decoded) =>
                        match decoded.event {
                            GoToSlide(idx) => decoded.id == "probe-carousel" and idx == 2 and encoded == "Carousel|probe-carousel|GoToSlide|2"
                            _ => Bool.False
                        }
                    _ => Bool.False
                }
            }
            Err(_) => Bool.False
        }

    decode_with_coords =
        match Carousel.decode_event("Carousel|probe|MouseDown", Str.to_utf8("123.5,456.7")) {
            Ok(decoded) =>
                match decoded.event {
                    MouseDown(x, y) => decoded.id == "probe" and x == 123.5 and y == 456.7
                    _ => Bool.False
                }
            _ => Bool.False
        }

    decode_rejects_unknown =
        match Carousel.decode_event("SomethingRandom123", []) {
            Err(UnknownEvent(msg)) => msg == "SomethingRandom123"
            _ => Bool.False
        }

    transform_strings =
        Carousel.calculate_transform({ active_index: 0, slides_per_view: 1.0, is_dragging: Bool.False, drag_offset_px: 0.0 }) == "translate3d(-0%, 0, 0)"
        and Carousel.calculate_transform({ active_index: 1, slides_per_view: 1.0, is_dragging: Bool.False, drag_offset_px: 0.0 }) == "translate3d(-100%, 0, 0)"
        and Carousel.calculate_transform({ active_index: 0, slides_per_view: 1.0, is_dragging: Bool.True, drag_offset_px: -50.0 }) == "translate3d(calc(-0% + -50px), 0, 0)"

    view_renders =
        match Carousel.init({ id: "probe", config: { ..Carousel.default_config, navigation: Bool.True }, slide_count: 2 }) {
            Ok(state) => {
                rendered = Html.render(Carousel.view(state, [slide("one"), slide("two")]))
                rendered.contains("id=\"probe\"")
                and rendered.contains("carousel-wrapper")
                and rendered.contains("translate3d(-0%, 0, 0)")
                and rendered.contains("aria-label=\"Previous slide\"")
                and rendered.contains("<div>one</div>")
            }
            Err(_) => Bool.False
        }

    fade_view_renders =
        match Carousel.init({ id: "probe", config: { ..Carousel.default_config, is_fade: Bool.True }, slide_count: 2 }) {
            Ok(state) => {
                rendered = Html.render(Carousel.view(state, [slide("one"), slide("two")]))
                rendered.contains("carousel-wrapper--fade")
                and rendered.contains("carousel-slide--active")
                and rendered.contains("--carousel-fade-duration: 300ms")
            }
            Err(_) => Bool.False
        }

    json_round_trip =
        match Carousel.init({ id: "probe", config: Carousel.default_config, slide_count: 3 }) {
            Ok(state) => {
                dragged = Carousel.update(state, MouseDown(12.5, 3.0))
                match Json.to_str_try(dragged) {
                    Ok(encoded) => {
                        decoded : Try(Carousel.State, _)
                        decoded = Json.parse(encoded)
                        match decoded {
                            Ok(restored) => restored == dragged
                            Err(_) => Bool.False
                        }
                    }
                    Err(_) => Bool.False
                }
            }
            Err(_) => Bool.False
        }

    config_json_round_trip =
        match Json.to_str_try(Carousel.default_config) {
            Ok(encoded) => {
                decoded : Try(Carousel.Config, _)
                decoded = Json.parse(encoded)
                match decoded {
                    Ok(restored) => restored == Carousel.default_config
                    Err(_) => Bool.False
                }
            }
            Err(_) => Bool.False
        }

    [
        { label: "init stores id, initial index and slide count", ok: init_ok },
        { label: "init rejects zero slides", ok: init_rejects_zero_slides },
        { label: "init rejects id containing a pipe", ok: init_rejects_pipe_id },
        { label: "init rejects out of bounds initial slide", ok: init_rejects_out_of_bounds },
        { label: "set_slide_count clamps the active index", ok: set_slide_count_clamps },
        { label: "set_slide_count rejects zero", ok: set_slide_count_rejects_zero },
        { label: "mouse drag past the threshold advances the slide", ok: drag_advances_slide },
        { label: "touch drag below the threshold stays put", ok: small_drag_stays },
        { label: "NextSlide, PrevSlide and GoToSlide move within bounds", ok: nav_events_move },
        { label: "encode_event and decode_event round-trip", ok: encode_decode_round_trip },
        { label: "decode_event parses coordinate payloads", ok: decode_with_coords },
        { label: "decode_event rejects unknown events", ok: decode_rejects_unknown },
        { label: "calculate_transform emits the pinned CSS strings", ok: transform_strings },
        { label: "view renders slides, transform and nav buttons via SSR", ok: view_renders },
        { label: "fade mode view renders the fade classes", ok: fade_view_renders },
        { label: "State survives a JSON round-trip", ok: json_round_trip },
        { label: "Config survives a JSON round-trip", ok: config_json_round_trip },
    ]
}

slide : Str -> Html(Str)
slide = |content| Html.div([], [Html.text(content)])
