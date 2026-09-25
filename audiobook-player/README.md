# Audiobook Player

An audiobook library whose mini player expands into a full player sheet.

Drag the mini player up and it grows into the full player. The cover art never
swaps or crossfades: it is one view travelling from a 44 point thumbnail to
full width hero art while the tab bar slides away, the corners round off and a
blur builds up behind it. One progress value drives all of it, so wherever you
stop the drag, every part of the sheet is at the same point. A quick flick
finishes the job no matter how far you actually dragged, and a flick the other
way puts it back.

While the track is running, the unplayed part of the progress bar is a row of
dashes marching slowly to the left. Stop it and they freeze where they are.

Four tabs: Stories, with shelves of trending stories and playlists; Search;
Collection; and Playlists, with the saved playlists and a row for making a new
one. The player sits over all four.

## Run

    flutter pub get
    flutter run

## Tests

    flutter test

The images under `test/goldens` were rendered on Windows. Regenerate them with
`flutter test --update-goldens` before comparing on another platform.
