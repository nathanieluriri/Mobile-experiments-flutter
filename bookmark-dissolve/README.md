# Bookmark Dissolve

A board of bookmark cards. Close one and it frosts over for a moment, then
crumbles into three pixel tiles of itself that scatter, spin, fall and blow off
to the right. The left edge starts coming apart before the right, so the whole
card has a direction to it.

Empty the board and it runs backwards: every card blows back in and reassembles
out of its own dust, one after another.

## Run

    flutter pub get
    flutter run

## Tests

    flutter test

The images under `test/goldens` are the board's states and the keyframes of both
animations. They were rendered on Windows; regenerate them with
`flutter test --update-goldens` before comparing on another platform.
