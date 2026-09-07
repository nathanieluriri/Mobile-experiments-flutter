# Spotify Onboarding

A two step connection flow. Each step asks for one thing, explains why, and
shows an endless column of cards wrapped around an arc behind the ask: cities
on the first step, artists on the second. The cards lean, slide, and shrink the
further they sit from the middle of the screen, blur into the background as
they run off the bottom, and come to rest on a card boundary when you let go.

The flow follows whatever appearance the device is set to. On white it is
written in near black and the button is a black slab carrying a coloured label;
on black the two swap, and the button becomes a slab of that same colour
carrying a near black label.

Moving between steps is a handover rather than a cut. The step on its way out
drifts against the direction of travel and softens; the one arriving drifts in
over it out of the same softness, sharpens, and settles.

## Run

    flutter pub get
    flutter run

## Tests

    flutter test

The reference images under `test/goldens` were rendered on Windows and may
differ by a pixel on another platform.
