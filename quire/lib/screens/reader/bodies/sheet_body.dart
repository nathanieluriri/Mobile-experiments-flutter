import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import '../../../format/csv_parser.dart';
import '../../../model/document.dart';
import '../../../services/document_store.dart';
import '../../../theme/easings.dart';
import '../../../theme/metrics.dart';
import '../../../theme/springs.dart';
import '../sheet_surface.dart';
import 'cell_bar.dart';
import 'page_states.dart';
import 'parse_strip.dart';
import 'sheet_tabs.dart';
import 'spine_table.dart';

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
    this.matches = const <SheetCell>{},
  });

  final DocumentStore store;

  /// Cells the current query found, which colour their spine glyphs so that
  /// folding a column can never hide a result.
  final Set<SheetCell> matches;

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
    this.matches = const <SheetCell>{},
    this.face = SheetFace.front,
  });

  final DocumentStore store;
  final Set<SheetCell> matches;
  final SheetFace face;

  @override
  State<SheetView> createState() => _SheetViewState();
}

class _SheetViewState extends State<SheetView>
    with TickerProviderStateMixin {
  /// Both are built in [initState] rather than lazily on first use, because a
  /// sheet with no grid on it never reaches the part of the build that would
  /// touch them, and a controller that first exists inside [dispose] is a
  /// ticker created against a tree that has already gone.
  late final AnimationController _column;
  late final AnimationController _bar;

  /// The bar rises on its spring and leaves on a plain ease, because arriving
  /// is an object being lifted and leaving is a thing being put down.
  late final Curve _barRise = SpringCurve(
    AppSprings.valueBarSpring,
    duration: kCellBarIn,
    clampOvershoot: true,
  );

  final Map<int, ScrollController> _scrolls = <int, ScrollController>{};

  late SheetController _sheet;

  /// The column that is open and the one it took over from, which is the whole
  /// state the open animation runs on.
  int _open = 0;
  int _from = 0;

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

  @override
  void initState() {
    super.initState();
    _column = AnimationController(vsync: this, duration: kColumnOpen, value: 1)
      ..addListener(_repaint);
    _bar = AnimationController(
      vsync: this,
      duration: kCellBarIn,
      reverseDuration: kCellBarOut,
    )..addListener(_repaint);
    _sheet = SheetController.of(widget.store);
    _sheet.addListener(_onController);
    widget.store.addListener(_onStore);
    _open = _from = _sheet.openColumn;
    _shown = _sheetIndex;
    if (_sheet.selected != null) _bar.value = 1;
    _readParseFacts();
  }

  @override
  void dispose() {
    _sheet.removeListener(_onController);
    widget.store.removeListener(_onStore);
    for (final scroll in _scrolls.values) {
      scroll.dispose();
    }
    _column.dispose();
    _bar.dispose();
    super.dispose();
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
      // A workbook is one document, so stepping to another sheet moves the
      // reader through it: the folio chip and the fore edge have to agree
      // with the tab that is lit.
      _moveTo(_rowOffset(sheet) + _rowsScrolled(sheet));
    }
    final next = _sheet.openColumn;
    if (next != _open) {
      _from = _open;
      _open = next;
      _column.forward(from: 0);
    }
    if (_sheet.selected != null) {
      _bar.forward();
    } else {
      _bar.reverse();
    }
    _repaint();
  }

  /// How far down a sheet was left, in whole rows.
  int _rowsScrolled(int index) =>
      (_sheet.offsetOf(index) / kTableRowHeight).floor();

  /// Puts the reader at [row] of the whole document without the store's own
  /// notification bouncing back as a jump.
  void _moveTo(int row) {
    if (widget.store.position == row) return;
    _syncing = true;
    widget.store.position = row;
    _syncing = false;
  }

  /// Follows the reader when something outside the grid moves them, which is
  /// the fore edge scrub and the riffle.
  void _onStore() {
    if (_syncing || !mounted) return;
    final scroll = _scrolls[_sheetIndex];
    if (scroll == null || !scroll.hasClients) return;
    final target =
        ((widget.store.position - _rowOffset(_sheetIndex)) * kTableRowHeight)
            .clamp(0.0, scroll.position.maxScrollExtent);
    if ((scroll.position.pixels - target).abs() < 0.5) return;
    scroll.jumpTo(target);
  }

  QuireDocument? get _document => widget.store.document;

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

  ScrollController _scrollFor(int index) => _scrolls.putIfAbsent(
    index,
    () => ScrollController(initialScrollOffset: _sheet.offsetOf(index)),
  );

  bool _onScroll(ScrollNotification notification) {
    // A tab strip sliding sideways and a value being read across are not the
    // reader moving through the document, so neither reaches the shell.
    if (notification.metrics.axis == Axis.horizontal) return true;
    if (notification is! ScrollUpdateNotification) return false;
    final index = _sheetIndex;
    _sheet.rememberOffset(index, notification.metrics.pixels);
    if (_sheet.selected != null) _sheet.selected = null;
    final row = (notification.metrics.pixels / kTableRowHeight).floor();
    _moveTo(_rowOffset(index) + (row < 0 ? 0 : row));
    return false;
  }

  void _jumpToRow(int row) {
    final scroll = _scrolls[_sheetIndex];
    if (scroll == null || !scroll.hasClients) return;
    scroll.jumpTo(
      (row * kTableRowHeight).clamp(0.0, scroll.position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
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

    final columns = _columnCount(table);
    _sheet.startOn(index, math.min(table.frozenColumns, columns - 1));
    final rest = columnWidths(columns);
    final t = easeOutCubic.transform(_column.value);
    final widths = <double>[
      for (var c = 0; c < columns; c++)
        if (c == _open)
          lerpDouble(rest.spine, rest.open, t)!
        else if (c == _from)
          lerpDouble(rest.open, rest.spine, t)!
        else
          rest.spine,
    ];
    final offset = lerpDouble(
      openOffset(spineWidths(columns, open: _from), _from),
      openOffset(spineWidths(columns, open: _open), _open),
      t,
    )!;
    final facts = _facts;
    final selected = _sheet.selected;

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (document.sections.length > 1)
                SheetTabs(
                  names: <String>[
                    for (final section in document.sections) section.title,
                  ],
                  active: index,
                  onSelect: (next) => _sheet.sheet = next,
                ),
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
                  switchInCurve: easeOutQuad,
                  switchOutCurve: easeOutQuad,
                  child: SpineTable(
                    key: ValueKey<int>(index),
                    table: table,
                    widths: widths,
                    scales: columnScales(table, from: _bodyFrom(table)),
                    offset: offset,
                    scroll: _scrollFor(index),
                    face: widget.face,
                    selected: selected,
                    matches: widget.matches,
                    raggedRows: facts?.raggedRows ?? const <int>{},
                    onCellTap: (cell) => _sheet.selected =
                        cell == selected ? null : cell,
                    onSpineTap: (column) => _sheet.openColumn = column,
                  ),
                ),
              ),
            ],
          ),
          if (_bar.value > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _cellBar(table, section.title, selected),
            ),
        ],
      ),
    );
  }

  /// The bar for the ringed cell, held on screen while it leaves.
  Widget _cellBar(TableBlock table, String sheetName, SheetCell? selected) {
    final cell = selected == null
        ? _leaving
        : (_leaving = _BarText.of(table, sheetName, selected));
    if (cell == null) return const SizedBox.shrink();
    return CellBar(
      reference: cell.reference,
      value: cell.value,
      formula: cell.formula,
      progress: _bar.status == AnimationStatus.reverse
          ? easeOutQuad.transform(_bar.value)
          : _barRise.transform(_bar.value),
    );
  }

  int _columnCount(TableBlock table) {
    var columns = table.columns.length;
    for (final row in table.rows) {
      if (row.cells.length > columns) columns = row.cells.length;
    }
    return math.max(1, columns);
  }

  Widget _emptySheet() => TornPage(
    size: const Size(kSheetWidth, kSheetHeight),
    label: kDocumentEmptyLabel,
  );

  int _bodyFrom(TableBlock table) {
    if (table.frozenRows > 0) return table.frozenRows;
    if (table.rows.isNotEmpty && table.rows.first.header) return 1;
    return 0;
  }
}

/// The three things a cell bar prints.
class _BarText {
  const _BarText(this.reference, this.value, this.formula);

  final String reference;
  final String value;
  final String? formula;

  static _BarText of(TableBlock table, String sheetName, SheetCell at) {
    final cell = cellAt(table, at.row, at.column);
    return _BarText(
      cellReference(sheetName, at.column, at.row),
      cell == null ? '' : flattenCell(cell.text),
      cell?.formula,
    );
  }
}
