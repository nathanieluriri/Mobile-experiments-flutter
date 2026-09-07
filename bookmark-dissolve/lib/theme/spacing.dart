/// The root size the source's utility classes resolve against: the platform's
/// own default text size, not a browser's 16.
const kRem = 14.0;

/// One step of the source's spacing scale, a quarter of the root size. A class
/// like `p-2` is `kStep * 2` and `px-5` is `kStep * 5`.
const kStep = kRem / 4;
