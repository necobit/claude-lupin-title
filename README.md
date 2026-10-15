# lupin-title

A Claude Code mod that turns your prompts into a 70s-anime-style title call.

- **Every character you type**: a typewriter clack (plus a small explosion), and the character flashes in a card at the centre of the screen.
- **When you send the prompt**: the whole prompt fills the screen in large Mincho type, with a brass sting.
- **While Claude works**: a card counts the elapsed time and types out excuses for the wait, over an up-tempo swing loop. Excuses follow what Claude is actually doing (reading a file, running a command, searching…): an instant template first, then one written by Haiku.
- **When the answer is done**: "お待たせしました" with the total time, and the music fades out.

All sounds and music are original, synthesised by `helper/gen_sounds.py`.

## Requirements

- macOS 13 Ventura or later, on Apple Silicon or Intel (the overlay is a small AppKit helper, `helper/lupin-overlay`, shipped as a universal binary)
- Not supported on Windows or Linux: the mod then does nothing
- A Claude Code build with mods (function hooks) support

## Install

At the prompt of a Claude Code terminal session:

```
/plugin install lupin-title --marketplace necobit/claude-lupin-title
```

Answer `y` to add the marketplace, then pick a scope.

From a shell:

```
claude plugin install lupin-title --marketplace necobit/claude-lupin-title
```

## Turning it on and off

| Command | What it does |
| --- | --- |
| `/lupin off` | Stops everything and quits the helper. Nothing relaunches it until you turn it back on. |
| `/lupin on` | Turns it back on. |
| `/lupin` | Shows whether it is on. |

The setting is remembered across sessions.

## How it works

The mod (`hooks/register.ts`) cannot draw over the whole screen, so it launches a tiny resident helper, `helper/lupin-overlay`, and talks to it over HTTP on `127.0.0.1:47391`. The helper draws a click-through overlay window and plays the sounds. It is shared by all sessions and quits after 30 idle minutes.

To rebuild the helper or the sounds yourself:

```
cd helper
swiftc -O -target arm64-apple-macos13 -o lupin-arm64 LupinOverlay.swift
swiftc -O -target x86_64-apple-macos13 -o lupin-x86_64 LupinOverlay.swift
lipo -create -output lupin-overlay lupin-arm64 lupin-x86_64
python3 gen_sounds.py ../sounds
```
