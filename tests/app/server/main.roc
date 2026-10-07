## Static server for the browser test suite: serves the test page shell, the
## carousel CSS and the Joy client bundle (app.wasm + runtime.js, put in
## tests/app/www by tests.roc). Started once from the repo root by tests.roc,
## which passes the port in the ROC_BASIC_WEBSERVER_PORT environment variable.
app [Context, program] {
    pf: platform "https://github.com/niclas-ahden/basic-webserver/releases/download/0.18.0/DuwGgLMnPKEVKXR5KuwtZRAtgap8TSp4GTnFf8ANHtXB.tar.zst",
    http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Env
import pf.Path
import pf.Server
import http.Response

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), InvalidPort(Str)])
init! = || {
    port_str =
        match Env.var_str!("ROC_BASIC_WEBSERVER_PORT") {
            Ok(p) => p
            Err(_) =>
                match Env.var_str!("PORT") {
                    Ok(p) => p
                    Err(_) => "8000"
                }
        }
    port = U16.from_str(port_str) ? |_| InvalidPort(port_str)
    Ok({ config: Server.default_config.with_listen({ host: "127.0.0.1", port: port }), context: {} })
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str)])
respond! = |request, _context| {
    uri =
        match request.target() {
            Resource({ raw_path, .. }) => raw_path
            _ => ""
        }
    if uri == "/" {
        Ok(serve_page())
    } else if uri == "/carousel.css" {
        serve_file!("carousel.css", "text/css")
    } else if uri == "/app.wasm" {
        serve_file!("tests/app/www/app.wasm", "application/wasm")
    } else if uri == "/runtime.js" {
        serve_file!("tests/app/www/runtime.js", "application/javascript")
    } else {
        Ok(Server.respond(Response.from_status(404).with_body(Str.to_utf8("Not found"))))
    }
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64)])
shutdown! = |_reason, _context| Ok({})

serve_file! : Str, Str => Try(Server.Outcome, [ServerErr(Str)])
serve_file! = |path, content_type|
    match Path.read_bytes!(Path.utf8(path)) {
        Ok(bytes) =>
            Ok(Server.respond(
                Response.from_status(200)
                    .with_headers([{ name: "Content-Type", value: content_type }])
                    .with_body(bytes),
            ))

        Err(_) =>
            Ok(Server.respond(Response.from_status(404).with_body(Str.to_utf8("File not found"))))
    }

# The shell is a raw string rather than joy-html SSR because the mount script
# must be an inline module script, and the SSR renderer deliberately keeps
# script text inert.
page_html : Str
page_html =
    \\<!DOCTYPE html>
    \\<html lang="en">
    \\<head>
    \\  <meta charset="utf-8" />
    \\  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    \\  <title>Carousel Test</title>
    \\  <link rel="stylesheet" href="/carousel.css" />
    \\</head>
    \\<body>
    \\  <div id="root"></div>
    \\  <script type="module">
    \\    import { mount } from '/runtime.js';
    \\    window.app = await mount({ wasm: '/app.wasm', root: document.getElementById('root'), flags: '' });
    \\  </script>
    \\</body>
    \\</html>

serve_page : () -> Server.Outcome
serve_page = ||
    Server.respond(
        Response.from_status(200)
            .with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])
            .with_body(Str.to_utf8(page_html)),
    )
