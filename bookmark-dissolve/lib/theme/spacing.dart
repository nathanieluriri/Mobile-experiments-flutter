/// The root size the spacing scale resolves against: the platform's own
/// default text size, not a browser's 16.
const kRem = 14.0;

/// One step of the spacing scale, a quarter of the root size. Two steps of
/// padding is `kStep * 2`, five steps is `kStep * 5`.
const kStep = kRem / 4;
