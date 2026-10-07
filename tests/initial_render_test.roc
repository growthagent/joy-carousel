app [main!] {
    pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
    playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.11.0/38uFJQMuEgrPoPLEDxQ4cwJwFLuYT8eTaVCY1jSxCLaW.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import playwright.Playwright

## Test: Initial render shows carousels with slide 0 active
main! = |_args| {
    # The test server is started once by tests.roc, which passes its address here.
    base_url = Env.var_str!(OsStr.from_str("CAROUSEL_TEST_URL")).ok_or("http://127.0.0.1:9000")
    { browser, page } = Playwright.launch_page!({ new: Cmd.new_str, spawn!: Cmd.spawn! }, Chromium(DefaultChannel))?

    Playwright.navigate!(page, base_url)?

    # Verify page title/heading renders
    Playwright.wait_for!(page, "text=Carousel Test", Visible)?

    # Verify games carousel renders
    Playwright.wait_for!(page, "#games", Visible)?
    Playwright.wait_for!(page, "text=Diablo II", Visible)?

    # Verify navigation buttons exist (test app has navigation: Bool.True)
    Playwright.wait_for!(page, "#games .carousel-button-prev", Visible)?
    Playwright.wait_for!(page, "#games .carousel-button-next", Visible)?

    # Verify prev is disabled at first slide
    Playwright.wait_for!(page, "#games .carousel-button-prev.carousel-button-disabled", Visible)?

    # Verify drinks carousel renders
    Playwright.wait_for!(page, "#drinks", Visible)?
    Playwright.wait_for!(page, "text=Whisky", Visible)?

    Playwright.close!(browser)
}
