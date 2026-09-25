import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../data/arrival_lines.dart';
import '../data/library.dart';

/// The channel the phone's notices answer on.
const kArrivalNoticesChannel = MethodChannel('ng.com.uriri.quire/notices');

/// How many lines are dealt ahead for the phone to use while quire is not
/// running. A folder that fills faster than this between two runs falls back
/// to the first line.
const kArrivalLinesAhead = 48;

/// The most pages spelt out in the PDF line the phone picks for itself.
const kArrivalCountedPages = 200;

/// Notices that a document has arrived in a folder quire was handed.
///
/// The phone looks for them on its own schedule, about every quarter of an
/// hour and whether or not quire is running, because nothing else sees a
/// download another app made: the download manager only reports its own.
/// So a notice comes a while after the file lands, never the moment it does.
///
/// quire deals the lines here, where they are tested, and hands the phone a
/// queue of them. The phone takes from the front and says, the next time it
/// is asked, how many it took.
class ArrivalNotices {
  const ArrivalNotices([this._channel = kArrivalNoticesChannel]);

  final MethodChannel _channel;

  /// Tells the phone which folders to watch and what to say, and advances
  /// [dealer] past whatever the phone said since the last time.
  ///
  /// The queue sent starts where the dealer stands, which is where the last
  /// one started too, so the phone drops from its front the lines it has
  /// already used and says how many that was.
  Future<void> watch(List<String> trees, LineDealer dealer) async {
    try {
      final used = await _channel.invokeMethod<int>('configure', {
        'trees': trees,
        'lines': dealer.ahead(kArrivalLinesAhead),
        'pdfLines': <String>[
          for (var n = 1; n <= kArrivalCountedPages; n++)
            countedArrivalLine(DocFormat.pdf, n)!,
        ],
      });
      if (used != null && used > 0) dealer.dealt += used;
    } on MissingPluginException {
      // No phone underneath, as under test.
    } on PlatformException {
      // A phone that will not schedule the check keeps the folders all the
      // same; it only goes without the notices.
    }
  }

  /// Asks for leave to post notices, which Android 13 and later ask the
  /// reader about. It is asked when a folder is first handed over, which is
  /// the moment it means something, and not when the app opens.
  Future<bool> askLeave() async {
    try {
      return await _channel.invokeMethod<bool>('askLeave') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// A seed made once for this install.
int freshDealerSeed() => math.Random.secure().nextInt(1 << 31);
