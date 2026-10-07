app [main!] {
    pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
    playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.11.0/38uFJQMuEgrPoPLEDxQ4cwJwFLuYT8eTaVCY1jSxCLaW.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Sleep
import playwright.Playwright

## Test: Cannot go before first slide - dragging right at slide 0 stays at 0
main! = |_args| {
    # The test server is started once by tests.roc, which passes its address here.
    base_url = Env.var_str!(OsStr.from_str("CAROUSEL_TEST_URL")).ok_or("http://127.0.0.1:9000")
    { browser, page } = Playwright.launch_page!({ new: Cmd.new_str, spawn!: Cmd.spawn! }, Chromium(DefaultChannel))?

    Playwright.navigate!(page, base_url)?

    # Start at slide 0 (prev disabled)
    Playwright.wait_for!(page, "#games .carousel-button-prev.carousel-button-disabled", Visible)?

    # Get the carousel element's bounding box for dynamic positioning
    box = Playwright.bounding_box!(page, "#games")?
    center_x = box.x + (box.width / 2.0)
    center_y = box.y + (box.height / 2.0)

    # Try to drag right (would go to slide -1 if allowed)
    Playwright.mouse_move!(page, center_x, center_y)?
    Playwright.mouse_down!(page)?
    Playwright.mouse_move_with_steps!(page, center_x + 300.0, center_y, 10)?
    Playwright.mouse_up!(page)?

    # Small delay to let any transition settle
    Sleep.millis!(500)

    # Should still be on slide 0 - can't go before first slide (prev still disabled)
    Playwright.wait_for!(page, "#games .carousel-button-prev.carousel-button-disabled", Visible)?

    Playwright.close!(browser)
}
