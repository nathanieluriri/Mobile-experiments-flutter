# Sticky Note Peel

A list of coloured notes with a corner you can peel. Press and hold the top-right
corner of a note and the paper folds along the line halfway between the corner
and your finger, so the flap lands exactly under your thumb whichever way you
pull. The torn-away region shows the dark ground behind the note and the flap is
the back of the paper, the note's colour darkened.

Lifting a note dims everything else and floats a row of actions underneath it.
Drag the corner over one and it lights up in its own colour; let go and the note
travels into it and shrinks away, and the list springs closed over the gap.

## Run

    flutter pub get
    flutter run

## Tests

    flutter test

The images under `test/goldens` were rendered on Windows. Regenerate them with
`flutter test --update-goldens` before comparing on another platform.
