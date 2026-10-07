app [main!] {
    pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
    playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.11.0/38uFJQMuEgrPoPLEDxQ4cwJwFLuYT8eTaVCY1jSxCLaW.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import playwright.Playwright

## Test: Navigation buttons (next/prev) work correctly
## The games carousel has 2 slides (0, 1)
main! = |_args| {
    # The test server is started once by tests.roc, which passes its address here.
    base_url = Env.var_str!(OsStr.from_str("CAROUSEL_TEST_URL")).ok_or("http://127.0.0.1:9000")
    { browser, page } = Playwright.launch_page!({ new: Cmd.new_str, spawn!: Cmd.spawn! }, Chromium(DefaultChannel))?

    Playwright.navigate!(page, base_url)?

    # Verify prev button is disabled at first slide, next is enabled
    Playwright.wait_for!(page, "#games .carousel-button-prev.carousel-button-disabled", Visible)?
    Playwright.wait_for!(page, "#games .carousel-button-next:not(.carousel-button-disabled)", Visible)?

    # Click next button to go to slide 1 (last)
    Playwright.click!(page, "#games .carousel-button-next")?

    # Prev should be enabled, next should be disabled (last slide)
    Playwright.wait_for!(page, "#games .carousel-button-prev:not(.carousel-button-disabled)", Visible)?
    Playwright.wait_for!(page, "#games .carousel-button-next.carousel-button-disabled", Visible)?

    # Click prev button to go back to slide 0
    Playwright.click!(page, "#games .carousel-button-prev")?

    # Prev disabled again (first slide), next enabled
    Playwright.wait_for!(page, "#games .carousel-button-prev.carousel-button-disabled", Visible)?
    Playwright.wait_for!(page, "#games .carousel-button-next:not(.carousel-button-disabled)", Visible)?

    Playwright.close!(browser)
}
