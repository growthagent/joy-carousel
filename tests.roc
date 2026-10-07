#!/usr/bin/env roc
## Runs everything the package has to prove beyond `roc check` and `roc test`:
##
## 1. The probe app (tests/probes/carousel_probe.roc), which uses the
##    package from outside, the way an app does, and renders the view
##    through joy-html.
## 2. The browser suite. The test app (tests/app) is built to wasm against the
##    Joy platform, the test server is started, and every tests/*_test.roc
##    drives the page in Chromium through roc-playwright.
##
## The probe and the server run through `roc` rather than as binaries built
## first, the way Joy runs its own, so no path has to name a Windows `.exe`.
##
## Run from the repository root with `roc` and `playwright` in place. CI runs
## this via `nix develop -c ./tests.roc`. Accepts a filename pattern
## (substring) and --fail-fast, e.g. `./tests.roc drag`.
##
## Optional env: ROC_OPT (default speed), ROC_SPEC_MAX_WORKERS (default 4),
## CAROUSEL_TEST_PORT (default 9000).
app [main!] {
    pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
    spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.0/9ThTkhd7zrviwQpM3LvGd7pvzGhr4ZXNmWJV7pTJc9AJ.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.Http
import pf.OsStr
import pf.Path
import pf.Sleep
import pf.Stderr
import pf.Stdout
import pf.Utc
import spec.Spec
import spec.Wait

client_main = "tests/app/client/main.roc"
client_www = "tests/app/www"
client_wasm = "${client_www}/app.wasm"
client_runtime = "${client_www}/runtime.js"
server_main = "tests/app/server/main.roc"

main! : List(OsStr) => Try({}, _)
main! = |os_args| {
    args = os_args.map(|a| OsStr.display(a))
    pattern = args.keep_if(|a| !a.starts_with("--")).first().ok_or("")
    fail_fast = args.contains("--fail-fast")
    opt = env_or!("ROC_OPT", "speed")

    # A filtered run is someone iterating on a browser spec, so skip the probes.
    if pattern == "" {
        run_probe!("tests/probes/carousel_probe.roc", opt)?
    }

    build_test_app!(opt)?

    port = env_or!("CAROUSEL_TEST_PORT", "9000")
    url = "http://127.0.0.1:${port}"

    # Anything already answering here would pass the readiness check below in
    # the new server's place, and the specs would run against it instead.
    probe = { max_attempts: 1, delay_ms: 0, request_timeout_ms: 1_000, headers: [] }
    if Wait.for_server!({ http_send!: Http.send!, sleep!: Sleep.millis! }, url, probe).is_ok() {
        Stderr.line!("error: something is already listening on ${url}, set CAROUSEL_TEST_PORT to a free port")?
        Err(PortInUse(url))?
    }

    # The server is stateless (all carousel state lives in the page and every
    # spec navigates fresh), so one instance serves every worker. Leashed, so
    # it dies with this script however the run ends, and takes the server roc
    # runs down with it.
    server = Cmd.new_str("roc")
        .args_str(["--opt=${opt}", server_main])
        .env_str("ROC_BASIC_WEBSERVER_PORT", port)
        .spawn_leashed!() ? |e| ServerSpawnFailed(e)

    # roc compiles the server before it starts, so this allows a minute.
    Wait.for_server!(
        { http_send!: Http.send!, sleep!: Sleep.millis! },
        url,
        {
            max_attempts: 600,
            delay_ms: 100,
            request_timeout_ms: 5_000,
            headers: [],
        },
    ) ? |_| ServerNeverAnswered(url)

    workers = U16.from_str(env_or!("ROC_SPEC_MAX_WORKERS", "4")).ok_or(4)

    effects = {
        spawn_test!: |file, envs|
            Cmd.new_str("roc")
                .args_str(["--opt=${opt}", file])
                .envs_str(envs)
                .stdout(Capture)
                .stderr(Capture)
                .spawn_leashed!(),
        try_wait!: Cmd.Child.try_wait!,
        kill!: Cmd.Child.kill!,
        wait!: Cmd.Child.wait!,
        list_dir!: |dir| Path.list!(Path.utf8(dir)).map_ok(|entries| entries.map(Path.display)),
        print!: Stdout.line!,
        utc_now!: Utc.now!,
        sleep_millis!: Sleep.millis!,
    }

    results = Spec.run_filtered!(effects, "tests", {
        max_workers: workers,
        worker_envs: |_index| [("CAROUSEL_TEST_URL", url)],
        before_each!: |_index| Ok({}),
        per_test_timeout_ms: 120_000,
        quiet: Bool.True,
        fail_fast,
    }, pattern)?

    server.close!() ?? {}

    passed = results.count_if(|r| r.passed)
    total = results.len()

    Stdout.line!("")?
    Stdout.line!("${passed.to_str()}/${total.to_str()} tests passed")?

    # A pattern that matches nothing is a failure: a typo'd filter must not
    # produce a green "0/0 passed" run.
    if total == 0 {
        Stderr.line!("No tests matched the pattern '${pattern}'")?
        Err(NoTestsMatched)
    } else if passed == total {
        Ok({})
    } else {
        Err(TestsFailed)
    }
}

env_or! : Str, Str => Str
env_or! = |name, default|
    match Env.var_str!(OsStr.from_str(name)) {
        Ok(val) if val != "" => val
        _ => default
    }

## roc's cache directory, looked up the way roc looks it up.
roc_cache_dir! : () => Str
roc_cache_dir! = || {
    xdg_cache_home = env_or!("XDG_CACHE_HOME", "")
    if xdg_cache_home != "" {
        "${xdg_cache_home}/roc"
    } else if Env.platform!().os == WINDOWS {
        "${env_or!("LOCALAPPDATA", "")}/roc"
    } else {
        "${env_or!("HOME", "")}/.cache/roc"
    }
}

## The hash a Joy release URL in the app header's `pf: platform "..."` ends in,
## which is also the directory roc unpacks that release into.
joy_hash_of : Str -> Try(Str, [NoJoyRelease])
joy_hash_of = |header| {
    after_pf = header.split_first("pf: platform \"") ? |_| NoJoyRelease
    url = after_pf.after.split_first("\"") ? |_| NoJoyRelease
    file = url.before.split_last("/") ? |_| NoJoyRelease
    if url.before.starts_with("https://") and file.after.ends_with(".tar.zst") {
        Ok(file.after.drop_suffix(".tar.zst"))
    } else {
        Err(NoJoyRelease)
    }
}

expect joy_hash_of("app [Model] {\n    pf: platform \"https://github.com/a/joy/releases/download/1.0/HASH.tar.zst\",\n}") == Ok("HASH")
expect joy_hash_of("app [Model] {\n    pf: platform \"../../joy/platform/main.roc\",\n}") == Err(NoJoyRelease)
expect joy_hash_of("app [Model] {}") == Err(NoJoyRelease)

## Run a probe app. The probes print one PASS/FAIL line per check and exit
## non-zero on a failure.
run_probe! : Str, Str => Try({}, _)
run_probe! = |src, opt| {
    Stdout.line!("Running ${src}...")?
    code = Cmd.new_str("roc").args_str(["--opt=${opt}", src]).exec_exit_code!()?
    if code == 0 {
        Ok({})
    } else {
        Err(ProbeFailed(src))
    }
}

## The test app's client: compiled to wasm against the Joy platform, with
## Joy's JS runtime next to it, for the server to serve.
build_test_app! : Str => Try({}, _)
build_test_app! = |opt| {
    Stdout.line!("Building the test app...")?

    # Everything in it is a build artifact, which git ignores, so a fresh
    # checkout has no such directory and the linker cannot write into it.
    Path.utf8(client_www).create_all!() ? |e| CouldNotCreateDir(client_www, e)

    # The memory and stack flags are the ones Joy's own build.roc passes, see
    # the notes there.
    roc_build!(
        ["--opt=${opt}", "--target=wasm32", "--wasm-memory=0", "--wasm-stack-size=1048576", "--output=${client_wasm}", client_main],
        client_wasm,
    )?

    # The runtime has to be the one from the Joy release the client names. The
    # build above unpacked that release into roc's package cache, under the
    # hash its URL ends in.
    header = Path.utf8(client_main).read_utf8!() ? |_| ClientNotReadable(client_main)
    joy_hash = joy_hash_of(header) ? |_| NoJoyReleaseIn(client_main)
    joy_runtime = "${roc_cache_dir!()}/packages/${joy_hash}/www/runtime.js"
    Path.utf8(joy_runtime).copy!(Path.utf8(client_runtime)) ? |e| CouldNotCopyJoyRuntime(joy_runtime, e)
    Ok({})
}

## `roc build` exits 2 when it only found warnings and can exit 0 without
## writing anything, so the output file decides: drop it up front and require
## that it came back. A stale build must never reach the tests.
roc_build! : List(Str), Str => Try({}, _)
roc_build! = |args, out| {
    _ = Path.utf8(out).delete!()
    code = Cmd.new_str("roc").args_str(["build"].concat(args)).exec_exit_code!()?
    built = Path.utf8(out).is_file!() ?? Bool.False
    if built and (code == 0 or code == 2) {
        Ok({})
    } else {
        Stderr.line!("error: roc build failed for ${out} (exit code ${code.to_str()})")?
        Err(BuildFailed(out))
    }
}
