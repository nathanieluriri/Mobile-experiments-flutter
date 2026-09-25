# Coverdeck

An iPod-style Cover Flow player whose backdrop tints to match the focused album.

Drag the deck sideways and the covers swing through perspective, the one in
front lying flat while its neighbours recede and fade. Let go and the deck
projects your throw forward before springing onto the nearest album. Tap a
cover beside the focused one to bring it in. The backdrop is every album's
pastel wash laid end to end and sampled wherever the deck happens to be, so
the whole screen slides between two records mid drag.

Below the deck sit the album's name, a progress bar and the transport
controls. A floating dock switches between the deck, a grid of every album,
and the saved playlists; it shrinks to icons as you scroll a list and grows
again on the way back up.

## Run

    flutter pub get
    flutter run

## Tests

    flutter test

The images under `test/goldens` were rendered on Windows. Regenerate them with
`flutter test --update-goldens` before comparing on another platform.
