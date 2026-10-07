app [main!] {
    pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
    playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.11.0/38uFJQMuEgrPoPLEDxQ4cwJwFLuYT8eTaVCY1jSxCLaW.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import playwright.Playwright

## Test: The carousel and its slides carry the WAI-ARIA carousel pattern's
## roles and names, the slides sit in a polite live region, the slides out of
## view are inert, the buttons at the ends are marked aria-disabled, and the
## buttons work from the keyboard without losing the focus at the end.
main! = |_args| {
    # The test server is started once by tests.roc, which passes its address here.
    base_url = Env.var_str!(OsStr.from_str("CAROUSEL_TEST_URL")).ok_or("http://127.0.0.1:9000")
    { browser, page } = Playwright.launch_page!({ new: Cmd.new_str, spawn!: Cmd.spawn! }, Chromium(DefaultChannel))?

    Playwright.navigate!(page, base_url)?
    Playwright.wait_for!(page, "#games", Visible)?

    # A carousel is a region unless the app asks for a group, and always has
    # a name, its own or a visible heading's.
    expect_count!(page, "#looped[role='region'][aria-roledescription='carousel'][aria-label='Loops']", 1)?
    expect_count!(page, "#games[role='group'][aria-roledescription='carousel'][aria-label='Games']", 1)?
    expect_count!(page, "#drinks[role='region'][aria-labelledby='drinks-heading']", 1)?

    # The slides sit in a polite live region, which the buttons control.
    expect_count!(page, "#games-slides[aria-live='polite']", 1)?
    expect_count!(page, "#games .carousel-button-next[aria-controls='games-slides']", 1)?

    # Each slide is a group named by its position, in the page's language.
    expect_count!(page, "#games [role='group'][aria-roledescription='slide'][aria-label='1 / 2']", 1)?
    expect_count!(page, "#games [role='group'][aria-roledescription='slide'][aria-label='2 / 2']", 1)?
    expect_count!(page, "#photos [role='group'][aria-roledescription='slide'][aria-label='Bild 2 av 3']", 1)?

    # Only the slide in view is reachable, and only the previous button is
    # unavailable, as an attribute and not just a look.
    expect_count!(page, "#games [aria-label='1 / 2']:not([inert])", 1)?
    expect_count!(page, "#games [aria-label='2 / 2'][inert]", 1)?
    expect_count!(page, "#games .carousel-button-prev[aria-disabled='true'][aria-label='Previous slide']", 1)?
    expect_count!(page, "#games .carousel-button-next:not([aria-disabled])[aria-label='Next slide']", 1)?

    # Enter on the focused next button steps forward.
    Playwright.key_press!(page, "#games .carousel-button-next", Enter, [])?
    Playwright.wait_for!(page, "#games [aria-label='2 / 2']:not([inert])", Visible) ? |_| EnterShouldShowTheNextSlide
    expect_count!(page, "#games [aria-label='1 / 2'][inert]", 1)?
    expect_count!(page, "#games .carousel-button-next[aria-disabled='true']", 1)?

    # The step reached the end, and the focus stayed on the button.
    focused = Playwright.evaluate!(page, "String(document.activeElement === document.querySelector('#games .carousel-button-next'))")?
    if focused != "true" {
        Err(FocusShouldStayOnTheNextButton)?
    } else {
        {}
    }

    Playwright.close!(browser)
}

## How many elements match `selector` must be `expected`.
expect_count! = |page, selector, expected|
    match Playwright.query_count!(page, selector) {
        Ok(count) if count == expected => Ok({})
        Ok(count) => Err(UnexpectedCount({ selector, count, expected }))
        Err(e) => Err(QueryFailed(selector, Str.inspect(e)))
    }
