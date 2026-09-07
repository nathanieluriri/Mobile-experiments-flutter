# Gooey FAB

A chat list with a floating action button that splits into two more buttons.

Tap it and a video call button and a voice call button stretch out of it like
liquid: a neck pulls, thins, and pinches off into its own circle. The circles go
into one layer that is blurred and then run through a colour matrix whose alpha
row snaps the edges back to hard. Blurring smears overlapping circles into each
other, and the threshold turns that smear into a single merging blob.

The second button leaves 60 ms after the first on a looser spring, so it
overshoots a little further. Closing reverses the order and uses a stiffer
spring, so the buttons retract instead of wobbling. While the buttons are out, a
blur behind them takes the list out of focus; tapping it, or either button,
closes everything.

## Run

    flutter pub get
    flutter run

## Tests

    flutter test

The images under `test/goldens` were rendered on Windows. Regenerate them with
`flutter test --update-goldens` before comparing on another platform.
