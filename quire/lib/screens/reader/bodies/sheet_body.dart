import 'dart:math' as math;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/widgets.dart';

import '../../../format/csv_parser.dart';
import '../../../model/document.dart';
import '../../../services/document_store.dart';
import '../../../theme/easings.dart';
import '../../../theme/metrics.dart';
import '../../../theme/springs.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../desk/desk_sheet.dart';
import '../sheet_surface.dart';
import 'cell_bar.dart';
import 'page_states.dart';
import 'parse_strip.dart';
import 'sheet_geometry.dart';
import 'sheet_grid.dart';
import 'sheet_tabs.dart';
import 'spine_table.dart';

/// A cell a find matched, and the sheet of the workbook it is on.
typedef SheetMatch = ({int sheet, SheetCell cell});

/// How many rows the fore edge draws one hairline for.
///
/// A mark per row on a seventy row file would be a grey block; a mark every
/// twenty five rows is a scale a thumb can aim at.
const kRowsPerForeEdgeMark = 25;

/// Which sheet is showing, which column is open, and which cell is ringed.
///
/// It lives outside the widget because a sheet has two sides and each side is
/// its own widget: without one shared object a reader could turn a sheet over
/// and find a different column open on the back than the one they left open on
/// the front. It is keyed to the document rather than to the screen, so the
/// state lasts exactly as long as the open document does: nothing disposes it,
/// because there is nothing to dispose once the store it hangs from is gone.
class SheetController extends ChangeNotifier {
  SheetController._();

  static final Expando<SheetController> _held = Expando<SheetController>();

  /// The view state of [store]'s grid, made once and then kept.
  static SheetController of(DocumentStore store) =>
      _held[store] ??= SheetController._();

  int _sheet = 0;
  final Map<int, int> _open = <int, int>{};
  final Map<int, double> _offsets = <int, double>{};
  SheetCell? _selected;

  /// Which sheet of a workbook is showing. Always 0 for a CSV.
  int get sheet => _sheet;
  set sheet(int value) {
    if (value == _sheet) return;
    _sheet = value;
    _selected = null;
    notifyListeners();
  }

  /// The one column showing its values on the current sheet.
  int get openColumn => _open[_sheet] ?? 0;
  set openColumn(int value) {
    if (value == openColumn) return;
    _open[_sheet] = value;
    // The ring belongs to a cell in the open column, so opening another one
    // takes the ring with it rather than leaving it stranded in a spine.
    _selected = null;
    notifyListeners();
  }

  /// Records which column a sheet opens on the first time it is shown, which
  /// is the file's frozen column when it names one.
  void startOn(int sheet, int column) => _open.putIfAbsent(sheet, () => column);

  /// Where a sheet was left scrolled to.
  double offsetOf(int sheet) => _offsets[sheet] ?? 0;
  void rememberOffset(int sheet, double value) => _offsets[sheet] = value;

  /// Where a sheet was left pushed to, across and down both. A workbook is
  /// one document and a reader who steps to another sheet and back expects to
  /// find the column they were reading, not column A.
  final Map<int, Offset> _pans = <int, Offset>{};
  Offset panOf(int sheet) => _pans[sheet] ?? Offset.zero;
  void rememberPan(int sheet, Offset value) => _pans[sheet] = value;

  /// The ringed cell, or null when the cell bar is down.
  SheetCell? get selected => _selected;
  set selected(SheetCell? value) {
    if (value == _selected) return;
    _selected = value;
    notifyListeners();
  }
}

/// The reader body for a spreadsheet and for a CSV.
///
/// Both formats parse to one grid [TableBlock] per section, so there is one
/// body for the two of them and the only difference on screen is the band
/// above the grid: a workbook names its sheets, a delimited file says how it
/// was read.
class SheetBody extends ReaderBody {
  const SheetBody({
    super.key,
    required this.store,
    this.matches = const <SheetMatch>{},
  });

  final DocumentStore store;

  /// Cells the current query found, which the grid washes.
  final Set<SheetMatch> matches;

  @override
  Widget buildFront(BuildContext context) =>
      SheetView(store: store, matches: matches);

  /// The back of a grid: the same cells, showing what the file stores rather
  /// than what the formatting makes of it.
  ///
  /// Both faces are built from the one parse the store is already holding, so
  /// the back has nothing to load and is ready in the frame the front is. A
  /// workbook with no grid in it says so on both faces, which is the only way
  /// a fold here can uncover anything other than the document.
  @override
  Widget buildBack(BuildContext context) =>
      SheetView(store: store, matches: matches, face: SheetFace.back);

  @override
  int get unitCount => store.unitCount;

  @override
  String get positionLabel => store.positionLabel;

  /// The grid's last two columns stand under the fore edge's usual hit strip,
  /// so the strip is pushed off the sheet while a grid is open and every spine
  /// can be tapped.
  @override
  bool get ownsRightEdge => true;

  @override
  List<double> get foreEdgeMarks {
    final count = store.unitCount;
    if (count <= 0) return const <double>[];
    return <double>[
      for (var row = 0; row < count; row += kRowsPerForeEdgeMark) row / count,
    ];
  }
}

/// One face of a grid document: the band above it, the table, and the bar.
class SheetView extends StatefulWidget {
  const SheetView({
    super.key,
    required this.store,
    this.matches = const <SheetMatch>{},
    this.face = SheetFace.front,
  });

  final DocumentStore store;
  final Set<SheetMatch> matches;
  final SheetFace face;

  @override
  State<SheetView> createState() => _SheetViewState();
}

class _SheetViewState extends State<SheetView> with TickerProviderStateMixin {
  /// How far the bar has risen, and how much room it has open for a
  /// comment, each on a spring, on a clock that runs only while either is
  /// moving.
  ///
  /// Springs rather than a timed curve, because the bar is sent up and down
  /// again at any moment, a cell chosen and let go and chosen again, and a
  /// spring sent back sets off from where it is at the speed it has instead
  /// of jumping to where a curve running the other way would put it.
  final SpringValue _rise = SpringValue(
    0,
    tolerance: SpringValue.shareTolerance,
  );
  final SpringValue _room = SpringValue(
    0,
    tolerance: SpringValue.shareTolerance,
  );

  /// Built in [initState] rather than lazily on first use, because a sheet
  /// with no grid on it never reaches the part of the build that would touch
  /// it, and a ticker that first exists inside [dispose] is created against a
  /// tree that has already gone.
  late final Ticker _barClock;
  double _barNow = 0;
  double _barStarted = 0;

  /// The reader's place the last time this sheet heard about it, so a store
  /// that speaks for another reason, a lock or a dog ear, is not taken for a
  /// jump.
  int _position = 0;

  late SheetController _sheet;

  /// The column that is open and the one it took over from, which is the whole
  /// state the open animation runs on.

  /// The sheet that was showing last frame, so a workbook can move the reader
  /// when they step to another one.
  int _shown = 0;

  /// True while this widget is the one writing the reader's position, so the
  /// store's own notification does not bounce back as a jump.
  bool _syncing = false;

  ParseFacts? _facts;

  /// What the bar was showing when the cell was let go, so it can finish
  /// leaving with its own text rather than emptying out first.
  _BarText? _leaving;

  /// The last cell with a comment the bar showed, so the comment's room can
  /// close around what it said rather than emptying first.
  _BarText? _said;

  /// The cell that was chosen when the controller last spoke.
  SheetCell? _chosen;

  /// The matches on one sheet, worked out again only when the find or the
  /// sheet changes, so the grid is not repainted for a set that is new only
  /// in name.
  Set<SheetCell> _matchesOn(int sheet) {
    if (!identical(widget.matches, _matchesFrom) || sheet != _matchesSheet) {
      _matchesFrom = widget.matches;
      _matchesSheet = sheet;
      _matchesHere = <SheetCell>{
        for (final match in widget.matches)
          if (match.sheet == sheet) match.cell,
      };
    }
    return _matchesHere;
  }

  Set<SheetMatch>? _matchesFrom;
  int _matchesSheet = -1;
  Set<SheetCell> _matchesHere = const <SheetCell>{};

  @override
  void initState() {
    super.initState();
    _barClock = createTicker(_barTick);
    _sheet = SheetController.of(widget.store);
    _sheet.addListener(_onController);
    widget.store.addListener(_onStore);
    _shown = _sheetIndex;
    _position = widget.store.position;
    _chosen = _sheet.selected;
    if (_chosen != null) {
      _rise.jumpTo(1);
      _room.jumpTo(_commented(_chosen!) ? 1 : 0);
    }
    _readParseFacts();
  }

  @override
  void dispose() {
    _sheet.removeListener(_onController);
    widget.store.removeListener(_onStore);
    _barClock.dispose();
    super.dispose();
  }

  void _barTick(Duration elapsed) {
    _barNow =
        _barStarted + elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (_rise.restingAt(_barNow) && _room.restingAt(_barNow)) {
      _barClock.stop();
    }
    _repaint();
  }

  void _runBar() {
    if (_barClock.isActive) return;
    _barStarted = _barNow;
    _barClock.start();
  }

  /// True when somebody has said something about [cell].
  bool _commented(SheetCell cell) {
    final table = _tableOn(_sheetIndex);
    if (table == null) return false;
    return cellAt(table, cell.row, cell.column)?.comment != null;
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  /// Reads a delimited file a second time, for the facts the shared model has
  /// no room for: which delimiter won, and which rows did not match their
  /// header. The model pads a ragged row out to the grid's width, so by the
  /// time the table exists the raggedness is gone.
  void _readParseFacts() {
    final document = widget.store.document;
    if (document == null || document.sourceFormat != 'csv') return;
    final bytes = widget.store.bytes;
    if (bytes.isEmpty) return;
    _facts = csvFacts(readCsv(bytes));
  }

  void _onController() {
    final sheet = _sheetIndex;
    if (sheet != _shown) {
      _shown = sheet;
      // A cell asked for on the sheet being left means nothing on the next
      // one. A cell asked for on the next one arrives with the choice below.
      _reveal = null;
      // A workbook is one document, so stepping to another sheet moves the
      // reader through it: the folio chip and the fore edge have to agree
      // with the tab that is lit.
      _moveTo(_rowOffset(sheet) + _rowsScrolled(sheet));
    }
    final chosen = _sheet.selected;
    if (chosen != _chosen) {
      if (chosen != null) {
        final said = _commented(chosen) ? 1.0 : 0.0;
        // A bar still out of sight opens with its room already the right
        // size; one already up opens or closes it as the choice moves.
        if (_rise.valueAt(_barNow) <= 0.001 && _rise.target == 0) {
          _room.jumpTo(said);
        } else {
          _room.sendTo(said, _barNow, AppSprings.barNote);
        }
        _rise.sendTo(1, _barNow, AppSprings.barRise);
      } else {
        _rise.sendTo(0, _barNow, AppSprings.barFall);
      }
      _runBar();
    }
    if (chosen != null) {
      // A cell chosen from somewhere other than the grid, such as the list of
      // comments, has to be brought into view as well as ringed. Showing a
      // cell is not a jump, so whatever row a jump was holding the reader on
      // gives way to where the grid ends up. Only a new choice asks: the
      // controller speaks for other reasons too, and those are not requests.
      if (chosen != _chosen) {
        _landing = null;
        _reveal = SheetReveal(chosen);
      }
    }
    _chosen = chosen;
    _repaint();
  }

  /// How far down a sheet was left, in whole rows.
  ///
  /// Worked out from the pan rather than from a scroll position, because the
  /// grid has none: it is painted at an offset and the offset is the state.
  int _rowsScrolled(int index) {
    final table = _tableOn(index);
    if (table == null) return 0;
    final geometry = SheetGeometry.of(table);
    return geometry.rowAt(_sheet.panOf(index).dy + geometry.frozenHeight);
  }

  /// Puts the reader at [row] of the whole document without the store's own
  /// notification bouncing back as a jump.
  void _moveTo(int row) {
    _position = row;
    if (widget.store.position == row) return;
    _syncing = true;
    widget.store.position = row;
    _syncing = false;
  }

  /// Follows the reader when something outside the grid moves them, which is
  /// the fore edge scrub and the riffle.
  void _onStore() {
    if (_syncing || !mounted) return;
    // Only a move of the reader's place is a jump. The store also speaks when
    // the page is locked or a dog ear is folded, and neither of those should
    // move the grid an inch.
    if (widget.store.position == _position) return;
    _position = widget.store.position;
    final holding = _sheetHolding(widget.store.position);
    if (holding != _sheetIndex) {
      // The sheet is turned with its scroll already where the row is, so the
      // move the turn itself makes lands on the same row rather than on
      // wherever that sheet was last left.
      final table = _tableOn(holding);
      if (table != null) {
        final geometry = SheetGeometry.of(table);
        final row = widget.store.position - _rowOffset(holding);
        _sheet.rememberPan(
          holding,
          Offset(
            _sheet.panOf(holding).dx,
            (geometry.topOf(row) - geometry.frozenHeight).clamp(
              0.0,
              double.infinity,
            ),
          ),
        );
      }
      _landing = widget.store.position;
      _sheet.sheet = holding;
      return;
    }
    // The grid is asked to bring the row into view rather than told where to
    // scroll to: it knows its own row heights and its own frozen panes, and
    // it will not move at all if the row is already on screen.
    _landing = widget.store.position;
    final row = widget.store.position - _rowOffset(_sheetIndex);
    if (row < 0) return;
    setState(
      () => _reveal = SheetReveal(
        SheetCell(row, _sheet.selected?.column ?? 0),
        toTop: true,
      ),
    );
  }

  QuireDocument? get _document => widget.store.document;

  /// The row a jump to another sheet was aimed at, held until the reader
  /// scrolls by hand.
  ///
  /// A short sheet cannot scroll the row to its top, so the list settles
  /// with some earlier row there. Without this, that settling would be read
  /// as the reader moving and would put them on that earlier row, and the
  /// place they jumped to would be lost the moment they arrived.
  int? _landing;

  /// The sheet that [row] of the whole document is on.
  int _sheetHolding(int row) {
    final document = _document;
    if (document == null || document.sections.isEmpty) return 0;
    var below = 0;
    for (var s = 0; s < document.sections.length; s++) {
      for (final block in document.sections[s].blocks) {
        if (block is TableBlock) below += block.rows.length;
      }
      if (row < below) return s;
    }
    return document.sections.length - 1;
  }

  int get _sheetIndex {
    final sections = _document?.sections.length ?? 0;
    if (sections == 0) return 0;
    return _sheet.sheet.clamp(0, sections - 1);
  }

  /// How many rows of the whole document sit above sheet [index], which is
  /// what makes the folio chip read one number across a whole workbook.
  int _rowOffset(int index) {
    final document = _document;
    if (document == null) return 0;
    var rows = 0;
    for (var s = 0; s < index && s < document.sections.length; s++) {
      for (final block in document.sections[s].blocks) {
        if (block is TableBlock) rows += block.rows.length;
      }
    }
    return rows;
  }

  TableBlock? _tableIn(DocSection section) {
    for (final block in section.blocks) {
      if (block is TableBlock) return block;
    }
    return null;
  }

  /// The grid on sheet [index], or null for a sheet that holds none.
  TableBlock? _tableOn(int index) {
    final document = _document;
    if (document == null || index < 0 || index >= document.sections.length) {
      return null;
    }
    return _tableIn(document.sections[index]);
  }

  bool _onScroll(ScrollNotification notification) {
    // A tab strip sliding sideways and a value being read across are not the
    // reader moving through the document, so neither reaches the shell.
    if (notification.metrics.axis == Axis.horizontal) return true;
    if (notification is! ScrollUpdateNotification) return false;
    final index = _sheetIndex;
    _sheet.rememberOffset(index, notification.metrics.pixels);
    if (_sheet.selected != null) _sheet.selected = null;
    final row = (notification.metrics.pixels / kTableRowHeight).floor();
    final top = _rowOffset(index) + (row < 0 ? 0 : row);
    final landing = _landing;
    if (landing != null && notification.dragDetails == null) {
      final showing = (notification.metrics.viewportDimension / kTableRowHeight)
          .floor();
      // At the foot every row below the top is on screen, whatever the
      // header and the padding leave of the viewport.
      final atFoot =
          notification.metrics.pixels >=
          notification.metrics.maxScrollExtent - 0.5;
      if (landing >= top && (atFoot || landing < top + showing)) return false;
    }
    _landing = null;
    _moveTo(top);
    return false;
  }

  /// How far the body has to start below its own top to clear the band.
  double _under = 0;

  /// Measures that gap once the body has been laid out, and again if the
  /// reader ever puts the body somewhere else.
  void _measureBand() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    // The padding is inside this body, so the body's own top does not move
    // when it changes: measuring it again would otherwise chase itself.
    final top = box.localToGlobal(Offset.zero).dy;
    final want = math.max(0.0, kHeadBandTop + kHeadBandHeight - top);
    if ((want - _under).abs() < 0.5) return;
    setState(() => _under = want);
  }

  /// Every sheet in the workbook, for a file with more of them than the foot
  /// of a phone can hold.
  Future<void> _allSheets(QuireDocument document, int showing) async {
    final picked = await showDeskSheet<int>(
      context,
      (context) => DeskSheet(
        title: 'Sheets',
        note: 'One workbook, however many sheets it was written on.',
        children: <Widget>[
          for (var i = 0; i < document.sections.length; i++)
            DeskSheetRow(
              label: document.sections[i].title,
              icon: i == showing ? LucideIcons.squareCheck : LucideIcons.table2,
              note: _rowsOn(document.sections[i]),
              onTap: () => Navigator.of(context).pop(i),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    _sheet.sheet = picked;
  }

  /// How many rows a sheet holds, in the words the desk uses for a count.
  String _rowsOn(DocSection section) {
    final table = _tableIn(section);
    if (table == null) return 'Nothing on it';
    final rows = table.rows.length;
    return rows == 1 ? '1 row' : '$rows rows';
  }

  /// The cell the grid is being asked to bring into view, if any.
  ///
  /// It is a cell rather than a row because the grid moves in two directions
  /// and a row on its own says nothing about which way it went.
  SheetReveal? _reveal;

  void _jumpToRow(int row) {
    setState(
      () => _reveal = SheetReveal(
        SheetCell(row, _sheet.selected?.column ?? 0),
        toTop: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureBand();
    });
    final document = _document;
    if (document == null || document.sections.isEmpty) {
      return _emptySheet();
    }
    final index = _sheetIndex;
    final section = document.sections[index];
    final table = _tableIn(section);
    // A workbook sheet with no grid on it is a real thing to open, and it is
    // the same nothing on both faces. Neither one is allowed to be a blank
    // rectangle: a corner turned here has to uncover the same answer the
    // front is giving.
    if (table == null) return _emptySheet();

    final facts = _facts;
    final selected = _sheet.selected;

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      // The band floats over the top of the reader, and a grid whose letters
      // are under it is a grid whose columns cannot be read. So the sheet
      // begins below the band and stays there, the way a spreadsheet keeps
      // its own toolbar above its letters. How far down that is depends on
      // where the reader put this body, which is why it is measured rather
      // than assumed.
      child: Padding(
        padding: EdgeInsets.only(top: _under),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (facts != null)
                  ParseStrip(
                    facts: facts,
                    onJumpToRagged: () {
                      final first = facts.firstRagged;
                      if (first != null) _jumpToRow(first - 1);
                    },
                  ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: kSheetTabCross,
                    switchInCurve: easeInOutQuad,
                    switchOutCurve: easeInOutQuad,
                    child: SheetGrid(
                      key: ValueKey<int>(index),
                      table: table,
                      selected: selected,
                      // What the bar covers is where a cell brought into
                      // view must not end up.
                      coveredBelow: selected == null
                          ? 0
                          : CellBar.heightFor(commented: _commented(selected)),
                      locked: widget.store.lock.holdsPage,
                      face: widget.face,
                      matches: _matchesOn(index),
                      raggedRows: facts?.raggedRows ?? const <int>{},
                      reveal: _reveal,
                      startAt: _sheet.panOf(index),
                      onSelect: (cell) =>
                          _sheet.selected = cell == selected ? null : cell,
                      onPanned: (pan, topRow, byHand) {
                        // The bar is a wide thing over a grid, so moving the
                        // grid by hand puts it away: what you are reading is
                        // the sheet again, not the cell you tapped a moment
                        // ago. A move the grid made itself, to bring a cell
                        // into view, leaves the choice that asked for it.
                        if (byHand && _sheet.selected != null) {
                          _sheet.selected = null;
                        }
                        _sheet.rememberPan(index, pan);
                        // A jump the grid is carrying out, or has carried
                        // out as far as a short sheet lets it, leaves the
                        // reader on the row they jumped to, whichever row
                        // the grid ends up with at its top. Only a hand
                        // moves them on from it.
                        if (byHand) _landing = null;
                        if (_landing != null) return;
                        _moveTo(_rowOffset(index) + topRow);
                      },
                    ),
                  ),
                ),
                // The sheets of a workbook sit along the foot, where a thumb
                // reaches and where the band over the top of the reader cannot
                // cover them.
                if (document.sections.length > 1)
                  SheetTabs(
                    names: <String>[
                      for (final section in document.sections) section.title,
                    ],
                    active: index,
                    onSelect: (next) => _sheet.sheet = next,
                    onAll: () => _allSheets(document, index),
                    locked: widget.store.lock.holdsPage,
                  ),
              ],
            ),
            // The bar rises out of the top of the sheets bar rather than
            // over it, so every sheet stays a tap away while a cell is being
            // read.
            if (_rise.valueAt(_barNow) > 0.001 || !_rise.restingAt(_barNow))
              Positioned(
                left: 0,
                right: 0,
                bottom: document.sections.length > 1 ? kSheetTabHeight : 0,
                child: ClipRect(
                  child: _cellBar(table, section.title, selected),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The bar for the ringed cell, held on screen while it leaves.
  Widget _cellBar(TableBlock table, String sheetName, SheetCell? selected) {
    final cell = selected == null
        ? _leaving
        : (_leaving = _BarText.of(table, sheetName, selected));
    if (cell == null) return const SizedBox.shrink();
    if (cell.comment != null) _said = cell;
    final said = _said;
    return CellBar(
      reference: cell.reference,
      value: cell.value,
      formula: cell.formula,
      comment: said?.comment,
      commentBy: said?.commentBy,
      noteOpen: _room.valueAt(_barNow).clamp(0.0, 1.0),
      progress: _rise.valueAt(_barNow).clamp(0.0, 1.0),
    );
  }

  Widget _emptySheet() => TornPage(
    size: const Size(kSheetWidth, kSheetHeight),
    label: kDocumentEmptyLabel,
  );
}

/// What a cell bar prints.
class _BarText {
  const _BarText(
    this.reference,
    this.value,
    this.formula,
    this.comment,
    this.commentBy,
  );

  final String reference;
  final String value;
  final String? formula;
  final String? comment;
  final String? commentBy;

  static _BarText of(TableBlock table, String sheetName, SheetCell at) {
    final cell = cellAt(table, at.row, at.column);
    return _BarText(
      cellReference(sheetName, at.column, at.row),
      cell == null ? '' : flattenCell(cell.text),
      cell?.formula,
      cell?.comment,
      cell?.commentBy,
    );
  }
}
