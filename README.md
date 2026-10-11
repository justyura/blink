# Blink Shell for iOS
Do Blink! [Blink](https://blink.sh) is the first professional, desktop-grade terminal for iOS that leverages the support of Mosh and SSH. Thus, we can unequivocally guarantee stable connections, lightning-fast speeds, and full configurations. It can and should be your all-day-long tool.

We did not create another terminal to fix your website on the go. Blink was built as a professional grade product from the onset. We started by analyzing what the must-haves were and we ended up grounding Blink on these three concepts:
- Fast rendering: dmesg in your Unix server should be instantaneous. We can't wait even a second to render. We didn't need to reinvent the wheel to make this happen. We simply used Chromium's HTerm to ensure that rendering is perfect and fast, even with those special, tricky encodings.
- Always on: Mosh transcends SSH's variability. Mosh overcomes the unstable and intermittent connectivity that we all associate with mobile connections. You can check your Safari without fear of having to restart the SSH connection. You can flawlessly jump from home, to the train, and then the office thanks to Mosh. Blink is rock-solid connected all the way. Mosh is readily available and can be easily installed on your server. Go to https://mosh.org. 
- Fully configurable: Blink embraces Bluetooth-coupled keyboards with gusto. Some like Caps as Esc on Vim, others Caps as Ctrl on Emacs. Blink champions them all. But there's more, because we want more. You can also add your own custom themes and fonts to Blink. During your always-on sessions, you're in your zone.

But, Blink is much more. Please read on:
- You should command your terminal, not navigate it. Blink will jump you right into a friendly shell and it'll be clear to you how to roll.
- The interface is straightforward. We dumped all menus and went full screen for your terminal.
- Use swipe to move between your open connections, slide down to close them, and even pinch to zoom!
- Configure your Blink connections by adding your own Hosts and RSA Encryption keys. Everything will look familiar and you get to work, fast!
- We've incorporated SplitView, for those necessary Google searches and chats with coworkers.

For more information, please visit [Blink Shell](https://blink.sh).

# Additions: 

Blink also contains a set of shell utilities, so you can add / remove files, list them, etc.

Specifically, the commands available (as of now) are:

* cd, setenv, ls, touch, cp, rm, ln, mv, mkdir, rmdir, 
df, du, chksum, chmod, chflags, chgrp, stat, readlink, 
compress, uncompress, gzip, gunzip,
* pwd, env, printenv, date, uname, id, groups, whoami, uptime
* cat, grep, wc
* curl (includes http, https, scp, sftp...), scp, sftp
* tar 

* You can call commands individually, or use small scripts using python or lua. There is redirection (">", "<", "&>" ...), but no pipe. 

All these commands are inside the `ios_system.framework` (precompiled, for facility). If you want to edit the source (to add more commands), see: https://github.com/holzschu/ios_system. 

curl opens access to file transfers to and from your iPad (ftp, http, scp, sftp...). It uses the key management of BLINKSHELL  (the keys you created with "config"). You can also specify keys with a path:
```
curl scp://host.name.edu/filename -o filename --key $SHARED/id_rsa --pass MyPassword 
```
You can also use the scp and sftp commands:
```
scp user@host.name.edu:filename . 
sftp localFilename user@host.name.edu:~/ 
```

scp and sftp are implemented through curl, by rewriting the arguments to follow the curl syntax. Pro: lighter implementation, smaller memory cost, less likely to have function name collisions. Con: some switches might not have exactly the same meaning. 

# Environment variables

In iOS, because of sandbox restrictions, you cannot write in the `~` directory, only in `~/Documents/`, `~/Library/` and `~/tmp`. Most Unix programs assume the configuration files are in `$HOME`. 
So either you redefine `$HOME` to `~/Documents/` or you set configuration variables (using `setenv`) to some other place.

I do this in Blink, inside the `MCPSession.m` file. The following variables are defined:
```bash
setenv PATH = $PATH:~/Library/bin:~/Documents/bin
setenv PYTHONHOME = $HOME/Library/
setenv SSH_HOME = $HOME/Documents/
setenv CURL_HOME = $HOME/Documents/
setenv HGRCPATH = $HOME/Documents/.hgrc/
setenv SSL_CERT_FILE = $HOME/Documents/cacert.pem
```

If you want to change them permanently, it's probably best to edit `MCPSession.m`.

# Obtaining Blink
Blink is available now on the [AppStore](https://itunes.apple.com/app/id1156707581). Check it out!

If you would like to participate on its development, we would love to have you on board! There are two ways to collaborate with the project: you can download and build Blink yourself, or you can request an invitation to help us test future versions (on the raw branch). If you want to participate on the testing, follow and tweet us [@BlinkShell](https://twitter.com/BlinkShell) about your usage scenarios. Invitations will be sent out in waves, please be patient if you do not receive yours immediately.

Bugs should be reported here on GitHub. If you have any questions or want to make sure we do not miss on an interesting feature, please send your suggestions to our Twitter account [@BlinkShell](https://twitter.com/BlinkShell). We would love to discuss them with you! Please do not use Twitter to report bugs.

We can't wait to receive your valuable feedback. Enjoy!

## Blink Pro: voice input

This fork adds hands-free dictation on top of Blink Shell, aimed at talking to AI assistants
(Claude Code, Codex, aider, …) that run in the terminal.

- **Right Shift** on a hardware keyboard triggers voice input. Pressing any other key while
  Shift is held keeps the normal Shift+key chord, so typing is unaffected.
- Audio is transcribed by **OpenAI `gpt-4o-transcribe`** (default) or **ElevenLabs Scribe**
  and typed into the focused terminal, exactly as if you had entered it on the keyboard.
- Two trigger styles: **Push to Talk** (hold to record, release to send) or **Toggle**
  (tap to start, tap again to stop).
- Options for appending a space, pressing Enter automatically, a fixed language code and
  key terms that bias recognition.

### Setup

1. Build and install Blink Pro (see [Build](#build) below).
2. Get an OpenAI API key (or an ElevenLabs key with the *Speech to Text* permission).
3. In Blink open **Settings › Voice Input**, pick the provider, paste the key and tap *Check API Key*.
4. Press and hold right Shift, speak, release. The transcript is typed into the terminal.

The API key is stored in the iOS keychain. Audio is recorded to a temporary file and deleted
after each transcription. The implementation lives in `Blink/Voice/`.

### Keyboard power features

| Keys | What happens |
|---|---|
| ⌥F | Host jumper: lists the hosts from `~/.ssh/config` and Blink's Hosts. ⏎ jumps to that host's open session or connects with ssh (or mosh, see Settings › Blink Pro). `local` returns to a plain Blink shell. |
| ⌥J | Session jumper: a palette listing every open session by its terminal title. Type to filter, ↑↓ and ⏎ to switch, or type the session number. |
| ⌥1 … ⌥9 | Jump straight to session 1…9. |
| ⌥O | Web search bar: type a query or URL, ⏎ opens it in Safari (default) or in the built-in browser (Settings › Blink Pro › Open in Safari) (⌘L / ⌥O address bar, ⌘[ ⌘] back/forward, ⌘W closes). Inside pages: `j`/`k` scroll, `d`/`u` half page, `gg`/`G`, `f` link hints (type the label to click), `H`/`L` history, `r` reload, `o` address bar, `y` copy URL, `x` close. |
| ⌥C | Toggle the built-in browser. Hiding it keeps the page and history, so it comes back instantly. Works even while a page is hung or the address bar is focused. ⌥⇧C discards the browser (kills a stuck page), ⌘. stops loading. |
| ⌥B | Jump to the Canvas Simple app (`canvassimple://`). Canvas Simple jumps back with ⌥B via `blinkpro://`. |

On iPhone, or whenever the software keyboard is up, the smart keys bar has a 🎤 key (tap, speak, it sends
after a pause; tap again to send immediately) and a ⚡ key that opens a menu with all of the above, so everything works
by touch too.

All of these are regular Blink shortcuts, so they can be changed in Settings › Keyboard › Shortcuts.
Settings › Blink Pro holds the search engine (Google, DuckDuckGo, Bing, Kagi, Baidu or a custom
`%s` template), the browser night mode (System / Dark / Force Dark), the Vim keys toggle and
whether the host jumper connects with ssh or mosh.

### iCloud between your devices

Voice and Blink Pro settings, the API keys (iCloud Keychain), `~/.ssh/config` and `known_hosts`
sync through iCloud, so a second device picks them up after signing in with the same Apple ID.
Private keys are deliberately not synced: run `tools/sync-ssh-to-ipad.sh --device <udid>` for each
device or import them in Settings › Keys. Blink's own Hosts sync is in Settings › Hosts.

### Sync your Mac's SSH config to the device

```bash
tools/sync-ssh-to-ipad.sh            # pushes ~/.ssh/config, referenced keys and known_hosts
```

For a phone, or any install that did not come from Xcode (TestFlight), devicectl cannot write
into the app, so prepare the folder instead and AirDrop it:

```bash
tools/sync-ssh-to-ipad.sh --out ~/Desktop   # creates ~/Desktop/ssh-sync
```

Save the folder in Files under *On My iPhone › Blink Pro* (it becomes `Documents/ssh-sync`),
then run `ssh-import` inside Blink Pro and delete the folder from the Mac. With iCloud sync
on, `~/.ssh/config` and `known_hosts` arrive by themselves; only the private keys need this.

Then run `ssh-import` inside Blink Pro. It installs `~/.ssh/config` (with `IdentityFile`
rewritten to key names), imports the private keys into the Blink keychain and merges
`known_hosts`. Keys protected by a passphrase are skipped and can be imported from
Settings › Keys. Use `ssh-import --force` to replace keys that already exist.

## Build
![CI](https://github.com/blinksh/blink/workflows/CI/badge.svg)

We made a ton easier to build and install Blink yourself on your iOS devices through XCode. We provide a precompiled package with all the libraries for the master branch. Here are the steps:

0. Check `xcode-select -p` is pointing to Xcode.app (`/Applications/Xcode.app/Contents/Developer`) not command tools.

1. Run the following command:
```bash
git clone --recursive https://github.com/blinksh/blink.git && \
    cd blink && ./get_frameworks.sh && ./get_resources.sh && \
    rm -rf Blink.xcodeproj/project.xcworkspace/xcshareddata/
```

2. Change developer ids

```bash
cp template_setup.xcconfig developer_setup.xcconfig
```

edit developer_setup.xcconfig (change apple developer id etc).

3. Open the project in XCode

3a. If you want to build without iCloud, Push Notificationa and/or Keychain sharing, Before doing anything else, go into the capabilities for the project and turn off Push Notifications, iCloud, and Keychain Sharing

4. Connect the device you want to build for and select it in Product -> Destination
5. Build and run on the device

This will download Blink and the associated frameworks: `libssh2`, `OpenSSL`, `libmoshios`, `protobuf` and `ios_system`. 

Although this is the quickest method to get you up and running, if you would like to compile all libraries and resources yourself, refer to the [BUILD.md](BUILD.md) file. Please let us know if you find any issues. Blink is a complex project with multiple low level dependencies and we are still looking for ways to simplify and automate the full compilation process.

# Using Blink
Our UI is very straightforward and optimizes the experience on touch devices for the really important part, the terminal. You will jump right into a very simple shell, so you will know what to do. Here are a few more tricks:
- Type 'help' to find information at the shell.
- Use two fingers tap to create a new shell.
- Move between shells by swiping your finger.
- You can exit the session and get back to the shell to open a new connection.
- Use pinch gesture to increase or reduce size of text. You can also use Cmd+ or Cmd- if using the keyboard.
- Copy and Paste by selecting text o tapping the screen.
- Run 'config' to setup your keys. Install them to a server through ssh-copy-id.
- Ctrl and Alt modifiers at the SmartKeys bar allow for continuous presses, like in a real keyboard.
- Use 3 finger tap to menu.

# Changelog

[View all changes](CHANGELOG.md)

# Attributions
- [Mosh](https://mosh.org) was written by Keith Winstein, along with Anders Kaseorg, Quentin Smith, Richard Tibbetts, Keegan McAllister, and John Hood.
- This product includes software developed by the OpenSSL Project
for use in the OpenSSL Toolkit. (https://www.openssl.org/).
- [Libssh2](https://www.libssh2.org)
- Entypo pictograms by Bruce Daniel www.entypo.com.
