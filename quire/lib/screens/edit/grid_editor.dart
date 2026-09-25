import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../edit/csv_patch.dart';
import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';
import '../desk/desk_sheet.dart';
import '../reader/bodies/spine_table.dart' show columnLetter;
import 'action_pill.dart';
import 'edit_frame.dart';
import 'paragraph_editor.dart' show SaveEdit;

const double kGridRowHeight = 36.0;
const double kGridHeaderHeight = 30.0;

/// The bar above the grid never changes height, so picking a cell whose
/// value is long never moves the grid under the finger.
const double kGridBarHeight = 56.0;
const double kGridMinColumn = 72.0;
const double kGridMaxColumn = 240.0;
const double kGridGhostColumn = 96.0;

/// Empty rows and columns shown past the end of the data, so there is
/// always somewhere to type the next row the way a spreadsheet has.
const int kGridSpareRows = 30;
const int kGridSpareColumns = 4;

/// What is picked in the grid.
sealed class GridPick {
  const GridPick();
}

class CellPick extends GridPick {
  const CellPick(this.row, this.column);
  final int row;
  final int column;

  @override
  bool operator ==(Object other) =>
      other is CellPick && other.row == row && other.column == column;

  @override
  int get hashCode => Object.hash(row, column);
}

class RowPick extends GridPick {
  const RowPick(this.row);
  final int row;
}

class ColumnPick extends GridPick {
  const ColumnPick(this.column);
  final int column;
}

/// A CSV or TSV file edited cell by cell, the way a phone spreadsheet does
/// it: tap a cell to pick it, change it in the bar above the grid, and use
/// the row numbers and column letters to add and take away rows and
/// columns.
class GridEditor extends StatefulWidget {
  const GridEditor({
    super.key,
    required this.title,
    required this.bytes,
    required this.onSave,
    required this.onBack,
  });

  final String title;
  final Uint8List bytes;
  final SaveEdit onSave;
  final VoidCallback onBack;

  @override
  State<GridEditor> createState() => GridEditorState();
}

/// The rows and the column widths as they stood before a change.
typedef _Step = (List<CsvRow>, List<double>);

class GridEditorState extends State<GridEditor> with WidgetsBindingObserver {
  late final CsvDocument _doc = CsvDocument.read(widget.bytes);

  final List<_Step> _undo = <_Step>[];
  final List<_Step> _redo = <_Step>[];

  GridPick? _pick;
  bool _menu = false;
  String? _clipboard;

  final TextEditingController _field = TextEditingController();
  final FocusNode _focus = FocusNode();

  final ScrollController _across = ScrollController();
  final ScrollController _acrossHead = ScrollController();
  final ScrollController _down = ScrollController();
  final ScrollController _downHead = ScrollController();

  /// Each column's width, measured once when the file opens. Typing never
  /// changes them; adding or taking away a column adds or takes its own.
  late List<double> _widths = _measure();

  /// The file's first row stays in sight under the column letters, as the
  /// reader shows it, until it is unfrozen from its row menu.
  late bool _frozen = _doc.rowCount > 1;

  /// The columns the grid builds cells for: the ones in sight and a few
  /// either side, so a wide file costs what a narrow one does.
  final ValueNotifier<(int, int)> _inSight = ValueNotifier<(int, int)>((0, 12));
  final ScrollController _acrossFrozen = ScrollController();
  bool _saving = false;
  String? _problem;

  /// True while the bar holds words not yet kept in their cell.
  bool _typing = false;

  @visibleForTesting
  CsvDocument get document => _doc;

  @visibleForTesting
  GridPick? get pick => _pick;

  @visibleForTesting
  bool get editing => _focus.hasFocus;

  @visibleForTesting
  double get verticalOffset => _down.hasClients ? _down.offset : 0;

  @visibleForTesting
  double get horizontalOffset => _across.hasClients ? _across.offset : 0;

  @visibleForTesting
  bool get frozen => _frozen;

  @visibleForTesting
  List<double> get widths => _widths;

  int get _first => _frozen ? 1 : 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A menu stays with its cell, so it goes when the grid moves.
    _across.addListener(() {
      if (_acrossHead.hasClients) _acrossHead.jumpTo(_across.offset);
      if (_acrossFrozen.hasClients) _acrossFrozen.jumpTo(_across.offset);
      _placeSight();
      if (_menu) setState(() => _menu = false);
    });
    _down.addListener(() {
      if (_downHead.hasClients) _downHead.jumpTo(_down.offset);
      if (_menu) setState(() => _menu = false);
    });
    _focus.addListener(() {
      setState(() {});
      if (_focus.hasFocus) _revealSoon();
    });
    _field.addListener(() {
      final typing = _isTyping;
      if (typing != _typing) setState(() => _typing = typing);
      // The bar grows with long words; the cell stays in sight above it.
      if (_focus.hasFocus) _revealSoon();
    });
  }

  /// Works out which columns are in sight, and a few either side.
  void _placeSight() {
    if (!_across.hasClients) return;
    final left = _across.offset;
    final right = left + _across.position.viewportDimension;
    var x = 0.0;
    var from = 0, to = _columns - 1;
    var seen = false;
    for (var c = 0; c < _columns; c++) {
      final w = _width(c);
      if (!seen && x + w >= left) {
        from = c;
        seen = true;
      }
      if (x > right) {
        to = c;
        break;
      }
      x += w;
    }
    final next = (math.max(0, from - 2), math.min(_columns - 1, to + 2));
    if (next != _inSight.value) _inSight.value = next;
  }

  bool get _isTyping {
    final pick = _pick;
    return pick is CellPick &&
        _focus.hasFocus &&
        _field.text != _doc.cell(pick.row, pick.column);
  }

  /// The keyboard coming up keeps the cell being typed into in sight.
  @override
  void didChangeMetrics() {
    if (_focus.hasFocus) _revealSoon();
  }

  void _revealSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pick = _pick;
      if (mounted && pick is CellPick) _reveal(pick.row, pick.column);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _awaitingEnds?.cancel();
    _field.dispose();
    _focus.dispose();
    _across.dispose();
    _acrossHead.dispose();
    _down.dispose();
    _downHead.dispose();
    _acrossFrozen.dispose();
    _inSight.dispose();
    super.dispose();
  }

  int get _rows => _doc.rowCount + kGridSpareRows;
  int get _columns => math.max(_doc.columnCount + kGridSpareColumns, 6);

  /// Each column as wide as the widest of its first rows is drawn, within
  /// limits, so short columns stay narrow and long ones do not take the
  /// whole screen.
  List<double> _measure() {
    final out = <double>[];
    // Measured at the size the phone draws text, so a larger font setting
    // widens the columns rather than cutting what is in them.
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: MediaQuery.textScalerOf(context),
    );
    for (var c = 0; c < _doc.columnCount; c++) {
      // The longest few values are the only ones that can be the widest.
      final values = <(int, String)>[
        for (var r = 0; r < math.min(_doc.rowCount, 200); r++)
          (r, _doc.cell(r, c).replaceAll(RegExp(r'\s+'), ' ')),
      ]..sort((a, b) => b.$2.length.compareTo(a.$2.length));
      var widest = 0.0;
      for (final (row, value) in values.take(6)) {
        painter
          ..text = TextSpan(text: value, style: row == 0 ? AppText.cellHeader : AppText.cell)
          ..layout();
        widest = math.max(widest, painter.width);
      }
      final scale = MediaQuery.textScalerOf(context).scale(1);
      out.add((widest + 16 + 6).clamp(kGridMinColumn, kGridMaxColumn * scale).toDouble());
    }
    painter.dispose();
    return out;
  }

  double _width(int column) =>
      column < _widths.length ? _widths[column] : kGridGhostColumn;

  List<double> get _shown => <double>[
    for (var c = 0; c < _columns; c++) _width(c),
  ];

  double _left(int column) {
    var x = 0.0;
    for (var c = 0; c < column; c++) {
      x += _width(c);
    }
    return x;
  }

  double get _rowHeadWidth => math.max(40, '$_rows'.length * 9.0 + 20);

  // Changes.

  void _change(void Function() edit, {List<double>? widths}) {
    final before = _doc.rows;
    edit();
    if (identical(before, _doc.rows)) return;
    _undo.add((before, _widths));
    _redo.clear();
    _problem = null;
    setState(() => _widths = widths ?? _widths);
  }

  void undo() {
    if (_isTyping) commit();
    if (_undo.isEmpty) return;
    _redo.add((_doc.rows, _widths));
    _step(_undo.removeLast());
  }

  void redo() {
    if (_isTyping) commit();
    if (_redo.isEmpty) return;
    _undo.add((_doc.rows, _widths));
    _step(_redo.removeLast());
  }

  /// Puts the rows back to [to], and picks and shows the cell that changed,
  /// so each step shows what it did.
  void _step(_Step to) {
    final (rows, widths) = to;
    final changed = _firstDifference(_doc.rows, rows);
    setState(() {
      _doc.rows = rows;
      _widths = widths;
      _menu = false;
      if (changed != null) _pick = CellPick(changed.$1, changed.$2);
      _load();
    });
    if (changed != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reveal(changed.$1, changed.$2);
      });
    }
  }

  static (int, int)? _firstDifference(List<CsvRow> a, List<CsvRow> b) {
    final n = math.max(a.length, b.length);
    for (var r = 0; r < n; r++) {
      if (r >= a.length || r >= b.length) {
        return (math.min(r, math.max(0, b.length - 1)), 0);
      }
      if (identical(a[r], b[r])) continue;
      final x = a[r].cells, y = b[r].cells;
      for (var c = 0; c < math.max(x.length, y.length); c++) {
        if ((c < x.length ? x[c] : '') != (c < y.length ? y[c] : '')) {
          return (r, c);
        }
      }
    }
    return null;
  }

  /// Puts the picked cell's value in the bar.
  void _load() {
    final pick = _pick;
    final value = pick is CellPick ? _doc.cell(pick.row, pick.column) : '';
    _field.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  /// True for a row number or column letter past the end of the data,
  /// which has nothing to insert beside or take away.
  bool _spare(GridPick pick) => switch (pick) {
    RowPick(:final row) => row >= _doc.rowCount,
    ColumnPick(:final column) => column >= _doc.columnCount,
    _ => false,
  };

  void select(GridPick? pick, {bool edit = false}) {
    // Moving anywhere else keeps what was typed, as a spreadsheet does.
    if (_isTyping && pick != _pick) commit();
    final same = pick != null && pick == _pick;
    setState(() {
      _pick = pick;
      _menu = same && !edit && !_focus.hasFocus && pick is CellPick;
      if (pick is RowPick || pick is ColumnPick) _menu = !_spare(pick!);
      if (pick == null) _menu = false;
    });
    _load();
    if (edit && pick is CellPick) {
      _focus.requestFocus();
    } else if (pick is! CellPick) {
      _focus.unfocus();
    }
  }

  /// Keeps what is in the bar, and moves down a row when [down] is set, the
  /// way Enter does in a spreadsheet.
  void commit({bool down = false}) {
    final pick = _pick;
    if (pick is! CellPick) return;
    if (_field.text != _doc.cell(pick.row, pick.column)) {
      _change(() => _doc.setCell(pick.row, pick.column, _field.text));
    }
    if (down) {
      setState(() => _pick = CellPick(pick.row + 1, pick.column));
      _load();
      _reveal(pick.row + 1, pick.column);
    }
  }

  void cancel() {
    _load();
    _focus.unfocus();
  }

  void _reveal(int row, int column) {
    if (_down.hasClients && row >= _first) {
      final top = (row - _first) * kGridRowHeight;
      final view = _down.position.viewportDimension;
      if (top < _down.offset) {
        _down.jumpTo(top);
      } else if (top + kGridRowHeight > _down.offset + view) {
        _down.jumpTo(
          math.min(top + kGridRowHeight - view, _down.position.maxScrollExtent),
        );
      }
    }
    if (_across.hasClients) {
      final left = _left(column);
      final right = left + _width(column);
      final view = _across.position.viewportDimension;
      if (left < _across.offset) {
        _across.jumpTo(left);
      } else if (right > _across.offset + view) {
        _across.jumpTo(
          math.min(right - view, _across.position.maxScrollExtent),
        );
      }
    }
  }

  Future<void> copy() async {
    final pick = _pick;
    if (pick is! CellPick) return;
    _clipboard = _doc.cell(pick.row, pick.column);
    await Clipboard.setData(ClipboardData(text: _clipboard!));
    setState(() => _menu = false);
  }

  Future<void> cut() async {
    await copy();
    clear();
  }

  Future<void> paste() async {
    final pick = _pick;
    if (pick is! CellPick) return;
    var text = _clipboard;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? text;
    } on Object {
      // No clipboard on this platform: the last copy made here stands in.
    }
    if (text == null) return;
    // A block copied from another sheet, cells split by tabs and rows by
    // line breaks, is spread over the cells from the picked one on.
    final block = text.contains('\t') || text.trimRight().contains('\n')
        ? <List<String>>[
            for (final line in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n'))
              line.split('\t'),
          ]
        : null;
    if (block != null && block.length > 1 && block.last.length == 1 && block.last.single.isEmpty) {
      block.removeLast();
    }
    _change(() {
      if (block == null) {
        _doc.setCell(pick.row, pick.column, text!);
        return;
      }
      for (var r = 0; r < block.length; r++) {
        for (var c = 0; c < block[r].length; c++) {
          _doc.setCell(pick.row + r, pick.column + c, block[r][c]);
        }
      }
    });
    setState(() => _menu = false);
    _load();
  }

  void clear() {
    final pick = _pick;
    if (pick is! CellPick) return;
    _change(() => _doc.setCell(pick.row, pick.column, ''));
    setState(() => _menu = false);
    _load();
  }

  void insertRow({required bool below}) {
    final row = switch (_pick) {
      CellPick(:final row) => row,
      RowPick(:final row) => row,
      _ => null,
    };
    if (row == null) return;
    final at = below ? row + 1 : row;
    if (at > _doc.rowCount) return;
    _change(() => _doc.insertRow(at));
    select(below ? RowPick(row + 1) : RowPick(row));
  }

  void deleteRow() {
    final row = switch (_pick) {
      CellPick(:final row) => row,
      RowPick(:final row) => row,
      _ => null,
    };
    if (row == null || row >= _doc.rowCount) return;
    _change(() => _doc.deleteRow(row));
    select(null);
  }

  void insertColumn({required bool right}) {
    final column = switch (_pick) {
      CellPick(:final column) => column,
      ColumnPick(:final column) => column,
      _ => null,
    };
    if (column == null) return;
    final at = right ? column + 1 : column;
    if (at > _doc.columnCount) return;
    final widths = <double>[
      for (var c = 0; c < math.max(_doc.columnCount, _widths.length); c++)
        _width(c),
    ]..insert(at, kGridGhostColumn);
    _change(() => _doc.insertColumn(at), widths: widths);
    select(right ? ColumnPick(column + 1) : ColumnPick(column));
  }

  void deleteColumn() {
    final column = switch (_pick) {
      CellPick(:final column) => column,
      ColumnPick(:final column) => column,
      _ => null,
    };
    if (column == null || column >= _doc.columnCount) return;
    final widths = List<double>.of(_widths);
    if (column < widths.length) widths.removeAt(column);
    _change(() => _doc.deleteColumn(column), widths: widths);
    select(null);
  }

  /// The cell a second tap would make a double tap on, until the time for
  /// one runs out.
  CellPick? _awaiting;
  Timer? _awaitingEnds;

  /// A tap picks a cell, a second tap on it offers what can be done to it,
  /// and two taps in quick succession open it to be typed into. Told apart
  /// here rather than by a double tap recogniser, which would hold every
  /// single tap back to see whether a second one follows.
  void _tapCell(int row, int column) {
    if (_tapIsStop) return;
    final cell = CellPick(row, column);
    final quick = cell == _awaiting;
    _awaitingEnds?.cancel();
    _awaiting = quick ? null : cell;
    if (!quick) {
      _awaitingEnds = Timer(kDoubleTapTimeout, () => _awaiting = null);
    }
    select(cell, edit: quick);
  }

  /// A long press on a cell picks it and offers what can be done to it at
  /// once.
  void _holdCell(int row, int column) {
    if (_tapIsStop) return;
    select(CellPick(row, column));
    setState(() => _menu = true);
  }

  /// A drag on a picked column's edge begins: the widths before it are a
  /// step of their own to undo.
  void _widenStart() {
    _undo.add((_doc.rows, _widths));
    _redo.clear();
  }

  /// A column letter's edge dragged makes the column wider or narrower.
  void _widen(int column, double by) {
    setState(() {
      final widths = <double>[
        for (var c = 0; c < math.max(_widths.length, column + 1); c++)
          _width(c),
      ];
      widths[column] = (widths[column] + by).clamp(40.0, 640.0);
      _widths = widths;
      _menu = false;
    });
    _placeSight();
  }

  void _freeze(bool on) {
    setState(() {
      _frozen = on;
      _menu = false;
    });
  }

  /// What the cell's More actions sheet can do at [pick]: nothing past the
  /// end of the data, where there is no row or column to act on.
  Set<String> _moreFor(CellPick pick) => <String>{
        if (pick.row <= _doc.rowCount) 'rowAbove',
        if (pick.row < _doc.rowCount) 'rowBelow',
        if (pick.column <= _doc.columnCount) 'columnLeft',
        if (pick.column < _doc.columnCount) 'columnRight',
        if (pick.row < _doc.rowCount) 'deleteRow',
        if (pick.column < _doc.columnCount) 'deleteColumn',
      };

  Future<void> _more() async {
    setState(() => _menu = false);
    final pick = _pick;
    final can = pick is CellPick ? _moreFor(pick) : const <String>{};
    final choice = await showDeskSheet<String>(
      context,
      (context) => DeskSheet(
        title: 'Rows and columns',
        children: <Widget>[
          for (final (key, label, icon) in const <(String, String, IconData)>[
            (
              'rowAbove',
              'Insert a row above',
              LucideIcons.betweenHorizontalStart,
            ),
            (
              'rowBelow',
              'Insert a row below',
              LucideIcons.betweenHorizontalEnd,
            ),
            (
              'columnLeft',
              'Insert a column to the left',
              LucideIcons.betweenVerticalStart,
            ),
            (
              'columnRight',
              'Insert a column to the right',
              LucideIcons.betweenVerticalEnd,
            ),
            ('deleteRow', 'Delete this row', LucideIcons.trash2),
            ('deleteColumn', 'Delete this column', LucideIcons.trash2),
          ])
            if (can.contains(key))
            DeskSheetRow(
              label: label,
              icon: icon,
              destructive: key.startsWith('delete'),
              onTap: () => Navigator.of(context).pop(key),
            ),
        ],
      ),
    );
    switch (choice) {
      case 'rowAbove':
        insertRow(below: false);
      case 'rowBelow':
        insertRow(below: true);
      case 'columnLeft':
        insertColumn(right: false);
      case 'columnRight':
        insertColumn(right: true);
      case 'deleteRow':
        deleteRow();
      case 'deleteColumn':
        deleteColumn();
    }
  }

  Future<void> _save() async {
    commit();
    setState(() => _saving = true);
    final problem = await widget.onSave(
      _doc.write(),
      _undo.length == 1 ? 'One change' : '${_undo.length} changes',
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _problem = problem;
    });
  }

  String get _reference => switch (_pick) {
    CellPick(:final row, :final column) => '${columnLetter(column)}${row + 1}',
    RowPick(:final row) => 'Row ${row + 1}',
    ColumnPick(:final column) => columnLetter(column),
    null => '',
  };

  @override
  Widget build(BuildContext context) {
    return EditFrame(
      title: widget.title,
      onBack: widget.onBack,
      onSave: _save,
      canSave: _doc.touched || _typing,
      saving: _saving,
      covered: _menu,
      onUncover: () => setState(() => _menu = false),
      tools: <Widget>[
        EditButton(
          icon: LucideIcons.undo2,
          label: 'Undo',
          enabled: _undo.isNotEmpty || _typing,
          onTap: undo,
        ),
        const SizedBox(width: 6),
        EditButton(
          icon: LucideIcons.redo2,
          label: 'Redo',
          enabled: _redo.isNotEmpty,
          onTap: redo,
        ),
      ],
      note: _problem,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _bar(),
          Expanded(child: _grid()),
        ],
      ),
    );
  }

  Widget _bar() {
    final picked = _pick is CellPick;
    final type = AppText.bodyTight;
    final line = MediaQuery.textScalerOf(context).scale(type.fontSize ?? 14) * (type.height ?? 1.4);
    final one = math.max(kGridBarHeight, line + 2 * 12 + 12 + 2);
    return Container(
      // One line tall while a cell is only picked, so picking never moves
      // the grid; taller while typing, so the words and the caret show.
      constraints: BoxConstraints(
        minHeight: one,
        maxHeight: _focus.hasFocus ? double.infinity : one,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.hairline),
          bottom: BorderSide(color: AppColors.hairline),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 52),
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                _reference,
                key: const ValueKey<String>('grid-reference'),
                style: AppText.cellHeader.copyWith(color: AppColors.inkSoft),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // A picked row or column opens its first cell, where the grid
              // already is.
              onTap: () => switch (_pick) {
                RowPick(:final row) => select(CellPick(row, 0), edit: true),
                ColumnPick(:final column) => select(
                  CellPick(0, column),
                  edit: true,
                ),
                null => select(const CellPick(0, 0), edit: true),
                CellPick() => null,
              },
              child: AbsorbPointer(
                absorbing: !picked,
                child: EditField(
                  key: const ValueKey<String>('grid-field'),
                  controller: _field,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: _focus.hasFocus ? 4 : 1,
                  hint: picked ? 'Empty cell' : 'Tap a cell',
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => commit(down: true),
                  // Enter keeps the keyboard up for the next cell down, the
                  // way a spreadsheet goes on down a column.
                  onEditingComplete: () {},
                  style: AppText.bodyTight.copyWith(color: AppColors.ink),
                ),
              ),
            ),
          ),
          if (_focus.hasFocus) ...<Widget>[
            const SizedBox(width: 6),
            EditButton(icon: LucideIcons.x, label: 'Cancel', onTap: cancel),
            const SizedBox(width: 6),
            EditButton(
              icon: LucideIcons.check,
              label: 'Keep',
              chosen: true,
              onTap: () {
                commit();
                _focus.unfocus();
              },
            ),
          ],
        ],
      ),
    );
  }

  /// Moves the grid with a finger in any direction, across and down at once.
  void _panBy(Offset delta) {
    for (final (controller, by) in [(_across, delta.dx), (_down, delta.dy)]) {
      if (!controller.hasClients) continue;
      final p = controller.position;
      p.jumpTo((p.pixels - by).clamp(p.minScrollExtent, p.maxScrollExtent));
    }
  }

  void _fling(Offset velocity) {
    for (final (controller, speed) in [
      (_across, -velocity.dx),
      (_down, -velocity.dy),
    ]) {
      if (!controller.hasClients) continue;
      final p = controller.position;
      if (p is ScrollPositionWithSingleContext) p.goBallistic(speed);
    }
  }

  void _hold() {
    for (final controller in [_across, _down]) {
      if (controller.hasClients) {
        controller.position.jumpTo(controller.position.pixels);
      }
    }
  }

  /// True from a touch that stopped the grid sliding until that finger
  /// lifts: the touch was to stop it, not to pick what passed under it.
  bool _stopping = false;

  void _touchDown(PointerDownEvent event) {
    var sliding = false;
    for (final controller in [_across, _down]) {
      if (controller.hasClients &&
          controller.position.isScrollingNotifier.value) {
        sliding = true;
      }
    }
    _stopping = sliding;
    if (sliding) _hold();
  }

  bool get _tapIsStop {
    final stop = _stopping;
    _stopping = false;
    return stop;
  }

  Widget _grid() {
    final rowHead = _rowHeadWidth;
    final widths = _shown;
    final width = widths.fold<double>(0, (a, b) => a + b);
    final pick = _pick;
    return LayoutBuilder(
      builder: (context, box) => Stack(
        clipBehavior: Clip.hardEdge,
        children: <Widget>[
          Positioned.fill(child: _gridBody(rowHead, widths, width, pick)),
          if (_menu && pick != null) _menuFor(pick, box.biggest, rowHead),
        ],
      ),
    );
  }

  /// The grid lets no scrollable of its own take a drag: one pan moves it
  /// across and down together, and a fling carries on both ways.
  static const ScrollPhysics _panned = NeverScrollableScrollPhysics(
    parent: ClampingScrollPhysics(),
  );

  Widget _gridBody(
    double rowHead,
    List<double> widths,
    double width,
    GridPick? pick,
  ) {
    final frozen = _frozen ? kGridRowHeight : 0.0;
    final first = _first;
    Widget rowOf(int r) => ValueListenableBuilder<(int, int)>(
          valueListenable: _inSight,
          builder: (context, sight, _) => _GridRow(
            row: r,
            doc: _doc,
            widths: widths,
            from: sight.$1,
            to: sight.$2,
            pick: pick,
            typing: _focus.hasFocus ? _field : null,
            onTap: (column) => _tapCell(r, column),
            onHold: (column) => _holdCell(r, column),
          ),
        );
    Widget rowHeadOf(int r) => _Head(
          key: ValueKey<String>('row-$r'),
          label: '${r + 1}',
          width: rowHead,
          height: kGridRowHeight,
          lit: switch (pick) {
            CellPick(:final row) => row == r,
            RowPick(:final row) => row == r,
            _ => false,
          },
          chosen: pick is RowPick && pick.row == r,
          onTap: () {
            if (!_tapIsStop) select(RowPick(r));
          },
          onHold: () => select(RowPick(r)),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _placeSight();
    });
    return Listener(
      onPointerDown: _touchDown,
      child: GestureDetector(
        key: const ValueKey<String>('grid-pan'),
        onPanStart: (_) {
          _stopping = false;
          _hold();
        },
        onPanUpdate: (d) => _panBy(d.delta),
        onPanEnd: (d) => _fling(d.velocity.pixelsPerSecond),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: <Widget>[
            const Positioned.fill(child: ColoredBox(color: AppColors.page)),
            // The column letters, moving across with the grid.
            Positioned(
              left: rowHead,
              top: 0,
              right: 0,
              height: kGridHeaderHeight,
              child: SingleChildScrollView(
                controller: _acrossHead,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(
                  children: <Widget>[
                    for (var c = 0; c < _columns; c++)
                      _Head(
                        key: ValueKey<String>('column-$c'),
                        label: columnLetter(c),
                        width: widths[c],
                        height: kGridHeaderHeight,
                        lit: switch (pick) {
                          CellPick(:final column) => column == c,
                          ColumnPick(:final column) => column == c,
                          _ => false,
                        },
                        chosen: pick is ColumnPick && pick.column == c,
                        onTap: () {
                          if (!_tapIsStop) select(ColumnPick(c));
                        },
                        onHold: () => select(ColumnPick(c)),
                        // Only a picked column's edge sizes it, so a swipe
                        // across the letters always moves the grid.
                        onWidenStart: pick is ColumnPick && pick.column == c ? _widenStart : null,
                        onWiden: pick is ColumnPick && pick.column == c ? (by) => _widen(c, by) : null,
                      ),
                  ],
                ),
              ),
            ),
            // The row numbers, moving down with the grid.
            Positioned(
              left: 0,
              top: kGridHeaderHeight + frozen,
              width: rowHead,
              bottom: 0,
              child: ListView.builder(
                controller: _downHead,
                physics: const NeverScrollableScrollPhysics(),
                itemExtent: kGridRowHeight,
                itemCount: _rows - first,
                itemBuilder: (context, i) => rowHeadOf(i + first),
              ),
            ),
            Positioned(
              left: rowHead,
              top: kGridHeaderHeight + frozen,
              right: 0,
              bottom: 0,
              child: SingleChildScrollView(
                controller: _across,
                scrollDirection: Axis.horizontal,
                physics: _panned,
                child: SizedBox(
                  width: width,
                  child: ListView.builder(
                    key: const ValueKey<String>('grid-body'),
                    controller: _down,
                    physics: _panned,
                    itemExtent: kGridRowHeight,
                    itemCount: _rows - first,
                    itemBuilder: (context, i) => rowOf(i + first),
                  ),
                ),
              ),
            ),
            // The frozen first row, across with the grid and never down.
            if (_frozen) ...<Widget>[
              Positioned(
                left: rowHead,
                top: kGridHeaderHeight,
                right: 0,
                height: kGridRowHeight,
                child: DecoratedBox(
                  key: const ValueKey<String>('grid-frozen'),
                  position: DecorationPosition.foreground,
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFFB8B8B8), width: 2)),
                  ),
                  child: ColoredBox(
                    color: AppColors.page,
                    child: SingleChildScrollView(
                      controller: _acrossFrozen,
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: SizedBox(width: width, child: rowOf(0)),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: kGridHeaderHeight,
                width: rowHead,
                height: kGridRowHeight,
                child: rowHeadOf(0),
              ),
            ],
            Positioned(
              left: 0,
              top: 0,
              width: rowHead,
              height: kGridHeaderHeight,
              child: const _Corner(),
            ),
          ],
        ),
      ),
    );
  }

  /// Where row [row]'s top sits over the grid, the frozen row staying put.
  double _rowTop(int row, double down) => row < _first
      ? kGridHeaderHeight + row * kGridRowHeight
      : kGridHeaderHeight + _first * kGridRowHeight + (row - _first) * kGridRowHeight - down;

  Widget _menuFor(GridPick pick, Size room, double rowHead) {
    final across = _across.hasClients ? _across.offset : 0.0;
    final down = _down.hasClients ? _down.offset : 0.0;
    final Rect target;
    final List<PillAction> actions;
    switch (pick) {
      case CellPick(:final row, :final column):
        target = Rect.fromLTWH(
          rowHead + _left(column) - across,
          _rowTop(row, down),
          _width(column),
          kGridRowHeight,
        );
        actions = <PillAction>[
          PillAction('Cut', () => unawaited(cut())),
          PillAction('Copy', () => unawaited(copy())),
          PillAction('Paste', () => unawaited(paste())),
          PillAction('Clear', clear),
          if (_moreFor(pick).isNotEmpty)
            PillAction(
              'More actions',
              () => unawaited(_more()),
              icon: LucideIcons.ellipsisVertical,
            ),
        ];
      case RowPick(:final row):
        target = Rect.fromLTWH(
          0,
          _rowTop(row, down),
          rowHead,
          kGridRowHeight,
        );
        actions = <PillAction>[
          PillAction('Insert above', () => insertRow(below: false)),
          PillAction('Insert below', () => insertRow(below: true)),
          if (row < _doc.rowCount) PillAction('Delete', deleteRow),
          if (row == 0 && _doc.rowCount > 1) PillAction(_frozen ? 'Unfreeze' : 'Freeze', () => _freeze(!_frozen)),
        ];
      case ColumnPick(:final column):
        target = Rect.fromLTWH(
          rowHead + _left(column) - across,
          0,
          _width(column),
          kGridHeaderHeight,
        );
        actions = <PillAction>[
          PillAction('Insert left', () => insertColumn(right: false)),
          PillAction('Insert right', () => insertColumn(right: true)),
          if (column < _doc.columnCount) PillAction('Delete', deleteColumn),
        ];
    }
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: PillPlacement(target),
        child: ActionPill(
          key: const ValueKey<String>('grid-actions'),
          actions: actions,
        ),
      ),
    );
  }
}

class _Corner extends StatelessWidget {
  const _Corner();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      color: Color(0xFFEDEDED),
      border: Border(
        right: BorderSide(color: Color(0xFFCFCFCF)),
        bottom: BorderSide(color: Color(0xFFCFCFCF)),
      ),
    ),
  );
}

/// A column letter or a row number.
class _Head extends StatelessWidget {
  const _Head({
    super.key,
    required this.label,
    required this.width,
    required this.height,
    required this.lit,
    required this.chosen,
    required this.onTap,
    this.onHold,
    this.onWidenStart,
    this.onWiden,
  });

  final String label;
  final double width;
  final double height;
  final bool lit;
  final bool chosen;
  final VoidCallback onTap;

  /// A touch and hold, which opens the menu while the finger is still down.
  final VoidCallback? onHold;

  /// Called with how far the column's right edge is dragged.
  final ValueChanged<double>? onWiden;
  final VoidCallback? onWidenStart;

  @override
  Widget build(BuildContext context) {
    final widen = onWiden;
    final hold = onHold;
    final face = _face();
    final head = hold == null
        ? face
        : GestureDetector(onLongPress: hold, behavior: HitTestBehavior.translucent, child: face);
    if (widen == null) return head;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: <Widget>[
          Positioned.fill(child: head),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 14,
            child: GestureDetector(
              key: ValueKey<String>('widen-$label'),
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => onWidenStart?.call(),
              onHorizontalDragUpdate: (d) => widen(d.delta.dx),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _face() {
    return PaperPress(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: chosen
              ? AppColors.accent
              : lit
              ? const Color(0xFFDCD3F2)
              : const Color(0xFFEDEDED),
          border: const Border(
            right: BorderSide(color: Color(0xFFCFCFCF)),
            bottom: BorderSide(color: Color(0xFFCFCFCF)),
          ),
        ),
        child: Text(
          label,
          style: AppText.cellHeader.copyWith(
            color: chosen ? AppColors.onAccent : const Color(0xFF5F5F5F),
          ),
        ),
      ),
    );
  }
}

/// One row of cells.
class _GridRow extends StatelessWidget {
  const _GridRow({
    required this.row,
    required this.doc,
    required this.widths,
    required this.from,
    required this.to,
    required this.pick,
    required this.typing,
    required this.onTap,
    required this.onHold,
  });

  final int row;
  final CsvDocument doc;
  final List<double> widths;

  /// The columns built: those in sight, and a few either side.
  final int from;
  final int to;
  final GridPick? pick;

  /// The bar being typed in, whose words the picked cell shows as they come.
  final ValueListenable<TextEditingValue>? typing;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onHold;

  int _columnAt(double x) {
    var left = 0.0;
    for (var c = 0; c < widths.length; c++) {
      left += widths[c];
      if (x < left) return c;
    }
    return widths.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final pick = this.pick;
    final rowPicked = pick is RowPick && pick.row == row;
    final last = math.min(to, widths.length - 1);
    var before = 0.0;
    for (var c = 0; c < from && c < widths.length; c++) {
      before += widths[c];
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => onTap(_columnAt(d.localPosition.dx)),
      onLongPressStart: (d) => onHold(_columnAt(d.localPosition.dx)),
      child: Row(
        children: <Widget>[
          SizedBox(width: before),
          for (var c = from; c <= last; c++)
            if (typing != null &&
                pick is CellPick &&
                pick.row == row &&
                pick.column == c)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: typing!,
                builder: (context, value, _) => _Cell(
                  value: value.text,
                  width: widths[c],
                  header: row == 0,
                  picked: true,
                  washed: false,
                ),
              )
            else
              _Cell(
                value: doc.cell(row, c),
                width: widths[c],
                header: row == 0,
                picked: pick is CellPick && pick.row == row && pick.column == c,
                washed: rowPicked || (pick is ColumnPick && pick.column == c),
              ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.value,
    required this.width,
    required this.header,
    required this.picked,
    required this.washed,
  });

  final String value;
  final double width;
  final bool header;
  final bool picked;
  final bool washed;

  @override
  Widget build(BuildContext context) {
    final number =
        !header && num.tryParse(value.trim().replaceAll(',', '')) != null;
    return Container(
      width: width,
      height: kGridRowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: number ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: washed ? const Color(0xFFEDE7FA) : null,
        border: picked
            ? Border.all(color: AppColors.accent, width: 2)
            : const Border(
                right: BorderSide(color: Color(0xFFE2E2E2)),
                bottom: BorderSide(color: Color(0xFFE2E2E2)),
              ),
      ),
      child: Text(
        value.replaceAll(RegExp(r'\s+'), ' '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: (header ? AppText.cellHeader : AppText.cell).copyWith(
          color: AppColors.pageInk,
        ),
      ),
    );
  }
}
