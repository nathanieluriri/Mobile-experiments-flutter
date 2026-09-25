/// How long a document takes to read, in whole minutes.
///
/// Deliberately one constant and one division, with no clock anywhere near it,
/// so the same document always reports the same number and a golden of the
/// desk colophon can never drift.
library;

/// The reading speed the estimate assumes.
const int kWordsPerMinute = 240;

/// Whole minutes for [words], rounded up, and never negative.
///
/// Rounding up because a document that takes forty seconds is a one minute
/// read, and reporting zero minutes for something with words in it reads as a
/// bug rather than as brevity.
int readingMinutes(int words) {
  if (words <= 0) return 0;
  return (words / kWordsPerMinute).ceil();
}
