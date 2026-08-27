# AGENTS.md

## Project Shape

- SwiftPM macOS menu bar app. The runnable app is packaged manually into `dist/whistle-menubar.app`.
- Use `./script/test.sh` for tests, `./script/package_app.sh` for packaging, and `./script/run_app.sh` for local launch.
- `script/build_and_run.sh` is only a compatibility entrypoint and does not launch the app.
- Keep `README.md` concise and user-facing. Put packaging details, implementation notes, and maintenance pitfalls in `AGENTS.md` instead.

## Resource Packaging Pitfalls

- Avoid direct `Bundle.module` access on app startup for `WhistleMenuBarApp` resources unless `script/package_app.sh` also copies the generated `whistle-menubar_WhistleMenuBarApp.bundle`.
- SwiftPM's generated `Bundle.module` accessor calls `fatalError` if the resource bundle is missing. Local `.build` paths can mask this, while GitHub Actions release zips will crash on another machine.
- Assets copied directly into `Contents/Resources` should be loaded through `Bundle.main`, as `StatusBarIconTemplate.png` does in `StatusBarController`.
- Keep `L10n` resolving packaged `WhistleMenuBarCore` bundles before falling back to `Bundle.module`; commit `7a25ac3` fixed this once already.

## Release Checks

- Releases are triggered by `v*` tags (for example `v0.4.0`) and currently publish Apple Silicon / arm64 builds only.
- Do not trust a local `dist` launch alone. Temporarily hide `.build/arm64-apple-macosx/release/whistle-menubar_WhistleMenuBarApp.bundle`, open `dist/whistle-menubar.app`, and confirm the process stays alive.
- Release artifacts are currently ad-hoc signed by default (`SIGN_IDENTITY=-`). Gatekeeper/manual allow behavior is separate from startup crashes.
- Regenerate icon outputs with `./script/generate_icons.sh` when SVG sources change, and keep the generated PNG/ICNS committed.
