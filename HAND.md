# H&nd

H&nd lets you work on HoneyWorld staff PCs, and on your own PCs, from wherever you are. It's built on RustDesk and runs over your private Tailscale network, so there's no server to rent.

## The two installers

Both are published on the **hand-nightly** release after every build.

| File | Install it on | What it does |
|---|---|---|
| `Hand-Install.exe` | Your own PCs | Normal install. Opens the People page. |
| `Hand-Staff-Install.exe` | Staff PCs | Asks for the person's name, joins Tailscale as a staff PC, installs H&nd, keeps the PC awake on mains power. One Windows prompt. |

Windows SmartScreen warns about both until the installers are code-signed. Click **More info → Run anyway**.

## Your side (People page)

- **Needs a hand** (yellow, top): staff who asked for help, with their note. A Windows notification also pops up, even if H&nd's window is closed.
- **Staff**: every staff PC, online or offline.
  - **Take over**: connect immediately. No popup on their side.
  - **Ask to help**: they get an Accept popup first.
- **My PCs**: your own Windows PCs. **Open** connects immediately.
- Rename anyone: hover the name and click the pencil, or double-click the name. Names stay on your PC.
- **Connect to address** (top right): type a Tailscale address to connect directly.

Inside a remote window:
- Drag any edge or corner. The window keeps the other screen's shape. If the other PC has two monitors, each gets its own window.
- **Pointer** button: they see your pointer with a fading purple trail, and your clicks don't touch their PC. Press it again to take control back.
- **Mic** button: starts a call, then mutes or unmutes your mic.
- **Speaker** button: mutes or unmutes them.
- Copy and paste text and files between the two PCs as usual.

## Staff side

- **Ask for a hand**: an optional note, then one click. They can cancel it.
- While you're on their PC, a small **Connected** bar shows in the corner, with:
  - **Take back control**: pauses your mouse and keyboard.
  - **End**: closes the session.

## One-time setup (already done once)

1. **Tailscale access rules** (login.tailscale.com → Access controls): your devices reach everything. Staff PCs can only send help requests to your devices on TCP 21120, and can't reach each other.
2. **Tailscale auth key** (Settings → Keys): Reusable, Pre-approved, tag `tag:hand-host`, 90 days.
3. **GitHub secrets** (repo Settings → Secrets → Actions):
   - `HAND_TS_AUTHKEY`: the Tailscale key
   - `HAND_FLEET_PASSWORD`: the take-over password, built into every install

## Every 90 days

The Tailscale key expires. Staff PCs that are already installed keep working, but new staff installs fail with "Could not join the company network".
1. Generate a new key with the same settings.
2. Update `HAND_TS_AUTHKEY` in GitHub secrets.
3. **Actions → H&nd Windows build → Run workflow**.

## If something goes wrong

- **Staff setup failed:** the setup screen names a `setup.log` file. Ask the staff member to send it.
- **A staff PC shows offline:** it's off, asleep on battery, or Tailscale was signed out. Open Tailscale on that PC.
- **No help notifications:** H&nd must be installed (not just run) on your PC, because the notifier runs from the H&nd tray icon.
