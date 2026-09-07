# Sticky Note Peel

A list of coloured notes with a corner you can peel. Press and hold the top-right
corner of a note and the paper folds along the line halfway between the corner
and your finger, so the flap lands exactly under your thumb whichever way you
pull. The torn-away region shows the dark ground behind the note and the flap is
the back of the paper, the note's colour darkened.

Lifting a note dims everything else and floats a row of actions underneath it.
Drag the corner over one and it lights up in its own colour; let go and the note
travels into it and shrinks away, and the list springs closed over the gap.

## Writing a note

The pencil opens a blank sheet: pick the paper, give it a title, then write
either a note or a list, one item per line. Naming a list on the sheet files the
note under it. Saved notes go to the top and are kept on the device, so they are
still there next time.

## Finding a note

The menu slides in a panel holding every list, each one a small sheet in the
colour of the notes inside it, with a count. Picking one narrows the page to it
and renames the heading; the notes that no longer belong close their own slots
and the rest slide up.

The magnifier reaches across the header and turns into a field. The list narrows
as you type, and every word it found is struck through with a marker on the note
itself.

## Run

    flutter pub get
    flutter run

## Tests

    flutter test

The images under `test/goldens` were rendered on Windows. Regenerate them with
`flutter test --update-goldens` before comparing on another platform.
