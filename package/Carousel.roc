import html.Html
import html.Attribute
import SlidesPerView

## A carousel of slides that the user swipes, drags or steps through. It holds
## its slides, so the slide count and the slides it renders can never
## disagree, and the active slide is always one of them. Its state is hidden:
## create it with [new], change it with [update] and [set_slides], read it
## with the accessors and render it with [view].
##
## ```
## model = { games: Carousel.new({ id: "games", slides: ["Diablo II", "Quake"], label: Labelled("Games") }) }
##
## # update
## Games(event) => { ..model, games: model.games.update(event) }
##
## # render
## model.games.view(|name, _index| Html.div([], [Html.text(name)]), |event| Games(event))
## ```
Carousel(slide) :: {
    id : Str,
    items : List(slide),
    position : U64,
    # A press is not a drag until it moves, see `drag_start_px`.
    drag : [Resting, Pressed({ start_x : F64 }), Dragging({ start_x : F64, offset_px : F64 })],
    transition : [Slide, Fade],
    slides_per_view : SlidesPerView,
    navigation : [NoButtons, Buttons({ previous : Str, next : Str })],
    at_ends : [Stop, Wrap],
    wraps : [Slide, Jump],
    # The track took its place without a transition: a wrap that `wraps:
    # Jump` made instant. The next move animates again.
    instant : Bool,
    label : [Labelled(Str), LabelledBy(Str)],
    role : [Region, Group],
    slide_label : Str,
    drag_threshold_px : U32,
    duration_ms : U32,
}.{
    ## What [new] takes. `id`, `slides` and `label` are required. Every other
    ## field has a default, which applies when the record is written inline at
    ## the call:
    ##
    ## - `id`: the carousel element's `id`, for CSS and tests. The element
    ##   that holds the slides gets the `id` `<id>-slides`.
    ## - `slides`: the slides, in order. An empty list is fine, a carousel
    ##   can get its slides later through [set_slides].
    ## - `label`: the carousel's accessible name, which the WAI-ARIA carousel
    ##   pattern asks for. `Labelled("Reviews")` names it, and
    ##   `LabelledBy("reviews-heading")` names it after the visible heading
    ##   with that `id`.
    ## - `role`: `Region` (default) makes the carousel a landmark that screen
    ##   reader users can jump to. `Group` suits a carousel that a page has
    ##   many of, like the photos on every product card.
    ## - `transition`: `Slide` (default) moves a horizontal track, `Fade`
    ##   cross-fades the slides in place.
    ## - `slides_per_view`: how many slides show at once (default one), see
    ##   [SlidesPerView].
    ## - `navigation`: `NoButtons` (default), or `Buttons` with the
    ##   accessible names of the previous and next buttons, in the page's
    ##   language: `Buttons({ previous: "Previous slide", next: "Next slide" })`.
    ## - `at_ends`: `Stop` (default) keeps the first and last slides where
    ##   they are, `Wrap` steps from the end to the start and back.
    ## - `wraps`: how a wrap looks with the `Slide` transition. `Slide`
    ##   (default) moves the track back across every slide in between, `Jump`
    ##   puts the slide at the other end in place at once. When the other
    ##   end is the neighbouring position, as with two slides, a wrap is a
    ##   step to the neighbour, and slides either way.
    ##   `Jump` suits slides that are only rendered near the active one, like
    ##   a gallery that loads the neighbouring pictures only, where sliding
    ##   across the track would sweep past empty slides.
    ## - `slide_label`: each slide's accessible name, in the page's language.
    ##   `{number}` stands for the slide's position counting from 1 and
    ##   `{count}` for how many slides there are. The default is
    ##   `"{number} / {count}"`, which names the third of five slides "3 / 5".
    ## - `drag_threshold_px`: how far a drag has to go to change the slide
    ##   (default 50).
    ## - `duration_ms`: how long a slide change animates (default 300).
    Options(slide) := {
        id : Str,
        slides : List(slide),
        label : [Labelled(Str), LabelledBy(Str)],
        role : [Region, Group] ?? Region,
        transition : [Slide, Fade] ?? Slide,
        slides_per_view : SlidesPerView ?? SlidesPerView.one,
        navigation : [NoButtons, Buttons({ previous : Str, next : Str })] ?? NoButtons,
        at_ends : [Stop, Wrap] ?? Stop,
        wraps : [Slide, Jump] ?? Slide,
        slide_label : Str ?? "{number} / {count}",
        drag_threshold_px : U32 ?? 50,
        duration_ms : U32 ?? 300,
    }

    ## A carousel on its first slide.
    new : Options(slide) -> Carousel(slide)
    new = |{ id, slides, label, role, transition, slides_per_view, navigation, at_ends, wraps, slide_label, drag_threshold_px, duration_ms }| {
        id,
        items: slides,
        position: 0,
        drag: Resting,
        transition,
        slides_per_view,
        navigation,
        at_ends,
        wraps,
        instant: Bool.False,
        label,
        role,
        slide_label,
        drag_threshold_px,
        duration_ms,
    }

    ## What a carousel's [view] sends through the `to_msg` the app passes, for
    ## the app to hand back to [update]. Navigation the app renders itself
    ## sends [next], [previous] or [go_to]:
    ##
    ## ```
    ## Html.button([Attribute.on_click(Games(Carousel.next))], [Html.text("Next")])
    ## ```
    Event :: {
        action : [
            # The pointer's horizontal client coordinate, and the button,
            # since only the primary button drags.
            PointerDown({ x : F64, button : U8 }),
            PointerMove(F64),
            PointerUp,
            PointerLeave,
            # The browser took the gesture over, a vertical scroll for one.
            PointerCancel,
            # The browser starting to drag an image or a link inside a slide,
            # which the view suppresses so the swipe keeps working.
            NativeDragStart,
            Previous,
            Next,
            GoTo(U64),
        ],
    }

    ## Step to the next slide, like the next button.
    next : Event
    next = { action: Next }

    ## Step to the previous slide, like the previous button.
    previous : Event
    previous = { action: Previous }

    ## Go to the slide at `index`. Near the end of a carousel that shows
    ## several slides at once, the view stops where the last slide is fully
    ## in it, which brings the slide at `index` into view too. An index past
    ## the last slide changes nothing.
    go_to : U64 -> Event
    go_to = |index| { action: GoTo(index) }

    ## Apply an event.
    update : Carousel(slide), Event -> Carousel(slide)
    update = |carousel, event|
        match event.action {
            PointerDown({ x, button }) =>
                if button == 0 {
                    { ..carousel, drag: Pressed({ start_x: x }) }
                } else {
                    carousel
                }

            PointerMove(x) =>
                match carousel.drag {
                    Resting => carousel
                    Pressed({ start_x }) =>
                        if (x - start_x).abs() > drag_start_px(carousel) {
                            { ..carousel, drag: Dragging({ start_x, offset_px: x - start_x }) }
                        } else {
                            carousel
                        }

                    Dragging({ start_x, .. }) => { ..carousel, drag: Dragging({ start_x, offset_px: x - start_x }) }
                }

            PointerUp => finish_drag(carousel)

            PointerLeave => finish_drag(carousel)

            PointerCancel => { ..carousel, drag: Resting, instant: Bool.False }

            NativeDragStart => carousel

            Previous => step(carousel, Back)

            Next => step(carousel, Forward)

            GoTo(index) =>
                if index < carousel.items.len() {
                    { ..carousel, position: index.min(last_position(carousel)), instant: Bool.False }
                } else {
                    carousel
                }
        }

    ## Replace the slides, keeping the active slide's index when the view can
    ## still go there and going as far as it can otherwise.
    set_slides : Carousel(slide), List(slide) -> Carousel(slide)
    set_slides = |carousel, new_slides| {
        replaced = { ..carousel, items: new_slides }
        { ..replaced, position: replaced.position.min(last_position(replaced)) }
    }

    ## The slides, in order.
    slides : Carousel(slide) -> List(slide)
    slides = |carousel| carousel.items

    ## How many slides the carousel has.
    slide_count : Carousel(slide) -> U64
    slide_count = |carousel| carousel.items.len()

    ## The index of the active slide, the first one in view. A carousel that
    ## shows several slides at once stops where the last slide is fully in
    ## view, so near the end the active index goes no further. 0 when there
    ## are no slides.
    active_index : Carousel(slide) -> U64
    active_index = |carousel| carousel.position

    ## Whether [previous] would change the slide. With `at_ends: Wrap` it
    ## does whenever there are more slides than fit in view.
    has_previous : Carousel(slide) -> Bool
    has_previous = |carousel| neighbour(carousel, Back).is_ok()

    ## Whether [next] would change the slide. With `at_ends: Wrap` it does
    ## whenever there are more slides than fit in view.
    has_next : Carousel(slide) -> Bool
    has_next = |carousel| neighbour(carousel, Forward).is_ok()

    ## Render the carousel. `render_slide` gets each slide and its index and
    ## renders it with the app's own message type, and `to_msg` wraps the
    ## carousel's [Event]s in that type. An app with several carousels tells
    ## them apart by the wrapper it passes to each.
    ##
    ## Each slide sits in a group named by `slide_label`, and the slides
    ## outside the visible window are `inert`, so neither the keyboard nor a
    ## screen reader lands on a slide nobody can see. The slides sit in a
    ## polite live region, so a screen reader reads the slide that comes into
    ## view.
    view : Carousel(slide), (slide, U64 -> Html(msg)), (Event -> msg) -> Html(msg)
    view = |carousel, render_slide, to_msg| {
        count = carousel.items.len()
        slide_views = carousel.items.map_with_index(|item, index| slide_view(carousel, index, count, render_slide(item, index)))
        slides_id = "${carousel.id}-slides"

        # The WAI-ARIA carousel pattern makes the slides' container a polite
        # live region for a carousel that does not rotate on its own.
        live = [Attribute.id(slides_id), Attribute.aria("live", "polite"), Attribute.aria("atomic", "false")]

        track =
            match carousel.transition {
                Slide =>
                    Html.div(
                        live.concat(
                            [
                                Attribute.class("carousel-wrapper"),
                                Attribute.style([("transform", track_transform(carousel)), ("transition", track_transition(carousel))]),
                            ],
                        ),
                        slide_views,
                    )

                Fade =>
                    Html.div(
                        live.concat(
                            [
                                Attribute.class("carousel-wrapper carousel-wrapper--fade"),
                                # carousel.css reads this in each slide's opacity
                                # transition. Set once here, it cascades to every slide.
                                Attribute.style([("--carousel-fade-duration", "${carousel.duration_ms.to_str()}ms")]),
                            ],
                        ),
                        slide_views,
                    )
            }

        buttons =
            match carousel.navigation {
                NoButtons => []
                Buttons(names) => [
                    nav_button("carousel-button-prev", names.previous, slides_id, neighbour(carousel, Back).is_ok(), to_msg(Carousel.previous)),
                    nav_button("carousel-button-next", names.next, slides_id, neighbour(carousel, Forward).is_ok(), to_msg(Carousel.next)),
                ]
            }

        Html.div(
            [
                Attribute.id(carousel.id),
                Attribute.class("carousel"),
                # Without this, dragging an image or a link inside a slide
                # starts the browser's own drag, which cancels the swipe.
                Attribute.on("dragstart", to_msg({ action: NativeDragStart })).prevent_default(),
            ]
                .concat(landmark(carousel.role, carousel.label))
                .concat(pointer_handlers(carousel.drag, to_msg)),
            [track].concat(buttons),
        )
    }
}

## The position one step in `direction`, round the end when the carousel
## wraps.
neighbour : Carousel(slide), [Back, Forward] -> Try(U64, [NoNeighbour])
neighbour = |carousel, direction| {
    position = carousel.position
    last = last_position(carousel)
    wrapping =
        match carousel.at_ends {
            Wrap => last > 0
            Stop => Bool.False
        }
    match direction {
        Back =>
            if position > 0 {
                Ok(position - 1)
            } else if wrapping {
                Ok(last)
            } else {
                Err(NoNeighbour)
            }

        Forward =>
            if position < last {
                Ok(position + 1)
            } else if wrapping {
                Ok(0)
            } else {
                Err(NoNeighbour)
            }
    }
}

## The furthest the view goes: the position that brings the last slide fully
## into view. With one slide per view that is the last slide. With more the
## view stops short of it, so it never shows empty space past the end.
last_position : Carousel(slide) -> U64
last_position = |carousel| {
    count = carousel.items.len()
    if count == 0 {
        0
    } else {
        # How many slides lie past the first view. The slack keeps a slides
        # per view that is whole in all but rounding from adding a last step
        # that barely moves.
        beyond = count.to_f64() - carousel.slides_per_view.to_f64() - 0.000001
        steps = if beyond > 0.0 beyond.ceiling_to_u64_try() ?? (count - 1) else 0
        steps.min(count - 1)
    }
}

## Where the view starts, in slides from the first: at the active slide, but
## never past where the last slide is fully in view. Fractional when a slides
## per view that is not whole reaches the end.
view_start : Carousel(slide) -> F64
view_start = |carousel| {
    end = carousel.items.len().to_f64() - carousel.slides_per_view.to_f64()
    F64.min(carousel.position.to_f64(), F64.max(0.0, end))
}

step : Carousel(slide), [Back, Forward] -> Carousel(slide)
step = |carousel, direction|
    match neighbour(carousel, direction) {
        Ok(position) => { ..carousel, position, instant: jumps(carousel, position) }
        Err(NoNeighbour) => carousel
    }

## Whether a step to `position` shows without a transition: a wrap that
## `wraps: Jump` keeps from sliding across the slides in between. A step
## is longer than one slide only when it wraps.
jumps : Carousel(slide), U64 -> Bool
jumps = |carousel, position| {
    distance = if position > carousel.position position - carousel.position else carousel.position - position
    match (carousel.wraps, carousel.transition) {
        (Jump, Slide) => distance > 1
        _ => Bool.False
    }
}

## How far a press has to move to become a drag. Until then the track stays
## where it is, so a press on a button lets a running slide change finish,
## and a click on the content of a slide goes through. Never more than the
## drag threshold, so every drag long enough to change the slide is a drag.
drag_start_px : Carousel(slide) -> F64
drag_start_px = |carousel| F64.min(5.0, carousel.drag_threshold_px.to_f64())

## End a drag: past the threshold to the left is the next slide, past it to
## the right the previous one, anything shorter stays. A press that never
## moved was a click, which the content under it gets.
finish_drag : Carousel(slide) -> Carousel(slide)
finish_drag = |carousel|
    match carousel.drag {
        Resting => carousel
        Pressed(_) => { ..carousel, drag: Resting }
        Dragging(drag) => {
            threshold = carousel.drag_threshold_px.to_f64()
            rested = { ..carousel, drag: Resting, instant: Bool.False }
            if drag.offset_px < 0.0 - threshold {
                step(rested, Forward)
            } else if drag.offset_px > threshold {
                step(rested, Back)
            } else {
                rested
            }
        }
    }

## A press can start a drag at any time. The rest of a drag is only listened
## for while a press lasts, so hovering over a carousel sends nothing.
pointer_handlers : [Resting, Pressed({ start_x : F64 }), Dragging({ start_x : F64, offset_px : F64 })], (Carousel.Event -> msg) -> List(Attribute(msg))
pointer_handlers = |drag, to_msg| {
    press = Attribute.on_pointer_down(|e| to_msg({ action: PointerDown({ x: e.client_x, button: e.button }) }))
    match drag {
        Resting => [press]
        Pressed(_) | Dragging(_) => [
            press,
            Attribute.on_pointer_move(|e| to_msg({ action: PointerMove(e.client_x) })),
            Attribute.on_pointer_up(|_| to_msg({ action: PointerUp })),
            Attribute.on_pointer_leave(|_| to_msg({ action: PointerLeave })),
            Attribute.on_pointer_cancel(|_| to_msg({ action: PointerCancel })),
        ]
    }
}

## The carousel's role and accessible name. A region is a landmark, a group
## is not.
landmark : [Region, Group], [Labelled(Str), LabelledBy(Str)] -> List(Attribute(msg))
landmark = |role, label| {
    role_attribute =
        match role {
            Region => Attribute.role("region")
            Group => Attribute.role("group")
        }
    name =
        match label {
            Labelled(text) => Attribute.aria("label", text)
            LabelledBy(id) => Attribute.aria("labelledby", id)
        }
    [role_attribute, Attribute.aria("roledescription", "carousel"), name]
}

## A previous or next button, which controls the slides. One that would
## change nothing is marked `aria-disabled` rather than disabled, so the
## keyboard focus stays on it when a step reaches the end, and it keeps the
## `carousel-button-disabled` class for styling. Pressing it changes nothing.
nav_button : Str, Str, Str, Bool, msg -> Html(msg)
nav_button = |class, name, slides_id, enabled, msg| {
    unavailable = if enabled [] else [Attribute.aria("disabled", "true")]
    Html.button(
        [
            Attribute.class(if enabled class else "${class} carousel-button-disabled"),
            Attribute.type("button"),
            Attribute.aria("label", name),
            Attribute.aria("controls", slides_id),
        ]
            .concat(unavailable)
            .concat([Attribute.on_click(msg)]),
        [],
    )
}

slide_view : Carousel(slide), U64, U64, Html(msg) -> Html(msg)
slide_view = |carousel, index, count, content| {
    slides_per_view = carousel.slides_per_view.to_f64()
    start = view_start(carousel)
    width = ("width", "${(100.0 / slides_per_view).to_str()}%")
    shown = in_window(index, start, slides_per_view)
    # While a drag runs the slides take no pointer events, so the release
    # lands beside them. The click that follows goes to what the press and
    # the release have in common, the carousel, and never reaches a button
    # or a link in the slide the drag started on.
    passive =
        match carousel.drag {
            Dragging(_) => [("pointer-events", "none")]
            Resting | Pressed(_) => []
        }
    layout =
        match carousel.transition {
            Slide => [Attribute.class("carousel-slide"), Attribute.style([width].concat(passive))]
            Fade => {
                class = if shown "carousel-slide carousel-slide--fade carousel-slide--active" else "carousel-slide carousel-slide--fade"
                # Each slide sits one slot to the right of the one before, and
                # the slot at the start of the view is at 0. Only opacity
                # animates, so the slides snap to their slots while they
                # cross-fade.
                offset = (index.to_f64() - start) * 100.0
                [Attribute.class(class), Attribute.style([width, ("transform", "translateX(${offset.to_str()}%)")].concat(passive))]
            }
        }
    name = carousel.slide_label.replace_each("{number}", (index + 1).to_str()).replace_each("{count}", count.to_str())
    Html.div(
        layout.concat(
            [
                Attribute.role("group"),
                Attribute.aria("roledescription", "slide"),
                Attribute.aria("label", name),
                Attribute.boolean("inert", !shown),
            ],
        ),
        [content],
    )
}

## Whether a slide shows, a partly shown one included, in a view that starts
## `start` slides in and is `slides_per_view` slides wide.
in_window : U64, F64, F64 -> Bool
in_window = |index, start, slides_per_view| {
    slot = index.to_f64()
    slot + 1.0 > start and slot < start + slides_per_view
}

track_transform : Carousel(slide) -> Str
track_transform = |carousel| {
    slide_width = 100.0 / carousel.slides_per_view.to_f64()
    shift = 0.0 - view_start(carousel) * slide_width
    match carousel.drag {
        Dragging(drag) => "translate3d(calc(${shift.to_str()}% + ${drag.offset_px.to_str()}px), 0, 0)"
        Resting | Pressed(_) => "translate3d(${shift.to_str()}%, 0, 0)"
    }
}

## The track follows the pointer without delay while a drag runs, takes its
## new slot at once after a wrap that jumps, and animates to its slot
## otherwise.
track_transition : Carousel(slide) -> Str
track_transition = |carousel|
    match carousel.drag {
        Dragging(_) => "none"
        Resting | Pressed(_) => if carousel.instant "none" else "transform ${carousel.duration_ms.to_str()}ms ease-out"
    }

# ============================================================================
# Tests
# ============================================================================

letters : List(Str)
letters = ["A", "B", "C"]

abc : Carousel(Str)
abc = Carousel.new({ id: "abc", slides: letters, label: Labelled("Letters") })

render : Carousel(Str) -> Str
render = |carousel| Html.render(carousel.view(|letter, index| Html.text("${letter}${index.to_str()}"), |event| event))

press : F64 -> Carousel.Event
press = |x| { action: PointerDown({ x, button: 0 }) }

move_to : F64 -> Carousel.Event
move_to = |x| { action: PointerMove(x) }

release : Carousel.Event
release = { action: PointerUp }

drag_by : Carousel(Str), F64 -> Carousel(Str)
drag_by = |carousel, dx| carousel.update(press(200.0)).update(move_to(200.0 + dx))

is_resting : Carousel(Str) -> Bool
is_resting = |carousel|
    match carousel.drag {
        Resting => Bool.True
        Pressed(_) | Dragging(_) => Bool.False
    }

two_per_view : SlidesPerView
two_per_view = SlidesPerView.from_f64(2.0) ?? SlidesPerView.one

# Four slides, two at a time: the view goes as far as the third slide.
panes : Carousel(Str)
panes = Carousel.new({ id: "panes", slides: ["A", "B", "C", "D"], label: Labelled("Panes"), slides_per_view: two_per_view })

# --- new ---

expect abc.active_index() == 0 and abc.slides() == letters and abc.slide_count() == 3 and is_resting(abc)

expect {
    empty = Carousel.new({ id: "empty", slides: [], label: Labelled("Empty") })
    empty.active_index() == 0 and empty.slide_count() == 0 and !empty.has_previous() and !empty.has_next()
}

# --- stepping ---

expect abc.update(Carousel.next).active_index() == 1

expect abc.update(Carousel.next).update(Carousel.previous).active_index() == 0

expect {
    # Stop: the last slide stays the last.
    last = abc.update(Carousel.go_to(2))
    last.update(Carousel.next).active_index() == 2 and !last.has_next() and last.has_previous()
}

expect {
    # Stop: the first slide stays the first.
    abc.update(Carousel.previous).active_index() == 0 and !abc.has_previous() and abc.has_next()
}

expect {
    wrapping = Carousel.new({ id: "abc", slides: letters, label: Labelled("Letters"), at_ends: Wrap })
    wrapping.update(Carousel.previous).active_index() == 2
    and wrapping.update(Carousel.go_to(2)).update(Carousel.next).active_index() == 0
    and wrapping.has_previous()
    and wrapping.update(Carousel.go_to(2)).has_next()
}

expect {
    # A single slide has nothing to wrap to.
    single = Carousel.new({ id: "single", slides: ["A"], label: Labelled("Single"), at_ends: Wrap })
    single.update(Carousel.next).active_index() == 0 and !single.has_next() and !single.has_previous()
}

expect {
    # Nothing moves in an empty carousel, whatever the event.
    empty = Carousel.new({ id: "empty", slides: [], label: Labelled("Empty"), at_ends: Wrap })
    empty.update(Carousel.next).active_index() == 0 and empty.update(Carousel.previous).active_index() == 0 and empty.update(Carousel.go_to(0)).active_index() == 0
}

expect abc.update(Carousel.go_to(2)).active_index() == 2

expect abc.update(Carousel.go_to(1)).update(Carousel.go_to(3)).active_index() == 1

# --- several slides per view ---

expect {
    # The view stops once the last slide is fully in it.
    at_end = panes.update(Carousel.next).update(Carousel.next)
    at_end.active_index() == 2 and !at_end.has_next() and at_end.update(Carousel.next).active_index() == 2
}

expect {
    # Going to a slide past that point goes as far as the view goes, which
    # brings the slide into view.
    panes.update(Carousel.go_to(3)).active_index() == 2 and panes.update(Carousel.go_to(4)).active_index() == 0
}

expect {
    # A wrap back from the start goes to the end of the view.
    wrapping = Carousel.new({ id: "panes", slides: ["A", "B", "C", "D"], label: Labelled("Panes"), slides_per_view: two_per_view, at_ends: Wrap })
    wrapping.update(Carousel.previous).active_index() == 2 and wrapping.update(Carousel.go_to(2)).update(Carousel.next).active_index() == 0
}

expect {
    # Slides that all fit in view leave nowhere to go, wrapping or not.
    pair = Carousel.new({ id: "pair", slides: ["A", "B"], label: Labelled("Pair"), slides_per_view: two_per_view, at_ends: Wrap })
    !pair.has_next() and !pair.has_previous() and pair.update(Carousel.next).active_index() == 0
}

expect {
    # Shrinking the slides pulls the view back to where it ends.
    panes.update(Carousel.go_to(2)).set_slides(["A", "B", "C"]).active_index() == 1
}

expect {
    # The last view of four slides two at a time shows the third and fourth.
    html = render(panes.update(Carousel.go_to(2)))
    html.contains("translate3d(-100%, 0, 0)")
    and html.contains("aria-label=\"2 / 4\" inert>B1")
    and html.contains("aria-label=\"3 / 4\">C2")
    and html.contains("aria-label=\"4 / 4\">D3")
}

expect {
    # One and a half per view: the last step brings the last slide fully in,
    # with half of the one before it.
    one_and_a_half = SlidesPerView.from_f64(1.5) ?? SlidesPerView.one
    carousel = Carousel.new({ id: "abc", slides: letters, label: Labelled("Letters"), slides_per_view: one_and_a_half })
    at_end = carousel.update(Carousel.next).update(Carousel.next)
    html = render(at_end)
    at_end.active_index() == 2
    and !at_end.has_next()
    and html.contains("aria-label=\"1 / 3\" inert>A0")
    and html.contains("aria-label=\"2 / 3\">B1")
    and html.contains("aria-label=\"3 / 3\">C2")
}

expect {
    # Fade lays the last view out the same way.
    fading = Carousel.new({ id: "panes", slides: ["A", "B", "C", "D"], label: Labelled("Panes"), slides_per_view: two_per_view, transition: Fade })
    html = render(fading.update(Carousel.go_to(3)))
    html.contains("style=\"width: 50%; transform: translateX(0%)\" role=\"group\" aria-roledescription=\"slide\" aria-label=\"3 / 4\">C2")
    and html.contains("style=\"width: 50%; transform: translateX(100%)\" role=\"group\" aria-roledescription=\"slide\" aria-label=\"4 / 4\">D3")
}

# --- dragging ---

expect {
    dragging = drag_by(abc, -30.0)
    match dragging.drag {
        Dragging(drag) => drag.offset_px < -29.9 and drag.offset_px > -30.1
        Resting | Pressed(_) => Bool.False
    }
}

expect {
    # A move without a press is hover, not a drag.
    is_resting(abc.update(move_to(10.0)))
}

expect {
    # Only the primary button drags.
    is_resting(abc.update({ action: PointerDown({ x: 200.0, button: 2 }) }).update(move_to(100.0)))
}

expect {
    # A press is not a drag until it moves, so the track keeps animating.
    pressed = abc.update(Carousel.next).update(press(200.0)).update(move_to(204.0))
    render(pressed).contains("translate3d(-100%, 0, 0); transition: transform 300ms ease-out")
}

expect {
    # A press that does not move is a click, which changes nothing.
    clicked = abc.update(press(200.0)).update(release)
    clicked.active_index() == 0 and is_resting(clicked)
}

expect {
    # Once a press moves, the slides stop taking pointer events until the
    # drag ends, and only then.
    !render(abc.update(press(200.0))).contains("pointer-events")
    and render(drag_by(abc, -6.0)).contains("style=\"width: 100%; pointer-events: none\"")
    and !render(drag_by(abc, -80.0).update(release)).contains("pointer-events")
}

expect {
    # A threshold below the distance a drag starts at still decides.
    touchy = Carousel.new({ id: "touchy", slides: letters, label: Labelled("Letters"), drag_threshold_px: 2 })
    drag_by(touchy, -3.0).update(release).active_index() == 1
}

expect {
    released = drag_by(abc, -51.0).update(release)
    released.active_index() == 1 and is_resting(released)
}

expect {
    # Exactly the threshold is not past it.
    released = drag_by(abc, -50.0).update(release)
    released.active_index() == 0 and is_resting(released)
}

expect drag_by(abc.update(Carousel.go_to(1)), 51.0).update(release).active_index() == 0

expect drag_by(abc.update(Carousel.go_to(1)), 50.0).update(release).active_index() == 1

expect {
    far = Carousel.new({ id: "far", slides: letters, label: Labelled("Letters"), drag_threshold_px: 100 })
    drag_by(far, -99.0).update(release).active_index() == 0 and drag_by(far, -101.0).update(release).active_index() == 1
}

expect {
    # Leaving the carousel ends the drag like a release.
    left = drag_by(abc, -80.0).update({ action: PointerLeave })
    left.active_index() == 1 and is_resting(left)
}

expect {
    # A cancelled gesture ends the drag without changing the slide.
    cancelled = drag_by(abc, -80.0).update({ action: PointerCancel })
    cancelled.active_index() == 0 and is_resting(cancelled)
}

expect {
    # The browser's own drag of an image changes nothing.
    dragging = drag_by(abc, -80.0)
    dragging.update({ action: NativeDragStart }).update(release).active_index() == 1
}

expect drag_by(abc, 80.0).update(release).active_index() == 0

expect drag_by(abc.update(Carousel.go_to(2)), -80.0).update(release).active_index() == 2

expect {
    wrapping = Carousel.new({ id: "abc", slides: letters, label: Labelled("Letters"), at_ends: Wrap })
    drag_by(wrapping, 80.0).update(release).active_index() == 2
}

# --- set_slides ---

expect abc.update(Carousel.go_to(1)).set_slides(["A", "B", "C", "D"]).active_index() == 1

expect {
    shrunk = abc.update(Carousel.go_to(2)).set_slides(["A", "B"])
    shrunk.active_index() == 1 and shrunk.slides() == ["A", "B"]
}

expect abc.update(Carousel.go_to(2)).set_slides([]).active_index() == 0

expect Carousel.new({ id: "later", slides: [], label: Labelled("Later") }).set_slides(letters).update(Carousel.next).active_index() == 1

# --- view ---

expect {
    html = render(abc)
    html.starts_with("<div id=\"abc\" class=\"carousel\" role=\"region\" aria-roledescription=\"carousel\" aria-label=\"Letters\">")
}

expect {
    grouped = Carousel.new({ id: "abc", slides: letters, label: LabelledBy("letters-heading"), role: Group })
    render(grouped).contains("role=\"group\" aria-roledescription=\"carousel\" aria-labelledby=\"letters-heading\">")
}

expect {
    # The slides sit in a polite live region that the buttons control.
    render(abc).contains("<div id=\"abc-slides\" aria-live=\"polite\" aria-atomic=\"false\" class=\"carousel-wrapper\"")
}

expect {
    # Every slide is a labelled group, and render_slide gets its index.
    html = render(abc)
    html.contains("aria-roledescription=\"slide\" aria-label=\"1 / 3\">A0</div>")
    and html.contains("aria-label=\"3 / 3\" inert>C2</div>")
}

expect {
    # The slide labels are in the page's language.
    swedish = Carousel.new({ id: "abc", slides: letters, label: Labelled("Bokstäver"), slide_label: "Bild {number} av {count}" })
    render(swedish).contains("aria-label=\"Bild 2 av 3\" inert>B1</div>")
}

expect {
    # Only the slides in view are reachable.
    html = render(abc.update(Carousel.next))
    html.contains("aria-label=\"1 / 3\" inert>A0")
    and html.contains("aria-label=\"2 / 3\">B1")
    and html.contains("aria-label=\"3 / 3\" inert>C2")
}

expect {
    # Two per view: the active slide and the next one show.
    html = render(Carousel.new({ id: "abc", slides: letters, label: Labelled("Letters"), slides_per_view: two_per_view }))
    html.contains("width: 50%")
    and html.contains("aria-label=\"1 / 3\">A0")
    and html.contains("aria-label=\"2 / 3\">B1")
    and html.contains("aria-label=\"3 / 3\" inert>C2")
}

expect render(abc).contains("style=\"transform: translate3d(0%, 0, 0); transition: transform 300ms ease-out\"")

expect render(abc.update(Carousel.go_to(2))).contains("transform: translate3d(-200%, 0, 0)")

expect {
    # While dragging the track follows the pointer and does not animate.
    html = render(drag_by(abc.update(Carousel.next), -40.0))
    html.contains("transform: translate3d(calc(-100% + -40px), 0, 0); transition: none")
}

expect render(Carousel.new({ id: "abc", slides: letters, label: Labelled("Letters"), duration_ms: 500 })).contains("transition: transform 500ms ease-out")

expect {
    fading = Carousel.new({ id: "abc", slides: letters, label: Labelled("Letters"), transition: Fade, duration_ms: 400 })
    html = render(fading.update(Carousel.next))
    html.contains("class=\"carousel-wrapper carousel-wrapper--fade\" style=\"--carousel-fade-duration: 400ms\"")
    and html.contains("class=\"carousel-slide carousel-slide--fade\" style=\"width: 100%; transform: translateX(-100%)\"")
    and html.contains("class=\"carousel-slide carousel-slide--fade carousel-slide--active\" style=\"width: 100%; transform: translateX(0%)\"")
    and html.contains("transform: translateX(100%)\" role=\"group\" aria-roledescription=\"slide\" aria-label=\"3 / 3\" inert>")
}

expect {
    # No buttons unless asked for.
    !render(abc).contains("<button")
}

expect {
    # A button that would change nothing stays focusable, marked aria-disabled.
    buttons = Carousel.new({ id: "abc", slides: letters, label: Labelled("Letters"), navigation: Buttons({ previous: "Föregående", next: "Nästa" }) })
    first = render(buttons)
    last = render(buttons.update(Carousel.go_to(2)))
    first.contains("<button class=\"carousel-button-prev carousel-button-disabled\" type=\"button\" aria-label=\"Föregående\" aria-controls=\"abc-slides\" aria-disabled=\"true\"></button>")
    and first.contains("<button class=\"carousel-button-next\" type=\"button\" aria-label=\"Nästa\" aria-controls=\"abc-slides\"></button>")
    and last.contains("<button class=\"carousel-button-prev\" type=\"button\" aria-label=\"Föregående\" aria-controls=\"abc-slides\"></button>")
    and last.contains("<button class=\"carousel-button-next carousel-button-disabled\" type=\"button\" aria-label=\"Nästa\" aria-controls=\"abc-slides\" aria-disabled=\"true\"></button>")
    and !first.contains(" disabled")
}

expect {
    # A wrapping carousel never disables its buttons.
    wrapping = Carousel.new({ id: "abc", slides: letters, label: Labelled("Letters"), at_ends: Wrap, navigation: Buttons({ previous: "Back", next: "Forward" }) })
    !render(wrapping).contains("disabled")
}

expect {
    # An empty carousel renders an empty track.
    html = render(Carousel.new({ id: "empty", slides: [], label: Labelled("Empty") }))
    html.contains("class=\"carousel-wrapper\" style=\"transform: translate3d(0%, 0, 0); transition: transform 300ms ease-out\"></div>")
}

# --- wraps ---

jumping : Carousel(Str)
jumping = Carousel.new({ id: "abc", slides: letters, label: Labelled("Letters"), at_ends: Wrap, wraps: Jump })

expect {
    # By default a wrap slides back across the track like any step.
    wrapping = Carousel.new({ id: "abc", slides: letters, label: Labelled("Letters"), at_ends: Wrap })
    render(wrapping.update(Carousel.previous)).contains("translate3d(-200%, 0, 0); transition: transform 300ms ease-out")
}

expect {
    # Jump: wrapping back from the first slide puts the last one in place at once.
    wrapped = jumping.update(Carousel.previous)
    wrapped.active_index() == 2 and render(wrapped).contains("translate3d(-200%, 0, 0); transition: none")
}

expect {
    # The same forward, from the last slide to the first.
    render(jumping.update(Carousel.go_to(2)).update(Carousel.next)).contains("translate3d(0%, 0, 0); transition: none")
}

expect {
    # Steps between neighbours still slide, the one right after a jump too.
    render(jumping.update(Carousel.next)).contains("translate3d(-100%, 0, 0); transition: transform 300ms ease-out")
    and render(jumping.update(Carousel.previous).update(Carousel.previous)).contains("translate3d(-100%, 0, 0); transition: transform 300ms ease-out")
}

expect {
    # A swipe past the end jumps the same way.
    render(drag_by(jumping, 80.0).update(release)).contains("translate3d(-200%, 0, 0); transition: none")
}

expect {
    # A drag too short to change the slide slides back, also right after a jump.
    render(drag_by(jumping.update(Carousel.previous), 10.0).update(release)).contains("translate3d(-200%, 0, 0); transition: transform 300ms ease-out")
}

expect {
    # With two slides a wrap is a step to the neighbour, and slides.
    pair = Carousel.new({ id: "pair", slides: ["A", "B"], label: Labelled("Pair"), at_ends: Wrap, wraps: Jump })
    render(pair.update(Carousel.previous)).contains("translate3d(-100%, 0, 0); transition: transform 300ms ease-out")
}

expect {
    # Going to a slide slides, however far away it is.
    render(jumping.update(Carousel.previous).update(Carousel.go_to(0))).contains("translate3d(0%, 0, 0); transition: transform 300ms ease-out")
}
