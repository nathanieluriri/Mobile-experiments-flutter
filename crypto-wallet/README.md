# crypto_wallet

A wallet whose balance falls apart when you pull down on it. The six digits slot-machine through random characters, tint with occasional accent colours and jitter behind a blur while the new balance loads, then lock back in one at a time from left to right as the blur unwinds. Tapping the balance refreshes it too.

Receive, Send, Swap and IPO slide up as flows while the wallet scales back and dims behind them. Receive shows the address as a QR code per network. Send takes a recipient, an amount on the keypad and the asset to pay with. Swap quotes one asset against another, with the token chips arcing past each other when the direction flips. IPO Market presents one featured offering with a live demand meter, price range, allocation estimator and subscription flow.

## Run

    flutter pub get
    flutter run

Built with Flutter 3.44. Fonts and icons are bundled; nothing is fetched from the network.

## Tests

    flutter test

The golden images under `test/goldens` were rendered on Windows. On another platform they may need regenerating with `flutter test --update-goldens`.
