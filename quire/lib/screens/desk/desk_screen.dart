import 'dart:math' as math;
import 'dart:ui' as ui;

import 'dart:io' show File;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../../constants/gooey_fab.dart';
import '../../data/library.dart';
import '../../pdf/writer.dart' show PdfWriteError;
import '../../services/document_store.dart';
import '../../theme/colors.dart';
import '../../theme/feedback.dart';
import '../../theme/easings.dart';
import '../../theme/metrics.dart';
import '../../theme/springs.dart';
import '../../theme/typography.dart';
import '../../widgets/gooey_fab/gooey_fab_controller.dart';
import '../../widgets/gooey_fab/gooey_fab.dart';
import '../../services/convert.dart';
import 'convert_sheet.dart';
import 'desk_colophon.dart';
import 'desk_sheet.dart';
import 'details_sheet.dart';
import 'rename_sheet.dart';
import 'desk_empty.dart';
import 'desk_top_bar.dart';
import 'destination_panel.dart';
import 'grid_body.dart';
// Named for the list it draws, under the alias that keeps it clear of the
// ListBody Flutter exports for laying children out one after another.
import 'list_body.dart' show DeskListBody;
import 'nav_drawer.dart';
import 'overflow_menu.dart';
import '../../widgets/goo_menu.dart';
import '../../painting/overflow_dots_painter.dart';
import '../../painting/overflow_goo_painter.dart';
import '../../config/flags.dart';
import 'search_pill.dart';
import 'shell_model.dart';
import 'sort_menu.dart';
import 'sort_row.dart';
import 'tab_strip.dart';
import 'undo_pill.dart';

/// Where the two lines of a search that found nothing sit.
const kNoResultsTop = 300.0;
const kNoResultsGap = 8.0;

/// How long the undo pill takes to come up off the desk.
const kUndoPillIn = Duration(milliseconds: 180);

/// The chrome above the body: the top bar, the tabs and the sort row.
const kShellChrome = kTopBarHeight + kTabStripHeight + kSortRowHeight;

/// How fast a finger has to be going for its direction to decide the drawer,
/// in points a second. Below this the drawer goes wherever it is nearest.
const kDrawerFlingVelocity = 300.0;

/// How much room the body keeps under the last row.
const kBodyBottomPadding = 96.0;

/// The desk: a top bar, the format tabs, the sort row, and the library.
///
/// The four parts are stacked and none of them scrolls under another, so the
/// only thing that moves when you scroll is the documents. A drawer comes in
/// over all four from the left, and the hamburger that opens it is a readout
/// of where it has got to rather than an animation of its own.
class DeskScreen extends StatefulWidget {
  const DeskScreen({
    super.key,
    required this.store,
    this.onOpen,
    this.onSign,
  });

  final LibraryStore store;

  /// Opening a document.
  ///
  /// The row's rect on the desk comes with it, because the reader grows out of
  /// the row rather than sliding over it, and the desk is the only thing that
  /// knows where a row has been scrolled to.
  final void Function(LibraryEntry entry, Rect cardRect)? onOpen;

  /// Taking a document to the signature pad.
  final void Function(LibraryEntry entry)? onSign;

  @override
  State<DeskScreen> createState() => _DeskScreenState();
}

class _DeskScreenState extends State<DeskScreen> with TickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _query = TextEditingController();
  final FocusNode _queryFocus = FocusNode();
  late final AnimationController _drawer;
  late final AnimationController _menu;
  late final AnimationController _overflow;
  late final AnimationController _undo;
  late final AnimationController _undoRise;

  /// Which end the drawer was last sent to, so a spring that stops inside its
  /// own tolerance can be put exactly on it. A panel resting a hundredth of a
  /// point short is a panel whose glyph is a hundredth of a degree short, and
  /// the two are only ever the same object if both land.
  bool _drawerOpen = false;

  DrawerDestination _destination = DrawerDestination.recent;
  DeskTab _tab = DeskTab.recent;
  SortField _sortField = SortField.dateModified;
  SortOrder _sortOrder = SortOrder.newToOld;
  DeskView _view = DeskView.list;
  LibraryEntry? _pill;

  /// Words on the pill instead of a removal, while they last.
  String? _notice;

  /// True while the desk is waiting for a PDF to be chosen for signing.
  bool _choosingToSign = false;

  /// The document whose overflow menu is open, and where its row was when the
  /// three dots were tapped, which is what the menu is hung off.
  LibraryEntry? _acting;
  Rect _actingRect = Rect.zero;

  /// Where the menu hangs from: the three dots, not the card behind them.
  Rect _actingMenuRect = Rect.zero;

  /// Measures the panel so the goo under it need not be told its size.
  final GlobalKey _menuKey = GlobalKey();

  /// The pills' motion, which is the action button's motion.
  ///
  /// The same controller rather than a copy of its numbers, because the
  /// numbers are not the effect. What makes the button settle is that every
  /// action rides its own spring simulation to rest, staggered by holding
  /// still and then letting go, and that a toggle mid flight carries the
  /// velocity through. Sized for every action there is; a document offering
  /// fewer leaves the rest unread.
  late final GooeyFabController _pills = GooeyFabController(
    vsync: this,
    actionCount: DeskAction.values.length,
  );

  /// Lets the layer repaint as the pills move, and puts the menu away once
  /// the last of them has come to rest on the dots.
  void _onPillsMoved() {
    if (!mounted) return;
    setState(() {});
    if (_acting != null && !_pills.isOpen && !_pillsMoving) {
      _acting = null;
    }
  }

  bool get _pillsMoving {
    bool moving(Animation<double> a) =>
        a.status == AnimationStatus.forward ||
        a.status == AnimationStatus.reverse;
    if (moving(_pills.progress)) return true;
    for (var i = 0; i < _pills.actionCount; i++) {
      if (moving(_pills.actionDrive(i))) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    // The drawer is driven by a simulation, so its duration is only what a
    // stopped controller falls back to. Its bounds are what clamp the spring's
    // overshoot, so the panel never opens past its own edge.
    _drawer = AnimationController(vsync: this, duration: kChromeIn);
    _drawer.addStatusListener((status) {
      if (status == AnimationStatus.forward ||
          status == AnimationStatus.reverse) {
        return;
      }
      final rest = _drawerOpen ? 1.0 : 0.0;
      if (_drawer.value != rest) _drawer.value = rest;
    });
    _menu = AnimationController(vsync: this, duration: kSortMenuIn);
    _overflow = AnimationController(vsync: this, duration: kOverflowOozeIn);
    _pills.animations.addListener(_onPillsMoved);
    _undo = AnimationController(vsync: this, duration: kUndoPill);
    _undo.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        widget.store.commitRemoval();
        setState(() {
          _pill = null;
          _notice = null;
        });
      }
    });
    _undoRise = AnimationController(vsync: this, duration: kUndoPillIn);
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _drawer.dispose();
    _menu.dispose();
    _overflow.dispose();
    _pills.animations.removeListener(_onPillsMoved);
    _pills.dispose();
    _undo.dispose();
    _undoRise.dispose();
    _scroll.dispose();
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  void _onStoreChanged() => setState(() {});

  // The drawer.

  double get _drawerWidth => drawerWidth(MediaQuery.sizeOf(context).width);

  void _toggleDrawer() => _settleDrawer(open: _drawer.value < 0.5, velocity: 0);

  void _dragDrawer(double delta) {
    _drawer
      ..stop()
      ..value = (_drawer.value + delta / _drawerWidth).clamp(0.0, 1.0);
  }

  void _endDrawerDrag(double velocity) {
    final open = velocity.abs() > kDrawerFlingVelocity
        ? velocity > 0
        : _drawer.value > 0.5;
    // A drag is answered where it lands rather than where it started, so a
    // drawer that springs back to where it was still says so.
    Feel.turn.ring();
    _settleDrawer(open: open, velocity: velocity / _drawerWidth);
  }

  /// Sends the drawer to whichever end it is going to, on the one spring that
  /// also turns the hamburger.
  ///
  /// Handing the finger's own velocity to the simulation is what makes a flick
  /// and a tap the same motion at two speeds rather than two behaviours.
  void _settleDrawer({required bool open, required double velocity}) {
    _drawerOpen = open;
    _drawer.animateWith(
      SpringSimulation(
        AppSprings.drawer,
        _drawer.value,
        open ? 1 : 0,
        velocity,
      ),
    );
  }

  void _select(DrawerDestination destination) {
    setState(() => _destination = destination);
    _settleDrawer(open: false, velocity: 0);
  }

  // The sort menu.

  void _openMenu() => _menu.forward();

  void _closeMenu() => _menu.reverse();

  void _setField(SortField field) {
    setState(() => _sortField = field);
    _closeMenu();
  }

  void _setOrder(SortOrder order) {
    setState(() => _sortOrder = order);
    _closeMenu();
  }

  // Search.

  void _onQueryChanged(String value) {
    widget.store.query = value;
    setState(() {});
  }

  /// The way in to a file from the phone, which is what the folder glyph on
  /// the pill and the button's first action both mean.
  ///
  /// The phone's own picker does the finding. What comes back is copied onto
  /// the desk at the top, the destination widens to everything so the new
  /// card is not hidden behind a drawer filter, and the list goes back to the
  /// top so the card is the first thing on screen. A desk with nowhere to
  /// keep a file, which is a desk built by a test, falls back to the search
  /// field, since finding is then the only opening there is.
  Future<void> _browse() async {
    if (!widget.store.canImport) {
      setState(() => _destination = DrawerDestination.allFiles);
      _queryFocus.requestFocus();
      return;
    }
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>[
        for (final format in DocFormat.values) format.extension,
      ],
    );
    if (picked == null || !mounted) return;
    // Read here rather than handing the store a path, because on Android the
    // picker's reference is only readable now, in this session, by the code
    // that asked for it.
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    final entry = await widget.store.importFile(picked.name, bytes);
    if (entry == null || !mounted) return;
    Feel.commit.ring();
    setState(() {
      _destination = DrawerDestination.allFiles;
      _tab = DeskTab.recent;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// What the action button's three pills do, in the order [kFabActions] lists
  /// them.
  void _fabAction(int index) {
    switch (index) {
      // Open a file.
      case 0:
        _browse();
      // Sign a PDF. Which PDF is a question only the library can answer, so
      // the desk narrows to the documents that can carry a signature and
      // waits for one to be chosen: the next card tapped goes to the pad
      // rather than to the reader.
      case 1:
        _beginChoosing();
      // Recent.
      case 2:
        setState(() {
          _destination = DrawerDestination.recent;
          _tab = DeskTab.recent;
        });
        if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  void _clearQuery() {
    _query.clear();
    widget.store.query = '';
    _queryFocus.unfocus();
    setState(() {});
  }

  // What a document can have done to it.

  /// Opens the overflow menu against the dots that asked for it.
  ///
  /// Two rectangles, because they answer two questions. [card] is the whole
  /// row or card and is what the reader grows out of when Open is chosen.
  /// [target] is the three dots themselves, and is where the menu hangs from:
  /// a grid card is tall enough that hanging a menu off its bottom edge puts
  /// the menu most of a screen below the finger that opened it.
  void _openOverflow(LibraryEntry entry, Rect card, Rect target) {
    setState(() {
      _acting = entry;
      _actingRect = card;
      _actingMenuRect = _intoShell(target.isEmpty ? card : target);
    });
    switch (kOverflowMenuStyle) {
      case OverflowMenuStyle.oozed:
        _overflow.forward(from: 0);
      case OverflowMenuStyle.pills:
        if (!_pills.isOpen) _pills.toggle();
    }
  }

  /// Brings a rect measured against the screen into the shell's own space.
  ///
  /// A row reports where its dots are with `localToGlobal`, which answers in
  /// the coordinates of the window. The shell lays out in the design's fixed
  /// space, which the app is scaled into, so the two are the same rect written
  /// in two different units. Everything that hangs off the dots has to be told
  /// the second one, or it lands short of them by whatever the scale is.
  Rect _intoShell(Rect screen) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return screen;
    return Rect.fromPoints(
      box.globalToLocal(screen.topLeft),
      box.globalToLocal(screen.bottomRight),
    );
  }

  /// Puts the menu away the way it arrived.
  ///
  /// Reversed rather than zeroed, because a body that oozed out of the dots
  /// has to be drawn back into them: a menu that vanishes has not gone
  /// anywhere, it has simply stopped being drawn. The entry is held until the
  /// reverse has finished, since the menu cannot retract once the shell has
  /// forgotten which document it belonged to.
  void _closeOverflow() {
    if (_acting == null) return;
    switch (kOverflowMenuStyle) {
      case OverflowMenuStyle.oozed:
        _overflow.reverse().whenCompleteOrCancel(() {
          if (mounted && _overflow.value == 0) {
            setState(() => _acting = null);
          }
        });
      case OverflowMenuStyle.pills:
        // The listener clears the entry once the springs have settled.
        if (_pills.isOpen) _pills.toggle();
    }
  }

  void _act(LibraryEntry entry, DeskAction action) {
    _closeOverflow();
    switch (action) {
      case DeskAction.read:
        widget.onOpen?.call(entry, _actingRect);
      case DeskAction.sign:
        widget.onSign?.call(entry);
      case DeskAction.share:
        _shareSigned(entry);
      case DeskAction.dogEar:
        final store = widget.store.storeFor(entry);
        store.toggleDogEar(store.position);
      case DeskAction.rename:
        _rename(entry);
      case DeskAction.duplicate:
        _duplicate(entry);
      case DeskAction.shareOriginal:
        _shareOriginal(entry);
      case DeskAction.details:
        _details(entry);
      case DeskAction.convert:
        _convert(entry);
      case DeskAction.move:
        _notify('Folders are not built yet.');
      case DeskAction.more:
        _more(entry);
      case DeskAction.star:
      case DeskAction.unstar:
        widget.store.toggleStar(entry);
      case DeskAction.remove:
        _remove(entry);
      case DeskAction.restore:
        widget.store.restore(entry);
      case DeskAction.deleteForever:
        widget.store.deleteForever(entry);
    }
  }

  /// Writes the signed PDF and hands it to the phone's share sheet.
  ///
  /// What can go wrong is said on the desk's own pill rather than in a
  /// dialog, in the words the writer gave for it.
  Future<void> _shareSigned(LibraryEntry entry) async {
    File? file;
    try {
      file = await widget.store.exportSigned(entry);
    } on PdfWriteError catch (error) {
      _notify(error.message);
      return;
    } on Object {
      _notify('The signed file could not be written.');
      return;
    }
    if (!mounted) return;
    if (file == null) {
      _notify('There is nothing signed to share yet.');
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        title: '${entry.title}, signed',
        files: <XFile>[XFile(file.path, mimeType: 'application/pdf')],
      ),
    );
  }

  /// The rest of what can be done to [entry], on a sheet.
  ///
  /// The dots hold what a reader reaches for. This holds the rest, because a
  /// dozen pills peeled off one button stops looking like anything came out of
  /// it and starts looking like a list that happens to be sticky.
  Future<void> _more(LibraryEntry entry) async {
    final actions = _actionsFor(entry, DeskMenuPlace.sheet);
    final picked = await showDeskSheet<DeskAction>(
      context,
      (context) => DeskSheet(
        title: entry.title,
        children: <Widget>[
          for (final action in actions)
            DeskSheetRow(
              label: action.label,
              icon: action.icon,
              note: _noteFor(entry, action),
              enabled: _allows(entry, action),
              onTap: () => Navigator.of(context).pop(action),
            ),
        ],
      ),
    );
    if (picked != null && mounted) _act(entry, picked);
  }

  /// Why a sheet row is offered but cannot be taken, or null when it can.
  String? _noteFor(LibraryEntry entry, DeskAction action) =>
      switch (action) {
        DeskAction.move => 'Folders are not built yet',
        DeskAction.shareOriginal when entry.source == DocSource.asset =>
          'A shipped document has no file to hand over',
        _ => null,
      };

  bool _allows(LibraryEntry entry, DeskAction action) => switch (action) {
    DeskAction.move => false,
    DeskAction.shareOriginal => entry.source == DocSource.file,
    _ => true,
  };

  /// What the desk knows about [entry].
  void _details(LibraryEntry entry) {
    showDeskSheet<void>(
      context,
      (context) => DetailsSheet(
        entry: entry,
        store: widget.store.peek(entry),
        starred: widget.store.isStarred(entry),
        binned: widget.store.isBinned(entry),
      ),
    );
  }

  /// Gives [entry] a different name.
  Future<void> _rename(LibraryEntry entry) async {
    final wanted = await showDeskSheet<String>(
      context,
      (context) => RenameSheet(title: entry.title),
    );
    if (wanted == null || !mounted) return;
    widget.store.rename(entry, wanted);
  }

  /// Puts a second copy of [entry] on the desk.
  Future<void> _duplicate(LibraryEntry entry) async {
    final copy = await widget.store.duplicate(entry);
    if (!mounted) return;
    _notify(
      copy == null
          ? 'That document could not be copied.'
          : '${copy.title} is on the desk.',
    );
  }

  /// Hands the file itself to the phone's share sheet, as it came in.
  Future<void> _shareOriginal(LibraryEntry entry) async {
    if (entry.source != DocSource.file) {
      _notify('A shipped document has no file to hand over.');
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        title: entry.title,
        files: <XFile>[XFile(entry.path)],
      ),
    );
  }

  /// Turns [entry] into another kind of file and puts the result on the desk.
  ///
  /// The original is never touched. A conversion is a new document, which is
  /// why it lands beside the one it came from rather than replacing it.
  Future<void> _convert(LibraryEntry entry) async {
    final store = widget.store.peek(entry);
    if (store == null) {
      _notify('Nothing has read that file yet.');
      return;
    }
    final source = ConvertSource(
      title: entry.title,
      document: store.document,
      pdf: store.pdf,
    );
    final targets = targetsFor(entry.format.extension, hasGrid: source.hasGrid);
    if (targets.isEmpty) {
      _notify('There is nothing to turn that into.');
      return;
    }
    final picked = await showDeskSheet<ConvertTarget>(
      context,
      (context) => ConvertSheet(
        title: entry.title,
        targets: targets,
        unbuilt: _unbuiltTargets,
      ),
    );
    if (picked == null || !mounted) return;

    final result = runConvert(source, picked, faces: await _faces());
    if (result == null) {
      _notify('quire cannot write a ${picked.label} file yet.');
      return;
    }
    final made = await widget.store.importFile(
      '${_fileSafe(entry.title)}.${picked.extension}',
      result.bytes,
    );
    if (!mounted) return;
    if (made == null) {
      _notify('The converted file could not be kept.');
      return;
    }
    if (result.warnings.isEmpty) {
      _notify('${made.title} is on the desk as ${picked.label}.');
      return;
    }
    await showDeskSheet<void>(
      context,
      (context) => ConvertWarningSheet(
        title: made.title,
        warnings: result.warnings,
      ),
    );
  }

  /// The targets the sheet offers but this build cannot write.
  ///
  /// Stated here rather than left off the list, so a reader looking for one
  /// finds out it is coming instead of wondering whether they missed it.
  static const Set<ConvertTarget> _unbuiltTargets = <ConvertTarget>{};

  /// The two faces a composed page is set in, read once and kept.
  ///
  /// They are the app's own typeface, which is what a page composed here is
  /// set in and what gets embedded in it, cut down to the letters the document
  /// actually uses.
  static ConvertFaces? _held;

  Future<ConvertFaces> _faces() async {
    final held = _held;
    if (held != null) return held;
    Future<Uint8List> read(String weight) async {
      final data = await rootBundle.load('assets/fonts/Inter-$weight.ttf');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }

    return _held = ConvertFaces(
      regular: await read('Regular'),
      bold: await read('Bold'),
    );
  }

  /// A title with the characters a file name cannot carry taken out.
  String _fileSafe(String title) {
    final clean = title.replaceAll(RegExp(r'[^A-Za-z0-9 ._-]+'), '').trim();
    return clean.isEmpty ? 'Document' : clean;
  }

  /// Puts the desk in the state of waiting for a PDF to sign.
  ///
  /// The pill says so and offers a way out, and does not drain: a choice is
  /// not something that runs out.
  void _beginChoosing() {
    setState(() {
      _destination = DrawerDestination.allFiles;
      _tab = DeskTab.pdf;
      _choosingToSign = true;
      _pill = null;
      _notice = 'Choose a PDF to sign';
    });
    _undo.value = 0;
    _undoRise.forward(from: 0);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _stopChoosing() {
    if (!_choosingToSign) return;
    setState(() {
      _choosingToSign = false;
      _notice = null;
    });
  }

  /// A card tapped while the desk is waiting for a PDF to sign.
  void _signChosen(LibraryEntry entry, Rect rect) {
    if (entry.format != DocFormat.pdf) return;
    _stopChoosing();
    widget.onSign?.call(entry);
  }

  /// Says [text] on the pill for as long as an undo would have lasted.
  void _notify(String text) {
    setState(() {
      _pill = null;
      _notice = text;
    });
    _undoRise.forward(from: 0);
    _undo.forward(from: 0);
  }

  /// Takes a document off the desk.
  ///
  /// Nothing here touches the row's pixels. The desk announces that the
  /// document has gone and the body, which drew the row, is what takes it
  /// apart: that is what makes every route out of the library crumble the same
  /// way, and what makes it impossible for a sort or a filter to crumble
  /// anything.
  void _remove(LibraryEntry entry) {
    widget.store.remove(entry);
    setState(() => _pill = entry);
    _undoRise.forward(from: 0);
    _undo.forward(from: 0);
  }

  void _undoRemoval() {
    if (_pill == null) return;
    _undo.stop();
    _undoRise.value = 0;
    setState(() => _pill = null);
    widget.store.undoRemove();
  }

  /// The documents the drawer's destination reaches, before the search: all
  /// of them for Recent and All files, the starred ones, the signed ones, or
  /// the ones in the bin.
  List<LibraryEntry> get _pool => switch (_destination) {
        DrawerDestination.starred =>
          widget.store.entries.where(widget.store.isStarred).toList(),
        DrawerDestination.signed => widget.store.entries
            .where((e) => widget.store.peek(e)?.signed ?? false)
            .toList(),
        DrawerDestination.bin => widget.store.binned,
        _ => widget.store.entries,
      };

  /// [_pool] after the search.
  List<LibraryEntry> get _base => widget.store.visibleOf(_pool);

  /// True while there is a list on screen for chrome to be about. A
  /// destination with nothing in it shows its own words instead, and gets no
  /// tabs and no sort row over them.
  bool get _listed =>
      _destination.library &&
      widget.store.entries.isNotEmpty &&
      _pool.isNotEmpty;

  /// What the body shows: the destination, then the search, then the tab,
  /// then the sort.
  List<LibraryEntry> get _entries => shellEntries(
        _base,
        _tab,
        _sortField,
        _sortOrder,
        widget.store.peek,
      );

  /// How much each tab holds, before the search is applied, so a count is a
  /// fact about the destination rather than about what you have typed.
  Map<DeskTab, int> get _counts => <DeskTab, int>{
        for (final tab in DeskTab.values) tab: _pool.where(tab.holds).length,
      };

  /// What [entry] can have done to it, here and now, in the one place.
  List<DeskAction> _actionsFor(
    LibraryEntry entry, [
    DeskMenuPlace place = DeskMenuPlace.goo,
  ]) => DeskAction.values
      .where(
        (action) =>
            action.place == place &&
            action.suits(
              entry,
              starred: widget.store.isStarred(entry),
              binned: widget.store.isBinned(entry),
              signed: widget.store.peek(entry)?.signed ?? false,
              canCopy: widget.store.canImport,
            ),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final bare = widget.store.entries.isEmpty;
    final nothingMatched = _listed && _base.isEmpty;
    return ColoredBox(
      color: AppColors.ground,
      child: Stack(
        children: [
          Positioned.fill(child: _shell(top, bottom, bare)),
          if (nothingMatched) _noResults(),
          if (_pill != null || _notice != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottom + kUndoPillBottom,
              child: Center(
                child: AnimatedBuilder(
                  animation: Listenable.merge(<Listenable>[_undo, _undoRise]),
                  builder: (context, _) => UndoPill(
                    title: _pill?.title ?? '',
                    message: _notice,
                    drained: _undo.value,
                    rise: easeOutCubic.transform(_undoRise.value),
                    actionLabel: _choosingToSign ? 'CANCEL' : 'UNDO',
                    onUndo: _notice == null
                        ? _undoRemoval
                        : _choosingToSign
                            ? _stopChoosing
                            : null,
                  ),
                ),
              ),
            ),
          // Over the library and under everything that opens on top of it:
          // the button is the desk's own control, so a menu or the drawer
          // covers it rather than the other way round.
          // The button is off the desk for now. Everything it offered has a
          // door of its own: a file comes in through the folder on the search
          // pill, a signature is drawn inside the document it belongs to, and
          // Recent is a row in the drawer.
          if (kShowDeskFab) GooeyFab(onSelected: _fabAction),
          if (_listed) _menuLayer(top),
          if (_acting case final entry?) _overflowLayer(entry),
          AnimatedBuilder(
            animation: _drawer,
            builder: (context, _) => NavDrawer(
              progress: _drawer.value,
              selected: _destination,
              onSelect: _select,
              onDismiss: () => _settleDrawer(open: false, velocity: 0),
              onDrag: _dragDrawer,
              onDragEnd: _endDrawerDrag,
            ),
          ),
          // Above the drawer, because it is the drawer's handle: the arrow it
          // turns into has to be legible over the panel it opened.
          Positioned(
            left: kTopBarPaddingX,
            top: top + kMenuButtonTop,
            child: AnimatedBuilder(
              animation: _drawer,
              builder: (context, _) => MenuButton(
                progress: _drawer.value,
                onTap: _toggleDrawer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shell(double top, double bottom, bool bare) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: top),
        AnimatedBuilder(
          animation: _query,
          builder: (context, _) => DeskTopBar(
            search: SearchPill(
              controller: _query,
              focusNode: _queryFocus,
              onChanged: _onQueryChanged,
              onClear: _clearQuery,
              onBrowse: _browse,
            ),
          ),
        ),
        // A desk with nothing on it drops the tabs and the sort row, for the
        // same reason a destination with nothing in it does: they are chrome
        // about a list, and there is no list.
        if (_listed) ...[
          TabStrip(
            selected: _tab,
            counts: _counts,
            onSelect: (tab) => setState(() => _tab = tab),
          ),
          SortRow(
            field: _sortField,
            order: _sortOrder,
            view: _view,
            onOpenMenu: _openMenu,
            onView: (view) => setState(() => _view = view),
          ),
        ],
        Expanded(child: _body(bottom, bare)),
      ],
    );
  }

  Widget _body(double bottom, bool bare) {
    if (!_destination.library) {
      return DestinationPanel(destination: _destination);
    }
    if (bare) return const DeskEmpty(onOpen: null);
    // Starred, signed and binned are destinations that can be empty while
    // the desk is not, and each has its own words for that.
    if (_pool.isEmpty) return DestinationPanel(destination: _destination);
    // Counted off what is on screen, not off the library. A tab that shows
    // two documents with `6 DOCUMENTS` set under them would be the desk
    // contradicting itself in the same glance.
    final colophon = DeskColophon(
      documents: _entries.length,
      words: widget.store.wordsIn(_entries),
      minutes: widget.store.minutesIn(_entries),
    );
    // The body is what scrolls, because the rows are its own: a slot closing
    // behind a removal has to be able to move the list under the finger. The
    // shell only says how much room to leave at the bottom for what it floats
    // over the body.
    if (_view == DeskView.list) {
      return DeskListBody(
        library: widget.store,
        entries: _entries,
        query: widget.store.query,
        onOpen: _choosingToSign ? _signChosen : widget.onOpen,
        onOverflow: _openOverflow,
        controller: _scroll,
        padding: EdgeInsets.only(bottom: bottom + kBodyBottomPadding),
        footer: colophon,
      );
    }
    return GridBody(
      library: widget.store,
      entries: _entries,
      query: widget.store.query,
      onOpen: _choosingToSign ? _signChosen : widget.onOpen,
      onOverflow: _openOverflow,
      controller: _scroll,
      padding: const EdgeInsets.all(kGridPadding).copyWith(
        bottom: bottom + kBodyBottomPadding,
      ),
      footer: colophon,
    );
  }

  /// The sort menu, and the tap anywhere else that closes it.
  ///
  /// It is drawn in the shell's own stack rather than pushed as a route, so
  /// the library behind it stays live and the menu cannot be left behind by a
  /// navigation.
  Widget _menuLayer(double top) {
    return AnimatedBuilder(
      animation: _menu,
      builder: (context, _) {
        // Built from the first frame of the run rather than the first frame
        // with something to see, so the arrival has a t of exactly 0.
        if (_menu.status == AnimationStatus.dismissed) {
          return const SizedBox.shrink();
        }
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Feel.tap.ring();
                  _closeMenu();
                },
              ),
            ),
            Positioned(
              left: kSortRowPaddingX,
              top: top + kShellChrome + kSortMenuOffset,
              child: SortMenu(
                t: _menu.value,
                field: _sortField,
                order: _sortOrder,
                onField: _setField,
                onOrder: _setOrder,
              ),
            ),
          ],
        );
      },
    );
  }

  /// The overflow menu, hung off the three dots that opened it.
  ///
  /// Its right edge lines up with the row's own right padding and it hangs
  /// just under the row, so it reads as belonging to that document rather than
  /// to the screen. Like the sort menu it is drawn in the shell's own stack
  /// rather than pushed as a route, so the library behind it stays live.
  /// How open the menu is, 0 to 1, whichever thing is driving it.
  double get _overflowOpen => switch (kOverflowMenuStyle) {
        OverflowMenuStyle.oozed =>
          easeOutCubic.transform(_overflow.value.clamp(0.0, 1.0)),
        OverflowMenuStyle.pills => _pills.progress.value.clamp(0.0, 1.0),
      };

  Widget _overflowLayer(LibraryEntry entry) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_overflow, _pills.animations]),
      builder: (context, _) {
        return Stack(
          children: [
            // The same scrim the action button puts down: a plain fade and no
            // blur, so the library dims behind the menu but stays readable,
            // which is the point of leaving it there. It rides the menu's own
            // controller, so it lifts as the menu is drawn back in.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Feel.tap.ring();
                  _closeOverflow();
                },
                child: ColoredBox(
                  color: AppColors.scrim.withValues(
                    alpha: AppColors.scrim.a *
                        switch (kOverflowMenuStyle) {
                          OverflowMenuStyle.oozed => _overflowOpen,
                          OverflowMenuStyle.pills => _pills.scrim.value,
                        },
                  ),
                ),
              ),
            ),
            if (kOverflowMenuStyle == OverflowMenuStyle.oozed)
              Positioned.fill(
                child: IgnorePointer(child: _overflowGoo()),
              ),
            // The panel is hung off the dots by the delegate. The pills place
            // themselves, because they are measured from the dots' centre
            // and a box clamped against the screen margin would carry the
            // goo's origin away from the glyph it is meant to sit under.
            switch (kOverflowMenuStyle) {
              OverflowMenuStyle.oozed => Positioned.fill(
                  child: CustomSingleChildLayout(
                    delegate: _OverflowMenuLayout(
                      anchor: _actingMenuRect,
                      margin: EdgeInsets.fromLTRB(
                        kListRowPaddingX,
                        kSafeTop,
                        kListRowPaddingX,
                        MediaQuery.paddingOf(context).bottom +
                            kOverflowMenuMargin,
                      ),
                      gap: kOverflowMenuOffset,
                    ),
                    child: OverflowMenu(
                      key: _menuKey,
                      t: _overflow.value,
                      entry: entry,
                      actions: _actionsFor(entry),
                      oozed: true,
                      onAction: (action) => _act(entry, action),
                    ),
                  ),
                ),
              OverflowMenuStyle.pills => GooMenu(
                  drives: <double>[
                    for (var i = 0; i < _pills.actionCount; i++)
                      _pills.actionDrive(i).value,
                  ],
                  items: <GooMenuItem>[
                    for (final action in _actionsFor(entry))
                      GooMenuItem(
                        label: action.label,
                        icon: action.icon,
                        destructive: action.destructive,
                      ),
                  ],
                  onPick: (i) => _act(entry, _actionsFor(entry)[i]),
                  anchor: _actingMenuRect,
                  bounds: Rect.fromLTRB(
                    0,
                    kSafeTop,
                    kScreenWidth,
                    kScreenHeight -
                        MediaQuery.paddingOf(context).bottom -
                        kOverflowMenuMargin,
                  ),
                ),
            },
            // Last, so it is over the goo. The dots are what the body came out
            // of, and a control the body has swallowed is a control nobody can
            // find. The barrier behind it takes the tap, which is what shuts
            // the menu, so the cross it turns into is honest.
            if (!_actingMenuRect.isEmpty)
              Positioned(
                left: _actingMenuRect.left,
                top: _actingMenuRect.top,
                width: _actingMenuRect.width,
                height: _actingMenuRect.height,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: OverflowDotsPainter(
                      t: _overflowOpen,
                      // Starts as the row's own faint dots and brightens as
                      // it opens, so the overlay and the dots underneath it
                      // are the same mark at the moment it appears and at the
                      // moment it goes.
                      colour: Color.lerp(
                        AppColors.inkFaint,
                        AppColors.ink,
                        _overflowOpen,
                      )!,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }


  /// The body the menu oozes out of the dots as.
  ///
  /// The panel's rectangle is measured rather than worked out, so this knows
  /// nothing about how many rows the menu has or how tall a row is, and it is
  /// read after the fact: on the first frame there is nothing to measure and
  /// nothing to draw, which is the frame the body would have been a dot on
  /// anyway. The goo is gone by the time the panel is solid, so no rim of it
  /// is left showing round a hard edge.
  Widget _overflowGoo() {
    final box = _menuKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return const SizedBox.shrink();
    final origin = (box.localToGlobal(Offset.zero) & box.size);
    final t = easeOutCubic.transform(_overflow.value.clamp(0.0, 1.0));
    final fade = 1 - ((t - 0.7) / 0.3).clamp(0.0, 1.0);
    if (fade <= 0) return const SizedBox.shrink();
    return Opacity(
      opacity: fade,
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix(kGooAlphaThresholdMatrix),
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: kGooBlurSigma,
            sigmaY: kGooBlurSigma,
            tileMode: TileMode.decal,
          ),
          child: CustomPaint(
            painter: OverflowGooPainter(
              from: _actingMenuRect,
              to: origin,
              fromRadius: _actingMenuRect.shortestSide / 2,
              toRadius: kSortMenuRadius,
              t: t,
              colour: AppColors.surface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _noResults() {
    return Positioned(
      left: kScreenPadding,
      right: kScreenPadding,
      top: kNoResultsTop,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Nothing on the desk matches.',
            style: AppText.title.copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: kNoResultsGap),
          Text(
            'for "${widget.store.query}"',
            style: AppText.docMeta.copyWith(color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }
}


/// Lays the overflow menu against the three dots that opened it.
///
/// The menu measures itself, so nothing here has to know how many rows it has
/// or how tall a row is: [getPositionForChild] is handed the size the menu
/// actually took. Its right edge lines up with the right edge of the dots, so
/// the menu reads as hanging off them whichever column a card sits in, and it
/// turns over above them rather than running off the bottom of the screen.
class _OverflowMenuLayout extends SingleChildLayoutDelegate {
  const _OverflowMenuLayout({
    required this.anchor,
    required this.margin,
    required this.gap,
  });

  /// The dots, in the coordinates of the layer the menu is drawn in.
  final Rect anchor;

  /// How close the menu may come to each edge of that layer.
  final EdgeInsets margin;

  /// The air between the dots and the menu.
  final double gap;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          math.max(0, constraints.maxWidth - margin.horizontal),
          math.max(0, constraints.maxHeight - margin.vertical),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final lowest = size.height - margin.bottom - childSize.height;
    final below = anchor.bottom + gap;
    final above = anchor.top - gap - childSize.height;
    // Under the dots when there is room, over them when there is not, and
    // pressed against the top edge when there is room in neither direction,
    // which is a menu taller than the screen and so is only ever a floor.
    final double top;
    if (below <= lowest) {
      top = below;
    } else if (above >= margin.top) {
      top = above;
    } else {
      top = math.max(margin.top, lowest);
    }
    final rightmost = size.width - margin.right - childSize.width;
    final left = clampDouble(
      anchor.right - childSize.width,
      margin.left,
      math.max(margin.left, rightmost),
    );
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_OverflowMenuLayout old) =>
      old.anchor != anchor || old.margin != margin || old.gap != gap;
}
