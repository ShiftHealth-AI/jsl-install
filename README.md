# Shift QA installer

Runs your own private copy of Shift (Join Shift Life) on a Mac, with sample families, for QA. Nothing you do in it
touches real families or sends real email.

## Install

Open **Terminal** (⌘-Space, type Terminal, Return), paste this line, press Return:

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ShiftHealth-AI/jsl-install/main/install.sh)"
```

It walks you through four steps and asks only when it needs you:

1. **Docker.** If the Mac has none, it installs OrbStack. macOS may ask for your password, and OrbStack's
   first-run window may need a click.
2. **GitHub.** You sign in in the browser. Your GitHub account needs access to Shift's private repository; ask
   Ward if it says it can't see it.
3. **Your email** (you sign in to Shift with it; nothing is sent to it) and, optionally, an AI key for drafted
   replies.
4. **Shift starts** (the first time downloads about 1 GB), sample data is added, and the browser opens at
   http://app.joinshiftlife.localhost. Sign-in codes arrive in the local inbox, http://mail.joinshiftlife.localhost.

## Later

| To | Do |
|---|---|
| Get the newest Shift | Run the same line again (your data stays) |
| Start over with fresh sample data | Run the line with ` -- --reset` added after the closing `"` |
| Stop Shift | `docker compose -p jsl-qa stop`, or quit OrbStack |

Your settings and the sign-in cheat sheet live in `~/jsl-qa` (`README.txt` there lists the sample accounts).

This repository holds only the installer: no Shift code and no secrets. Everything it downloads past step 2
needs a GitHub account with access to Shift.
