# Mobile experiments, Flutter version

Flutter rebuilds of the React Native experiments at [nathanieluriri/Mobile-experiments](https://github.com/nathanieluriri/Mobile-experiments): animations, gestures, and UI ideas, each one a standalone Flutter app with its own README.

| Project | What it is |
|---|---|
| [gooey-fab](gooey-fab) | A chat list with a floating action button that splits into two more buttons |
| [sticky-note-peel](sticky-note-peel) | A list of coloured notes with a corner you can peel |
| [bookmark-dissolve](bookmark-dissolve) | A board of bookmark cards that frost over and crumble into tiles of themselves when closed |
| [coverdeck](coverdeck) | An iPod-style Cover Flow player whose backdrop tints to match the focused album |
| [spotify-onboarding](spotify-onboarding) | A two step connection flow with an endless column of cards wrapped around an arc |
| [audiobook-player](audiobook-player) | An audiobook library whose mini player expands into a full player sheet |
| [crypto-wallet](crypto-wallet) | A wallet whose balance falls apart when you pull down on it, then locks back in digit by digit |

Every project runs the same way:

    flutter pub get
    flutter run

Each app ships golden tests under `test/goldens`; run them with `flutter test`.

Built with Flutter 3.44.
