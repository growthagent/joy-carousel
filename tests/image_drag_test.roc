app [main!] {
    pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
    playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.11.0/38uFJQMuEgrPoPLEDxQ4cwJwFLuYT8eTaVCY1jSxCLaW.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import playwright.Playwright

## Test: Dragging an image slide with the mouse changes the slide. Without
## the carousel's dragstart handler the browser starts dragging the image
## itself, cancels the pointer stream, and the swipe goes nowhere.
main! = |_args| {
    # The test server is started once by tests.roc, which passes its address here.
    base_url = Env.var_str!(OsStr.from_str("CAROUSEL_TEST_URL")).ok_or("http://127.0.0.1:9000")
    { browser, page } = Playwright.launch_page!({ new: Cmd.new_str, spawn!: Cmd.spawn! }, Chromium(DefaultChannel))?

    Playwright.navigate!(page, base_url)?
    Playwright.wait_for!(page, "#photos .carousel-button-prev.carousel-button-disabled", Visible)?

    # The image carousel sits below the fold, and a mouse press outside the
    # viewport lands nowhere.
    _ = Playwright.evaluate!(page, "document.querySelector('#photos').scrollIntoView({ block: 'center' }); 'ok'")?

    box = Playwright.bounding_box!(page, "#photos img[alt='Photo 1']")?
    center_x = box.x + (box.width / 2.0)
    center_y = box.y + (box.height / 2.0)

    Playwright.mouse_move!(page, center_x, center_y)?
    Playwright.mouse_down!(page)?
    Playwright.mouse_move_with_steps!(page, center_x - 300.0, center_y, 10)?
    Playwright.mouse_up!(page)?

    Playwright.wait_for!(page, "#photos .carousel-button-prev:not(.carousel-button-disabled)", Visible) ? |_| ImageDragShouldChangeTheSlide

    Playwright.close!(browser)
}
