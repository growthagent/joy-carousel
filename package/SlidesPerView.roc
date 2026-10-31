## How many slides a carousel shows side by side: `1.0` fills it with one
## slide, `2.0` shows two half-width slides, `1.5` shows one slide and half of
## the next as a preview. Always a finite number above zero, so a carousel
## never divides by zero or lays its slides out at a negative width.
##
## ```
## two = SlidesPerView.from_f64(2.0)?
## carousel = Carousel.new({ id: "games", slides: games, slides_per_view: two })
## ```
SlidesPerView :: { count : F64 }.{
    ## One slide at a time, the default.
    one : SlidesPerView
    one = { count: 1.0 }

    ## `Err(NotPositive(n))` for zero, a negative number, NaN or infinity.
    from_f64 : F64 -> Try(SlidesPerView, [NotPositive(F64)])
    from_f64 = |n|
        if n > 0.0 and !n.is_infinite() {
            Ok({ count: n })
        } else {
            Err(NotPositive(n))
        }

    to_f64 : SlidesPerView -> F64
    to_f64 = |slides_per_view| slides_per_view.count

    ## Encoded, the count is its number as a string, `"1.5"`. A count is
    ## finite by construction, but the `F64` codecs the compiler derives can
    ## fail on NaN and infinity, and `Json.to_str` needs an encoder that
    ## cannot, so the count travels as text and is checked on the way in.
    parser_for : encoding -> (state -> Try({ value : SlidesPerView, rest : state }, err))
        where [
            encoding.parse_str : encoding, state -> Try({ value : Str, rest : state }, err),
            encoding.invalid_value : encoding, state -> err,
        ]
    parser_for = |encoding| {
        Encoding : encoding

        |state| {
            parsed = Encoding.parse_str(encoding, state)?

            match F64.from_str(parsed.value) {
                Ok(n) =>
                    match from_f64(n) {
                        Ok(slides_per_view) => Ok({ value: slides_per_view, rest: parsed.rest })
                        Err(_) => Err(Encoding.invalid_value(encoding, state))
                    }

                Err(_) => Err(Encoding.invalid_value(encoding, state))
            }
        }
    }

    encoder_for : encoding -> (SlidesPerView, state -> Try(state, err))
        where [
            encoding.encode_str : Str, state -> Try(state, err),
        ]
    encoder_for = |_encoding| {
        Encoding : encoding

        |slides_per_view, state| Encoding.encode_str(slides_per_view.count.to_str(), state)
    }
}

expect {
    n = SlidesPerView.one.to_f64()
    n > 0.999 and n < 1.001
}

expect
    match SlidesPerView.from_f64(1.5) {
        Ok(spv) => spv.to_f64() > 1.499 and spv.to_f64() < 1.501
        Err(_) => Bool.False
    }

expect
    match SlidesPerView.from_f64(0.0) {
        Err(NotPositive(_)) => Bool.True
        Ok(_) => Bool.False
    }

expect
    match SlidesPerView.from_f64(-1.0) {
        Err(NotPositive(_)) => Bool.True
        Ok(_) => Bool.False
    }

expect
    match SlidesPerView.from_f64(F64.nan) {
        Err(NotPositive(_)) => Bool.True
        Ok(_) => Bool.False
    }

expect
    match SlidesPerView.from_f64(F64.infinity) {
        Err(NotPositive(_)) => Bool.True
        Ok(_) => Bool.False
    }

# --- encoded ---

expect Json.to_str(SlidesPerView.from_f64(1.5) ?? SlidesPerView.one) == "\"1.5\""

expect {
    parsed : Try(SlidesPerView, _)
    parsed = Json.parse("\"1.5\"")
    match parsed {
        Ok(spv) => spv.to_f64() > 1.499 and spv.to_f64() < 1.501
        Err(_) => Bool.False
    }
}

# A count that is not positive is rejected on the way in, like in `from_f64`.
expect {
    parsed : Try(SlidesPerView, _)
    parsed = Json.parse("\"0\"")
    match parsed {
        Err(_) => Bool.True
        Ok(_) => Bool.False
    }
}

expect {
    parsed : Try(SlidesPerView, _)
    parsed = Json.parse("\"many\"")
    match parsed {
        Err(_) => Bool.True
        Ok(_) => Bool.False
    }
}
