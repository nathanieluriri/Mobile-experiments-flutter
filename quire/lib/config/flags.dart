/// Choices the app is still making up its mind about.
///
/// A flag lives here only while two answers are both built and the better one
/// has not been picked yet. Once it is picked the loser goes, and so does the
/// flag: this file is a waiting room, not a settings screen.
library;

/// How the menu behind a document's three dots arrives.
enum OverflowMenuStyle {
  /// One card, oozing out of the dots on a body of goo that then hardens into
  /// the panel. The menu keeps the shape it has always had.
  oozed,

  /// Four separate pills, peeling off the dots one after another on necks
  /// that thin and let go, the way the action button's three do.
  pills,
}

/// Flip this and rebuild to compare the two.
const kOverflowMenuStyle = OverflowMenuStyle.pills;

/// How the top of a list answers a pull.
enum PullStyle {
  /// The list follows the finger and the loop sits in the gap above it, the
  /// way a list on iOS opens a space at its head.
  follow,

  /// The list stays where it is and the loop comes down over it, the way
  /// Chrome and Gmail answer a pull on Android.
  overlay,

  /// The loop is pulled out of the top edge on a neck that thins and lets go,
  /// which is the app's own material: the same goo the menu is peeled off.
  goo,
}

/// Flip this and rebuild to compare the three.
const kPullStyle = PullStyle.goo;

/// Whether the desk carries the action button.
///
/// Off while the three things it offered live somewhere better: a file comes
/// in through the folder on the search pill, a signature is drawn inside the
/// document it belongs to, and Recent is a row in the drawer. The button and
/// its goo stay in the tree because the goo is the app's own material and the
/// button is where it was worked out.
const kShowDeskFab = false;
