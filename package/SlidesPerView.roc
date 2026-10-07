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
