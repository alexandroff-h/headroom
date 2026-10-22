# Installing Headroom with a coding agent

Paste the block below into Claude Code, or any agent that can run shell commands
on your Mac. It installs Headroom from source and leaves it running.

---

```
Install Headroom on this Mac from https://github.com/alexandroff-h/headroom

Headroom is a native macOS SwiftUI app. It builds with Swift Package Manager and
needs no third-party dependencies.

Do this:

1. Check the prerequisites and tell me if either is missing rather than guessing:
   - macOS 14 or newer      (`sw_vers -productVersion`)
   - A Swift 6 toolchain    (`swift --version`). If it is absent, the Xcode
     Command Line Tools are enough: `xcode-select --install`.

2. Clone to ~/Developer/headroom (or tell me where you put it instead):
      git clone https://github.com/alexandroff-h/headroom.git ~/Developer/headroom

3. Build the app bundle:
      cd ~/Developer/headroom && bash scripts/build-app.sh
   This compiles in release, writes dist/Headroom.app, generates the icon, and
   signs it locally. It takes a minute or two on first run.

4. Verify the build rather than assuming it worked:
      bash scripts/check-compat.sh
   Expect "OK: deploys to macOS 14.0 and later." Report the output to me.

5. Run the tests:
      swift test
   Expect 67 passing. Report any failure instead of continuing past it.

6. Install and launch:
      cp -R dist/Headroom.app /Applications/
      open /Applications/Headroom.app

7. Confirm it is actually running and tell me what it cost:
      pgrep -fl Headroom
      top -pid $(pgrep -f "Headroom.app/Contents/MacOS/Headroom" | head -1) \
          -l 6 -s 2 -stats cpu | tail -4
   It should settle around 2% of one core. If it is materially higher, say so
   rather than reporting success.

Notes:
- Headroom needs no special permissions. It reads only what the kernel gives any
  process. If something asks you to grant accessibility or screen recording,
  stop and tell me, because that is not expected.
- The build is signed locally, not notarized. Gatekeeper may ask on first launch
  since it was built on this machine; that is normal for a from-source build.
- It writes one file, ~/Library/Application Support/Headroom/actions.json. There
  is no installer, no daemon, no login item. To uninstall: delete the .app, that
  JSON file, and `defaults delete design.alexandroff.headroom`.
```

---

## Doing it by hand

If you would rather not hand it to an agent, the same thing is four commands:

```sh
git clone https://github.com/alexandroff-h/headroom.git
cd headroom
bash scripts/build-app.sh
open dist/Headroom.app
```
