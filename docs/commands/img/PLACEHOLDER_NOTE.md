# Placeholder Images

The following PNG files are placeholders and need to be generated from VHS tape files:

## Logging Commands
- hug-la.png (from hug-la.tape)
- hug-lla.png (from hug-lla.tape)
- hug-lp.png (from hug-lp.tape)
- hug-lf.png (from hug-lf.tape)
- hug-lc.png (from hug-lc.tape)
- hug-lau.png (from hug-lau.tape)
- hug-ld.png (from hug-ld.tape)
- hug-llf.png (from hug-llf.tape)

## Branching Commands
- hug-bl.png (from hug-bl.tape)
- hug-bla.png (from hug-bla.tape)
- hug-blr.png (from hug-blr.tape)
- hug-bll.png (from hug-bll.tape)

## File Inspection Commands
- hug-fblame.png (from hug-fblame.tape)
- hug-fcon.png (from hug-fcon.tape)
- hug-fa.png (from hug-fa.tape)
- hug-fborn.png (from hug-fborn.tape)

## Working Directory Commands
- hug-w-discard.png (from hug-w-discard.tape)
- hug-w-purge.png (from hug-w-purge.tape)

## HEAD Operations Commands
- hug-h-back.png (from hug-h-back.tape)
- hug-h-undo.png (from hug-h-undo.tape)
- hug-h-files.png (from hug-h-files.png)

## To Generate Real Screenshots

Run the following command from the repository root:

```bash
make vhs
```

Or to build specific tape files:

```bash
make vhs-build-one TAPE=hug-la.tape
```

These commands will use VHS (Video Handshake) to generate actual terminal screenshots from the tape files in `docs/screencasts/`.

## Requirements

- VHS must be installed: https://github.com/charmbracelet/vhs
- Demo repository must exist: `make demo-repo`
- Hug must be installed and activated: `make install && source bin/activate`
