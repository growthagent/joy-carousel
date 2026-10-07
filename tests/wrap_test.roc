app [main!] {
    pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
    playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.11.0/38uFJQMuEgrPoPLEDxQ4cwJwFLuYT8eTaVCY1jSxCLaW.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import playwright.Playwright

## Test: A carousel with `at_ends: Wrap` steps from the first slide back to
## the last and from the last on to the first, and never disables a button.
main! = |_args| {
    # The test server is started once by tests.roc, which passes its address here.
    base_url = Env.var_str!(OsStr.from_str("CAROUSEL_TEST_URL")).ok_or("http://127.0.0.1:9000")
    { browser, page } = Playwright.launch_page!({ new: Cmd.new_str, spawn!: Cmd.spawn! }, Chromium(DefaultChannel))?

    Playwright.navigate!(page, base_url)?
    Playwright.wait_for!(page, "#looped [aria-label='1 / 3']:not([inert])", Visible)?

    disabled = Playwright.query_count!(page, "#looped button[aria-disabled]")?
    if disabled != 0 { Err(WrappingButtonsShouldNeverBeDisabled(disabled))? } else { {} }

    Playwright.click!(page, "#looped .carousel-button-prev")?
    Playwright.wait_for!(page, "#looped [aria-label='3 / 3']:not([inert])", Visible) ? |_| PrevShouldWrapToTheLastSlide

    Playwright.click!(page, "#looped .carousel-button-next")?
    Playwright.wait_for!(page, "#looped [aria-label='1 / 3']:not([inert])", Visible) ? |_| NextShouldWrapToTheFirstSlide

    Playwright.close!(browser)
}
