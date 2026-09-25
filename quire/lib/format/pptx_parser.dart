import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../model/document.dart';

/// English Metric Units per logical point. PowerPoint states every position
/// and every size in these, and a deck read without the conversion is a deck
/// drawn as a single dot.
const double kEmuPerPoint = 12700.0;

/// The stage PowerPoint falls back to, in points: the old four by three.
///
/// It is only reached by a file whose presentation part forgot to say, which
/// is rare and still better answered with a stage than with nothing.
const double kDefaultSlideWidth = 720.0;
const double kDefaultSlideHeight = 540.0;

/// The size a run of slide text has when nothing in the file says.
const double kSlideTextSize = 18.0;

/// How a paragraph or a run of slide text is set, once everything up its
/// chain of placeholder, layout, master and list style has been laid down.
class SlideTextLook {
  const SlideTextLook({
    required this.size,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.colour,
    this.align = DocAlign.start,
    this.bulleted = false,
    this.ordered = false,
    this.level = 0,
    this.bullet,
  });

  /// Points.
  final double size;
  final bool bold;
  final bool italic;
  final bool underline;

  /// 0xAARRGGBB, or null for the slide's ink.
  final int? colour;
  final DocAlign align;
  final bool bulleted;
  final bool ordered;
  final int level;

  /// The glyph a bulleted paragraph is drawn with.
  final String? bullet;
}

/// How the words of one shape are set: the look each outline level has
/// before a paragraph says anything, and each paragraph and run as it is.
class SlideTextLooks {
  const SlideTextLooks(this.levels, this.paragraphs);

  /// Levels 0 to 8.
  final List<SlideTextLook> levels;
  final List<(SlideTextLook, List<SlideTextLook>)> paragraphs;
}

/// Something on a slide that can be picked up: a shape, a picture, a table
/// or chart, a connector or a group, at the top level of the slide.
class SlideObject {
  const SlideObject({
    required this.id,
    required this.kind,
    required this.box,
    this.rotation = 0,
    this.flipH = false,
    this.flipV = false,
    this.placeholder,
    this.name = '',
    this.hasText = false,
  });

  final int id;

  /// 'sp', 'pic', 'graphicFrame', 'grpSp' or 'cxnSp'.
  final String kind;
  final SlideBox box;
  final double rotation;
  final bool flipH;
  final bool flipV;

  /// The placeholder type the object fills, such as 'title' or 'body'.
  final String? placeholder;
  final String name;

  /// True for a shape whose words can be typed.
  final bool hasText;

  bool get isPicture => kind == 'pic';
  bool get isLine => kind == 'cxnSp';
}

/// One layout a slide can be built on.
class SlideLayoutInfo {
  const SlideLayoutInfo(this.path, this.name, this.master, this.type);
  final String path;
  final String name;
  final String master;

  /// PowerPoint's name for what the layout is for, such as 'title' or 'obj'.
  final String? type;
}

/// The defaults in force for one outline level of one text body.
///
/// PowerPoint says almost nothing on the slide itself. A line of body text
/// takes its size from the layout, which takes it from the master, which takes
/// it from the master's own list styles, and a bullet is usually named in none
/// of those places and simply inherited. This is the accumulator that walk
/// fills in, so a slide's own run properties are laid over a complete answer
/// rather than over nothing.
class _Level {
  double? size;
  bool? bold;
  bool? italic;
  bool? underline;
  DocAlign? align;
  int? colour;

  /// The glyph a bullet is drawn with, or null where none has been named.
  String? bullet;

  /// True for a numbered list, false for a glyph, null where nothing is said.
  bool? ordered;

  /// True when something in the chain said this level carries no bullet at
  /// all, which is what a title says and what a body paragraph says when its
  /// author turned the bullet off.
  bool? plain;

  void layer(_Level over) {
    size = over.size ?? size;
    bold = over.bold ?? bold;
    italic = over.italic ?? italic;
    underline = over.underline ?? underline;
    align = over.align ?? align;
    colour = over.colour ?? colour;
    if (over.plain == true) {
      plain = true;
      bullet = null;
      ordered = null;
    } else if (over.bullet != null || over.ordered != null) {
      plain = false;
      bullet = over.bullet ?? bullet;
      ordered = over.ordered ?? ordered;
    }
  }

  _Level copy() => _Level()
    ..size = size
    ..bold = bold
    ..italic = italic
    ..underline = underline
    ..align = align
    ..colour = colour
    ..bullet = bullet
    ..ordered = ordered
    ..plain = plain;
}

/// One placeholder as a layout or a master describes it: where it sits, how
/// its text is set, and which way its words are anchored in the box.
class _Slot {
  SlideBox? box;
  DocVerticalAlign? anchor;
  double? rotation;
  final Map<int, _Level> levels = <int, _Level>{};
}

/// A layout or a master, read once and kept.
///
/// A deck of forty slides stands on two or three of these, and reparsing the
/// master per slide is the difference between opening a deck and waiting for
/// one.
class _Frame {
  _Frame(this.path);
  final String path;

  /// The part this one inherits from: a layout's master, or nothing.
  String? parent;

  /// Placeholders by `type:idx`, and again by type alone, because a slide
  /// matches on the index where it has one and on the type where it does not.
  final Map<String, _Slot> byKey = <String, _Slot>{};
  final Map<String, _Slot> byType = <String, _Slot>{};

  /// The master's own list styles, which is where most body text is really
  /// set. Keyed by 'title', 'body' and 'other'.
  final Map<String, Map<int, _Level>> textStyles = <String, Map<int, _Level>>{};

  int? background;
  String? backgroundAsset;

  /// The theme colours this part resolves scheme names against, already run
  /// through the master's colour map.
  Map<String, int> colours = const <String, int>{};

  /// Everything on the part that is not a placeholder: the decoration a slide
  /// inherits without owning, which is what most branded decks are made of.
  final List<SlideShape> furniture = <SlideShape>[];
}

/// Reads a .pptx into [QuireDocument]: one section per slide, each holding one
/// [SlideBlock].
///
/// A slide is the one thing in this app's world that is laid out rather than
/// flowed, so unlike the Word and Markdown bridges this one keeps geometry.
/// Almost all of the work is inheritance. A shape on a slide routinely says
/// only what it holds; where it sits, how big its words are and whether they
/// carry a bullet are all somewhere up a chain of layout, master and theme,
/// and a parser that reads only the slide produces a deck of unstyled text
/// piled in the top left corner.
///
/// Throws [ArchiveException] when the bytes are not a readable zip, and
/// [FormatException] when they are a zip with no presentation inside. Both are
/// caught at the loader boundary and become a designed state.
class PptxParser {
  PptxParser(
    this.bytes, {
    this.parts,
    this.media = const <String, Uint8List>{},
    Archive? archive,
    this.loadMedia = true,
  }) : _given = archive;
  final Uint8List bytes;
  final Archive? _given;

  /// False when [media] already holds every picture the deck has, so the
  /// zip's pictures are not read again.
  final bool loadMedia;

  /// The text of a part as an editor holds it now, or null to read the one
  /// in [bytes].
  final String? Function(String path)? parts;

  /// Media an editor has added, by path.
  final Map<String, Uint8List> media;

  late Archive _zip;
  bool _opened = false;
  final Map<String, Uint8List> _assets = <String, Uint8List>{};
  final Map<String, _Frame> _frames = <String, _Frame>{};
  final Map<String, Map<String, String>> _rels =
      <String, Map<String, String>>{};
  final Map<String, Map<String, int>> _themes = <String, Map<String, int>>{};

  /// Placeholder slots already merged down the chain, keyed by the layout and
  /// the placeholder, so a deck of forty slides resolves each one once.
  final Map<String, _Slot> _slots = <String, _Slot>{};

  double _slideWidth = kDefaultSlideWidth;
  double _slideHeight = kDefaultSlideHeight;

  // Reading the container.

  static String _ln(XmlElement e) => e.name.local;

  static Iterable<XmlElement> _kids(XmlElement e, String local) =>
      e.childElements.where((c) => _ln(c) == local);

  static XmlElement? _kid(XmlElement e, String local) {
    for (final c in e.childElements) {
      if (_ln(c) == local) return c;
    }
    return null;
  }

  /// The first descendant with this name, at any depth.
  static XmlElement? _find(XmlElement e, String local) {
    for (final c in e.childElements) {
      if (_ln(c) == local) return c;
      final deeper = _find(c, local);
      if (deeper != null) return deeper;
    }
    return null;
  }

  /// Attribute lookup ignoring the namespace prefix, because the same
  /// attribute arrives prefixed or bare depending on which tool wrote the
  /// file.
  static String? _at(XmlElement e, String local) {
    for (final a in e.attributes) {
      if (a.name.local == local) return a.value;
    }
    return null;
  }

  /// The relationship id an element names, as against its own `id`, which
  /// a slide list entry carries too, bare, and first.
  static String? _relId(XmlElement e) {
    for (final a in e.attributes) {
      if (a.name.local == 'id' && a.name.prefix != null) return a.value;
    }
    return null;
  }

  String? _text(String path) {
    final over = parts?.call(path);
    if (over != null) return over;
    final file = _zip.find(path);
    if (file == null) return null;
    return utf8.decode(file.content, allowMalformed: true);
  }

  XmlElement? _root(String path) {
    final xml = _text(path);
    if (xml == null) return null;
    try {
      return XmlDocument.parse(xml).rootElement;
    } on XmlException {
      // One unreadable part of a deck is a slide that comes back thin, not a
      // deck that refuses to open. The presentation part is the exception, and
      // its caller checks it.
      return null;
    }
  }

  /// The relationships of one part, as absolute paths inside the container.
  Map<String, String> _relsOf(String part) {
    final held = _rels[part];
    if (held != null) return held;
    final cut = part.lastIndexOf('/');
    final dir = cut < 0 ? '' : part.substring(0, cut);
    final file = cut < 0 ? part : part.substring(cut + 1);
    final root = _root('$dir/_rels/$file.rels');
    final map = <String, String>{};
    if (root != null) {
      for (final r in root.childElements) {
        final id = _at(r, 'Id');
        final target = _at(r, 'Target');
        if (id == null || target == null) continue;
        if (_at(r, 'TargetMode') == 'External') continue;
        map[id] = _resolve(dir, target);
      }
    }
    _rels[part] = map;
    return map;
  }

  /// A relationship target read against the directory of the part that names
  /// it.
  static String _resolve(String dir, String target) {
    if (target.startsWith('/')) return target.substring(1);
    final parts = <String>[...dir.split('/').where((s) => s.isNotEmpty)];
    for (final step in target.split('/')) {
      if (step == '.' || step.isEmpty) continue;
      if (step == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(step);
    }
    return parts.join('/');
  }

  // The parse.

  XmlElement _open() {
    if (!_opened) {
      _zip = _given ?? ZipDecoder().decodeBytes(bytes);
      if (loadMedia) {
        _loadMedia();
      } else {
        _assets.addAll(media);
      }
      _opened = true;
    }
    final root = _root('ppt/presentation.xml');
    if (root == null) throw const FormatException('no ppt/presentation.xml');
    _readStage(root);
    return root;
  }

  /// The deck's slide parts, in the order it presents them.
  List<String> slideParts() => _slideOrder(_open());

  /// The slide at [path], drawn as the reader draws it, with each shape
  /// carrying the id it has in the file and empty placeholders kept.
  SlideBlock slideAt(String path, {int index = 0}) {
    _open();
    return _slide(path, index).blocks.single as SlideBlock;
  }

  /// The deck's media, as the slides refer to it.
  Map<String, Uint8List> get assets {
    _open();
    return _assets;
  }

  QuireDocument parse({String title = 'Presentation'}) {
    final root = _open();
    final order = _slideOrder(root);
    if (order.isEmpty) throw const FormatException('a deck with no slides');

    final sections = <DocSection>[];
    final outline = <OutlineEntry>[];
    for (var i = 0; i < order.length; i++) {
      final slide = _slide(order[i], i);
      sections.add(slide);
      outline.add(OutlineEntry(slide.title, 1, i, 0));
    }

    return QuireDocument(
      title: title,
      sections: sections,
      assets: _assets,
      sourceFormat: 'pptx',
      outline: outline,
    );
  }

  void _loadMedia() {
    for (final f in _zip.files) {
      if (!f.isFile) continue;
      if (!f.name.startsWith('ppt/media/')) continue;
      _assets[f.name] = Uint8List.fromList(f.content as List<int>);
    }
    _assets.addAll(media);
  }

  /// The stage every slide is laid out on, in points.
  void _readStage(XmlElement presentation) {
    final size = _kid(presentation, 'sldSz');
    if (size == null) return;
    final cx = double.tryParse(_at(size, 'cx') ?? '');
    final cy = double.tryParse(_at(size, 'cy') ?? '');
    if (cx != null && cx > 0) _slideWidth = cx / kEmuPerPoint;
    if (cy != null && cy > 0) _slideHeight = cy / kEmuPerPoint;
  }

  /// The slide parts, in the order the deck presents them.
  ///
  /// The order lives in the presentation part and nowhere else. Sorting the
  /// zip entries by name instead puts slide10 between slide1 and slide2, which
  /// is a deck nobody can follow.
  List<String> _slideOrder(XmlElement presentation) {
    final rels = _relsOf('ppt/presentation.xml');
    final list = _kid(presentation, 'sldIdLst');
    final out = <String>[];
    if (list != null) {
      for (final id in _kids(list, 'sldId')) {
        final target = rels[_relId(id) ?? ''];
        if (target != null) out.add(target);
      }
    }
    if (out.isNotEmpty) return out;
    // A deck whose list is missing is still a deck: fall back to the parts
    // themselves, ordered by the number in the name rather than the name.
    final found = <String>[
      for (final f in _zip.files)
        if (RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(f.name)) f.name,
    ];
    found.sort((a, b) => _slideNumber(a).compareTo(_slideNumber(b)));
    return found;
  }

  static int _slideNumber(String path) {
    final match = RegExp(r'(\d+)\.xml$').firstMatch(path);
    return match == null ? 0 : int.parse(match.group(1)!);
  }

  // Layouts, masters and themes.

  _Frame? _frame(String path) {
    final held = _frames[path];
    if (held != null) return held;
    final root = _root(path);
    if (root == null) return null;
    final frame = _Frame(path);
    _frames[path] = frame;

    for (final entry in _relsOf(path).entries) {
      if (entry.value.contains('/slideMasters/')) frame.parent = entry.value;
    }
    frame.colours = _themeFor(path, root);

    final common = _kid(root, 'cSld');
    if (common != null) {
      _readBackground(common, frame);
      final tree = _kid(common, 'spTree');
      if (tree != null) _readSlots(tree, frame);
    }
    final styles = _kid(root, 'txStyles');
    if (styles != null) {
      for (final name in const <String>[
        'titleStyle',
        'bodyStyle',
        'otherStyle',
      ]) {
        final el = _kid(styles, name);
        if (el == null) continue;
        frame.textStyles[name.replaceAll('Style', '')] = _listStyle(
          el,
          frame.colours,
        );
      }
    }
    return frame;
  }

  /// The theme colours in force for a part, already run through the master's
  /// colour map.
  ///
  /// The map is the step everybody forgets. A theme names its colours dk1,
  /// lt1 and accent1, while a shape asks for tx1, bg1 or accent1, and the
  /// master is the only part that says which is which. Skipping it swaps every
  /// dark text colour for a light one, which is a deck of white text on white
  /// paper.
  Map<String, int> _themeFor(String part, XmlElement root) {
    final held = _themes[part];
    if (held != null) return held;
    var themePath = '';
    var mapFrom = part;
    for (final entry in _relsOf(part).entries) {
      if (entry.value.contains('/theme/')) themePath = entry.value;
      if (entry.value.contains('/slideMasters/')) mapFrom = entry.value;
    }
    if (themePath.isEmpty && mapFrom != part) {
      for (final entry in _relsOf(mapFrom).entries) {
        if (entry.value.contains('/theme/')) themePath = entry.value;
      }
    }
    final scheme = <String, int>{};
    final theme = themePath.isEmpty ? null : _root(themePath);
    final list = theme == null ? null : _find(theme, 'clrScheme');
    if (list != null) {
      for (final slot in list.childElements) {
        final value = _colourOf(slot);
        if (value != null) scheme[_ln(slot)] = value;
      }
    }
    final mapRoot = mapFrom == part ? root : _root(mapFrom);
    final clrMap = mapRoot == null ? null : _find(mapRoot, 'clrMap');
    final out = <String, int>{...scheme};
    if (clrMap != null) {
      for (final a in clrMap.attributes) {
        final to = scheme[a.value];
        if (to != null) out[a.name.local] = to;
      }
    }
    // Four names every deck uses that a theme never states, because the format
    // calls them something else there.
    out['tx1'] ??= scheme['dk1'] ?? 0xFF000000;
    out['bg1'] ??= scheme['lt1'] ?? 0xFFFFFFFF;
    out['tx2'] ??= scheme['dk2'] ?? out['tx1']!;
    out['bg2'] ??= scheme['lt2'] ?? out['bg1']!;
    _themes[part] = out;
    return out;
  }

  void _readBackground(XmlElement common, _Frame frame) {
    final bg = _kid(common, 'bg');
    if (bg == null) return;
    final properties = _kid(bg, 'bgPr');
    if (properties != null) {
      frame.background = _solidFill(properties, frame.colours);
      frame.backgroundAsset = _pictureFill(properties, frame.path);
      return;
    }
    // A background stated as a reference into the theme's fill list. Only its
    // colour is taken: the fill styles themselves are gradients and textures
    // this reader does not draw, and the colour is the part that decides
    // whether the text on top can be read at all.
    final ref = _kid(bg, 'bgRef');
    if (ref != null) frame.background = _colourIn(ref, frame.colours);
  }

  /// Every placeholder a layout or master describes, and everything else on it
  /// as furniture.
  void _readSlots(XmlElement tree, _Frame frame) {
    for (final shape in tree.childElements) {
      final name = _ln(shape);
      if (name != 'sp' && name != 'pic' && name != 'graphicFrame') continue;
      final ph = _placeholderOf(shape);
      if (ph == null) {
        final drawn = _shape(shape, frame.path, frame.colours, null);
        if (drawn != null) frame.furniture.add(_asFurniture(drawn));
        continue;
      }
      final slot = _Slot()
        ..box = _boxOf(shape)
        ..rotation = _rotationOf(shape);
      final body = _kid(shape, 'txBody');
      if (body != null) {
        final properties = _kid(body, 'bodyPr');
        if (properties != null) slot.anchor = _anchorOf(properties);
        final list = _kid(body, 'lstStyle');
        if (list != null) slot.levels.addAll(_listStyle(list, frame.colours));
      }
      frame.byKey['${ph.type}:${ph.index}'] = slot;
      frame.byType.putIfAbsent(ph.type, () => slot);
    }
  }

  /// One `a:lstStyle`, or one of the master's text styles, level by level.
  Map<int, _Level> _listStyle(XmlElement el, Map<String, int> colours) {
    final out = <int, _Level>{};
    for (final child in el.childElements) {
      final match = RegExp(r'^lvl(\d)pPr$').firstMatch(_ln(child));
      if (match == null) continue;
      out[int.parse(match.group(1)!) - 1] = _paragraphStyle(child, colours);
    }
    return out;
  }

  /// The text defaults one `a:pPr` states, whether it is a paragraph's own or
  /// a level of a list style.
  _Level _paragraphStyle(XmlElement pPr, Map<String, int> colours) {
    final level = _Level();
    level.align = switch (_at(pPr, 'algn')) {
      'ctr' => DocAlign.center,
      'r' => DocAlign.end,
      'just' || 'dist' => DocAlign.justify,
      'l' => DocAlign.start,
      _ => null,
    };
    for (final child in pPr.childElements) {
      switch (_ln(child)) {
        case 'buNone':
          level.plain = true;
        case 'buChar':
          level.plain = false;
          level.ordered = false;
          level.bullet = _at(child, 'char') ?? '•';
        case 'buAutoNum':
          level.plain = false;
          level.ordered = true;
        case 'defRPr':
          final run = _runStyle(child, colours);
          level.size = run.size;
          level.bold = run.bold;
          level.italic = run.italic;
          level.underline = run.underline;
          level.colour = run.colour;
      }
    }
    return level;
  }

  /// What one `a:rPr` or `a:defRPr` says about its characters.
  _Level _runStyle(XmlElement rPr, Map<String, int> colours) {
    final level = _Level();
    // Sizes are in hundredths of a point, which is the other factor a deck can
    // be drawn wrong by.
    final size = double.tryParse(_at(rPr, 'sz') ?? '');
    if (size != null && size > 0) level.size = size / 100;
    final bold = _at(rPr, 'b');
    if (bold != null) level.bold = bold == '1' || bold == 'true';
    final italic = _at(rPr, 'i');
    if (italic != null) level.italic = italic == '1' || italic == 'true';
    final underline = _at(rPr, 'u');
    if (underline != null) level.underline = underline != 'none';
    level.colour = _solidFill(rPr, colours);
    return level;
  }

  static DocVerticalAlign? _anchorOf(XmlElement bodyPr) =>
      switch (_at(bodyPr, 'anchor')) {
        'ctr' => DocVerticalAlign.center,
        'b' => DocVerticalAlign.bottom,
        't' => DocVerticalAlign.top,
        _ => null,
      };

  // Colour.

  /// The colour of a `solidFill` directly inside [parent].
  int? _solidFill(XmlElement parent, Map<String, int> colours) {
    final fill = _kid(parent, 'solidFill');
    return fill == null ? null : _colourIn(fill, colours);
  }

  /// The one colour element inside [parent], with its modifiers applied.
  int? _colourIn(XmlElement parent, Map<String, int> colours) {
    for (final child in parent.childElements) {
      final value = _colourOf(child, colours);
      if (value != null) return value;
    }
    return null;
  }

  /// One colour element: literal, scheme, system or preset, and then whatever
  /// the file does to it afterwards.
  ///
  /// The modifiers are not decoration. A themed deck states one accent and
  /// then lightens it per slide with `lumMod` and `lumOff`, so a reader that
  /// drops them paints every tint of a colour as the colour itself and loses
  /// the whole of the deck's shading.
  int? _colourOf(XmlElement el, [Map<String, int> colours = const {}]) {
    int? base;
    switch (_ln(el)) {
      case 'srgbClr':
        base = _hex(_at(el, 'val'));
      case 'sysClr':
        base = _hex(_at(el, 'lastClr'));
      case 'schemeClr':
        base = colours[_at(el, 'val') ?? ''];
      case 'prstClr':
        base = _presetColours[_at(el, 'val') ?? ''];
      default:
        // A wrapper such as one of `a:clrScheme`'s named slots, which holds
        // the real element one deeper.
        for (final child in el.childElements) {
          final inner = _colourOf(child, colours);
          if (inner != null) return inner;
        }
        return null;
    }
    if (base == null) return null;
    var value = base;
    for (final mod in el.childElements) {
      final amount = _percent(_at(mod, 'val'));
      if (amount == null) continue;
      switch (_ln(mod)) {
        case 'alpha':
          value = _withAlpha(value, amount);
        case 'lumMod':
        case 'shade':
          value = _scale(value, amount);
        case 'lumOff':
          value = _lighten(value, amount);
        case 'tint':
          value = _tint(value, amount);
      }
    }
    return value;
  }

  static int? _hex(String? value) {
    if (value == null || value.length != 6) return null;
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? null : 0xFF000000 | parsed;
  }

  /// A drawing percentage, stated either in thousandths of a percent or with a
  /// trailing sign, and returned as a fraction.
  static double? _percent(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value.endsWith('%')) {
      final parsed = double.tryParse(value.substring(0, value.length - 1));
      return parsed == null ? null : parsed / 100;
    }
    final parsed = double.tryParse(value);
    return parsed == null ? null : parsed / 100000;
  }

  static int _withAlpha(int colour, double amount) =>
      (colour & 0x00FFFFFF) | ((255 * amount.clamp(0.0, 1.0)).round() << 24);

  static int _scale(int colour, double amount) =>
      _rgb(colour, (channel) => (channel * amount).round().clamp(0, 255));

  static int _lighten(int colour, double amount) =>
      _rgb(colour, (channel) => (channel + 255 * amount).round().clamp(0, 255));

  static int _tint(int colour, double amount) => _rgb(
    colour,
    (channel) => (channel * amount + 255 * (1 - amount)).round().clamp(0, 255),
  );

  static int _rgb(int colour, int Function(int) each) {
    final a = (colour >> 24) & 0xFF;
    final r = each((colour >> 16) & 0xFF);
    final g = each((colour >> 8) & 0xFF);
    final b = each(colour & 0xFF);
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  /// The few preset names that turn up in decks written by tools other than
  /// PowerPoint. The full list is a hundred and forty names nobody uses.
  static const Map<String, int> _presetColours = <String, int>{
    'black': 0xFF000000,
    'white': 0xFFFFFFFF,
    'red': 0xFFFF0000,
    'green': 0xFF008000,
    'blue': 0xFF0000FF,
    'yellow': 0xFFFFFF00,
    'gray': 0xFF808080,
    'grey': 0xFF808080,
    'darkGray': 0xFFA9A9A9,
    'lightGray': 0xFFD3D3D3,
  };

  // Slides.

  DocSection _slide(String path, int index) {
    final root = _root(path);
    var layoutPath = '';
    var notesPath = '';
    for (final entry in _relsOf(path).entries) {
      if (entry.value.contains('/slideLayouts/')) layoutPath = entry.value;
      if (entry.value.contains('/notesSlides/')) notesPath = entry.value;
    }
    final layout = layoutPath.isEmpty ? null : _frame(layoutPath);
    final parent = layout?.parent;
    final master = parent == null ? null : _frame(parent);
    final colours = layout?.colours ?? master?.colours ?? const <String, int>{};

    final shapes = <SlideShape>[];
    int? background;
    String? backgroundAsset;

    if (root != null) {
      final common = _kid(root, 'cSld');
      if (common != null) {
        final own = _Frame(path)..colours = colours;
        _readBackground(common, own);
        background = own.background;
        backgroundAsset = own.backgroundAsset;
        final tree = _kid(common, 'spTree');
        if (tree != null) {
          shapes.addAll(_shapesIn(tree, path, colours, layout, master));
        }
      }
    }

    // A slide that says nothing about its ground takes the layout's, then the
    // master's. A deck's whole look usually lives one of those two steps up.
    background ??= layout?.background ?? master?.background;
    backgroundAsset ??= layout?.backgroundAsset ?? master?.backgroundAsset;

    final block = SlideBlock(
      width: _slideWidth,
      height: _slideHeight,
      // Whatever the master and the layout draw goes underneath, so a branded
      // rule or panel the slide inherits without owning is not lost.
      shapes: <SlideShape>[
        ...?master?.furniture,
        ...?layout?.furniture,
        ...shapes,
      ],
      background: background,
      backgroundAsset: backgroundAsset,
      notes: notesPath.isEmpty
          ? const <DocBlock>[]
          : _notes(notesPath, colours),
      layoutName: layout == null ? null : _nameOf(layout.path),
    );
    final named = block.title;
    return DocSection(
      named == null || named.isEmpty ? 'Slide ${index + 1}' : named,
      <DocBlock>[block],
      kind: 'slide',
    );
  }

  /// The same shape, marked as one the slide inherits rather than owns.
  static SlideShape _asFurniture(SlideShape shape) =>
      shape.copyWith(inherited: true);

  static String _nameOf(String path) {
    final cut = path.lastIndexOf('/');
    final file = cut < 0 ? path : path.substring(cut + 1);
    return file.replaceAll('.xml', '');
  }

  List<SlideShape> _shapesIn(
    XmlElement tree,
    String part,
    Map<String, int> colours,
    _Frame? layout,
    _Frame? master, {
    int? group,
  }) {
    final out = <SlideShape>[];
    for (final el in tree.childElements) {
      switch (_ln(el)) {
        case 'sp':
        case 'pic':
        case 'graphicFrame':
        case 'cxnSp':
          final shape = _shape(
            el,
            part,
            colours,
            _slotFor(el, layout, master),
            master,
            group ?? idOf(el),
          );
          if (shape != null) out.add(shape);
        case 'grpSp':
          // A group states its own frame and its children state theirs in the
          // group's own coordinates, which is a transform this reader does not
          // carry. Taking the children at face value keeps their content and
          // their rough arrangement, and loses only the group's offset.
          final inner = _shapesIn(
            el,
            part,
            colours,
            layout,
            master,
            group: group ?? idOf(el),
          );
          out.addAll(inner.map(_groupPlacer(el)));
      }
    }
    return out;
  }

  /// Where a group puts its children: from the group's own coordinates, its
  /// child offset and extent, into the slide's, turned with the group.
  static SlideShape Function(SlideShape) _groupPlacer(XmlElement group) {
    final properties = _kid(group, 'grpSpPr');
    final transform = properties == null ? null : _kid(properties, 'xfrm');
    if (transform == null) return (shape) => shape;
    double at(String kid, String name) =>
        (double.tryParse(_at(_kid(transform, kid) ?? transform, name) ?? '') ??
            0) /
        kEmuPerPoint;
    final x = at('off', 'x'), y = at('off', 'y');
    final cx = at('ext', 'cx'), cy = at('ext', 'cy');
    final hasChild = _kid(transform, 'chOff') != null;
    final chX = hasChild ? at('chOff', 'x') : x;
    final chY = hasChild ? at('chOff', 'y') : y;
    final chCx = _kid(transform, 'chExt') != null ? at('chExt', 'cx') : cx;
    final chCy = _kid(transform, 'chExt') != null ? at('chExt', 'cy') : cy;
    final sx = chCx > 0 ? cx / chCx : 1.0;
    final sy = chCy > 0 ? cy / chCy : 1.0;
    final turn = (double.tryParse(_at(transform, 'rot') ?? '') ?? 0) / 60000;
    final centreX = x + cx / 2, centreY = y + cy / 2;
    return (shape) {
      final b = shape.box;
      var left = x + (b.left - chX) * sx;
      var top = y + (b.top - chY) * sy;
      final width = b.width * sx, height = b.height * sy;
      if (turn != 0) {
        final radians = turn * math.pi / 180;
        final dx = left + width / 2 - centreX, dy = top + height / 2 - centreY;
        final cos = math.cos(radians), sin = math.sin(radians);
        left = centreX + dx * cos - dy * sin - width / 2;
        top = centreY + dx * sin + dy * cos - height / 2;
      }
      return shape.copyWith(
        box: SlideBox(left, top, width, height),
        rotation: shape.rotation + turn,
      );
    };
  }

  /// The id a shape, picture, connector or group has on its slide.
  static int? idOf(XmlElement el) {
    for (final nv in el.childElements) {
      if (!_ln(nv).startsWith('nv')) continue;
      final properties = _kid(nv, 'cNvPr');
      if (properties != null) return int.tryParse(_at(properties, 'id') ?? '');
    }
    return null;
  }

  /// The placeholder a shape claims, and therefore the slot it inherits from.
  static ({String type, int index})? _placeholderOf(XmlElement shape) {
    final nv =
        _kid(shape, 'nvSpPr') ??
        _kid(shape, 'nvPicPr') ??
        _kid(shape, 'nvGraphicFramePr');
    final properties = nv == null ? null : _kid(nv, 'nvPr');
    final ph = properties == null ? null : _kid(properties, 'ph');
    if (ph == null) return null;
    return (
      type: _at(ph, 'type') ?? 'body',
      index: int.tryParse(_at(ph, 'idx') ?? '') ?? 0,
    );
  }

  /// The slot a placeholder inherits from, master first and layout over it.
  ///
  /// Merged rather than picked, because a layout routinely names a
  /// placeholder and says nothing else about it: its whole purpose is to
  /// restyle one thing and leave the rest to the master. Taking the first
  /// frame that mentions the placeholder loses the master's box, which is
  /// every title and every body on a deck built the ordinary way.
  _Slot? _slotFor(XmlElement shape, _Frame? layout, _Frame? master) {
    final ph = _placeholderOf(shape);
    if (ph == null) return null;
    final key = '${ph.type}:${ph.index}';
    final memo = '${layout?.path}|$key';
    final held = _slots[memo];
    if (held != null) return held;

    _Slot? on(_Frame? frame) => frame == null
        ? null
        : frame.byKey[key] ??
              frame.byType[ph.type] ??
              frame.byType[_equivalent(ph.type)];

    final above = on(master);
    final near = on(layout);
    if (above == null && near == null) return null;

    final merged = _Slot()
      ..box = near?.box ?? above?.box
      ..anchor = near?.anchor ?? above?.anchor
      ..rotation = near?.rotation ?? above?.rotation;
    for (final step in <_Slot?>[above, near]) {
      if (step == null) continue;
      for (final level in step.levels.entries) {
        (merged.levels[level.key] ??= _Level()).layer(level.value);
      }
    }
    _slots[memo] = merged;
    return merged;
  }

  /// The placeholder types the format treats as one thing under two names, so
  /// a slide's `ctrTitle` still finds the layout's `title`.
  static String _equivalent(String type) => switch (type) {
    'ctrTitle' => 'title',
    'title' => 'ctrTitle',
    'subTitle' => 'body',
    'body' => 'subTitle',
    _ => type,
  };

  SlideShape? _shape(
    XmlElement el,
    String part,
    Map<String, int> colours,
    _Slot? slot, [
    _Frame? master,
    int? id,
  ]) {
    final box = _boxOf(el) ?? slot?.box;
    // A shape with no box anywhere up the chain has nowhere to be drawn. It is
    // nearly always an empty layout placeholder, and inventing a rectangle for
    // it would put an empty panel on every slide of the deck.
    if (box == null) return null;

    final ph = _placeholderOf(el);
    final role = _roleOf(el, ph?.type);
    final properties = _kid(el, 'spPr');
    final blocks = <DocBlock>[];
    SlideChart? drawn;

    switch (_ln(el)) {
      case 'pic':
        final key = _pictureFill(el, part);
        if (key != null) {
          blocks.add(
            ImageBlock(
              key,
              width: box.width,
              height: box.height,
              alt: _describedBy(el),
            ),
          );
        }
      case 'graphicFrame':
        final table = _find(el, 'tbl');
        if (table != null) blocks.add(_table(table, colours));
        final chart = _chartPicture(el, part);
        if (chart != null) {
          blocks.add(ImageBlock(chart, width: box.width, height: box.height));
        } else {
          drawn = _chartOf(el, part, colours);
        }
    }

    final style = _kid(el, 'style');
    final body = _kid(el, 'txBody');
    if (body != null) {
      blocks.addAll(
        _textBody(body, colours, slot, role, master, _fontRefColour(style, colours)),
      );
    }

    final fillAsset = _ln(el) == 'pic' ? null : _pictureFill(el, part);
    final fill = (properties == null ? null : _solidFill(properties, colours)) ??
        (fillAsset == null && !_statesFill(properties)
            ? _styleColour(style, 'fillRef', colours)
            : null);
    final ownLine = properties == null ? null : _kid(properties, 'ln');
    final line = _lineOf(properties, colours) ??
        (ownLine == null ||
                (_kid(ownLine, 'noFill') == null &&
                    _kid(ownLine, 'solidFill') == null &&
                    _kid(ownLine, 'gradFill') == null)
            ? _styleColour(style, 'lnRef', colours)
            : null);
    // A shape holding nothing and filled with nothing is a spacer the file
    // keeps for its own reasons. Drawing it costs a layer and shows nothing.
    // An empty placeholder is kept, drawing nothing, so an editor can show
    // where its words would go.
    if (blocks.isEmpty && fill == null && fillAsset == null && line == null && ph == null && drawn == null) {
      return null;
    }

    final bodyProperties = body == null ? null : _kid(body, 'bodyPr');
    final transform = properties == null ? null : _kid(properties, 'xfrm');
    final geometry = properties == null ? null : _kid(properties, 'prstGeom');
    final outline = properties == null ? null : _kid(properties, 'ln');
    final dash = outline == null ? null : _kid(outline, 'prstDash');
    final effects = properties == null ? null : _kid(properties, 'effectLst');
    final blip = _find(el, 'blip');
    final alpha = blip == null ? null : _kid(blip, 'alphaModFix');
    final dashName = dash == null ? null : _at(dash, 'val');
    return SlideShape(
      box: box,
      blocks: blocks,
      role: role,
      fill: fill,
      fillAsset: fillAsset,
      line: line,
      lineWidth: _lineWidthOf(properties) > 0
          ? _lineWidthOf(properties)
          : line == null
          ? 0
          : _styleLineWidth(style),
      verticalAlign: bodyProperties == null
          ? slot?.anchor
          : _anchorOf(bodyProperties) ?? slot?.anchor,
      rotation: _rotationOf(el) ?? slot?.rotation ?? 0,
      id: id,
      geometry: (geometry == null ? null : _at(geometry, 'prst')) ?? (_ln(el) == 'cxnSp' ? 'line' : 'rect'),
      dash: dashName == null || dashName == 'solid' ? null : dashName,
      shadow: effects != null && _kid(effects, 'outerShdw') != null,
      opacity: alpha == null ? 1 : ((double.tryParse(_at(alpha, 'amt') ?? '') ?? 100000) / 100000).clamp(0.0, 1.0),
      flipH: transform != null && (_at(transform, 'flipH') == '1' || _at(transform, 'flipH') == 'true'),
      flipV: transform != null && (_at(transform, 'flipV') == '1' || _at(transform, 'flipV') == 'true'),
      placeholder: blocks.isEmpty ? ph?.type : null,
      own: idOf(el),
      textable: _ln(el) == 'sp',
      chart: drawn,
    );
  }

  /// True when a shape's properties say how it is filled, even to say it is
  /// not, so a style's fill does not fill it.
  static bool _statesFill(XmlElement? properties) {
    if (properties == null) return false;
    for (final child in properties.childElements) {
      switch (_ln(child)) {
        case 'noFill' || 'solidFill' || 'gradFill' || 'blipFill' || 'pattFill' || 'grpFill':
          return true;
      }
    }
    return false;
  }

  /// The colour a shape's style gives its fill or its outline, where the
  /// style names one of the theme's styles at all.
  int? _styleColour(XmlElement? style, String ref, Map<String, int> colours) {
    final el = style == null ? null : _kid(style, ref);
    if (el == null) return null;
    if ((int.tryParse(_at(el, 'idx') ?? '') ?? 0) <= 0) return null;
    return _colourIn(el, colours);
  }

  /// The width of the theme line style a shape's style names, in points, as
  /// Office's own themes set them.
  static double _styleLineWidth(XmlElement? style) {
    final el = style == null ? null : _kid(style, 'lnRef');
    final idx = int.tryParse((el == null ? null : _at(el, 'idx')) ?? '') ?? 0;
    return switch (idx) {
      <= 0 => 0,
      1 => 0.5,
      2 => 1,
      _ => 1.5,
    };
  }

  int? _fontRefColour(XmlElement? style, Map<String, int> colours) {
    final el = style == null ? null : _kid(style, 'fontRef');
    return el == null ? null : _colourIn(el, colours);
  }

  static SlideRole _roleOf(XmlElement el, String? placeholder) {
    if (placeholder == 'title' || placeholder == 'ctrTitle') {
      return SlideRole.title;
    }
    switch (_ln(el)) {
      case 'pic':
        return SlideRole.picture;
      case 'graphicFrame':
        return _find(el, 'tbl') != null ? SlideRole.table : SlideRole.chart;
    }
    return placeholder == null ? SlideRole.other : SlideRole.body;
  }

  /// The box a shape states for itself, in points.
  static SlideBox? _boxOf(XmlElement el) {
    final properties = _kid(el, 'spPr') ?? _kid(el, 'grpSpPr');
    final own = (properties == null ? null : _kid(properties, 'xfrm')) ??
        _kid(el, 'xfrm');
    if (own == null) return null;
    final off = _kid(own, 'off');
    final ext = _kid(own, 'ext');
    if (off == null || ext == null) return null;
    final x = double.tryParse(_at(off, 'x') ?? '');
    final y = double.tryParse(_at(off, 'y') ?? '');
    final cx = double.tryParse(_at(ext, 'cx') ?? '');
    final cy = double.tryParse(_at(ext, 'cy') ?? '');
    if (x == null || y == null || cx == null || cy == null) return null;
    return SlideBox(
      x / kEmuPerPoint,
      y / kEmuPerPoint,
      cx / kEmuPerPoint,
      cy / kEmuPerPoint,
    );
  }

  /// Clockwise degrees, from the sixtieths of a degree the format states
  /// rotation in.
  static double? _rotationOf(XmlElement el) {
    final properties = _kid(el, 'spPr');
    final transform = properties == null ? null : _kid(properties, 'xfrm');
    final parsed = double.tryParse(
      (transform == null ? null : _at(transform, 'rot')) ?? '',
    );
    return parsed == null ? null : parsed / 60000;
  }

  int? _lineOf(XmlElement? properties, Map<String, int> colours) {
    if (properties == null) return null;
    final line = _kid(properties, 'ln');
    if (line == null || _kid(line, 'noFill') != null) return null;
    return _solidFill(line, colours);
  }

  static double _lineWidthOf(XmlElement? properties) {
    if (properties == null) return 0;
    final line = _kid(properties, 'ln');
    if (line == null) return 0;
    final width = double.tryParse(_at(line, 'w') ?? '');
    return width == null ? 0 : width / kEmuPerPoint;
  }

  /// The asset key of the picture a part is filled with, or null.
  String? _pictureFill(XmlElement el, String part) {
    final fill = _find(el, 'blipFill');
    final blip = fill == null ? null : _kid(fill, 'blip');
    if (blip == null) return null;
    final id = _at(blip, 'embed') ?? _at(blip, 'link');
    if (id == null) return null;
    final target = _relsOf(part)[id];
    if (target == null || !_assets.containsKey(target)) return null;
    return target;
  }

  /// A chart's or a diagram's cached picture, where the file keeps one.
  ///
  /// quire does not draw charts, and a chart simply missing from a slide is a
  /// hole in the middle of somebody's argument. Most files carry a rendering
  /// of it, and showing that is honest: it is what the deck itself last looked
  /// like.
  String? _chartPicture(XmlElement el, String part) {
    final data = _find(el, 'graphicData');
    if (data == null) return null;
    final uri = _at(data, 'uri') ?? '';
    if (!uri.contains('chart') && !uri.contains('diagram')) return null;
    final rels = _relsOf(part);
    for (final child in data.descendantElements) {
      for (final a in child.attributes) {
        if (!a.name.local.startsWith('id') && a.name.local != 'embed') continue;
        final target = rels[a.value];
        if (target != null && _assets.containsKey(target)) return target;
      }
    }
    return null;
  }

  /// A chart read from its part: its kind, its categories and each series'
  /// cached values and colour, for a chart the file keeps no picture of.
  SlideChart? _chartOf(XmlElement el, String part, Map<String, int> colours) {
    final data = _find(el, 'graphicData');
    if (data == null || !(_at(data, 'uri') ?? '').contains('chart')) return null;
    final ref = _find(data, 'chart');
    final target = ref == null ? null : _relsOf(part)[_at(ref, 'id') ?? ''];
    final root = target == null ? null : _root(target);
    final chart = root == null ? null : _find(root, 'chart');
    final plot = chart == null ? null : _kid(chart, 'plotArea');
    if (chart == null || plot == null) return null;
    XmlElement? kindOf;
    for (final c in plot.childElements) {
      if (_ln(c).endsWith('Chart')) {
        kindOf = c;
        break;
      }
    }
    if (kindOf == null) return null;
    final kind = switch (_ln(kindOf)) {
      'barChart' || 'bar3DChart' => _at(_kid(kindOf, 'barDir') ?? kindOf, 'val') == 'bar' ? 'bar' : 'col',
      'lineChart' || 'line3DChart' || 'stockChart' || 'radarChart' || 'scatterChart' => 'line',
      'areaChart' || 'area3DChart' => 'area',
      'pieChart' || 'pie3DChart' || 'ofPieChart' => 'pie',
      'doughnutChart' => 'doughnut',
      _ => 'col',
    };
    final grouping = _at(_kid(kindOf, 'grouping') ?? kindOf, 'val') ?? '';
    List<String> points(XmlElement? holder) {
      if (holder == null) return const <String>[];
      final out = <int, String>{};
      var count = 0;
      for (final e in holder.descendantElements) {
        if (_ln(e) == 'ptCount') count = int.tryParse(_at(e, 'val') ?? '') ?? count;
        if (_ln(e) != 'pt') continue;
        final idx = int.tryParse(_at(e, 'idx') ?? '') ?? out.length;
        out[idx] = _kid(e, 'v')?.innerText ?? '';
        if (idx + 1 > count) count = idx + 1;
      }
      return <String>[for (var i = 0; i < count; i++) out[i] ?? ''];
    }

    final accents = <int>[
      for (var i = 1; i <= 6; i++) colours['accent$i'] ?? const <int>[0xFF4472C4, 0xFFED7D31, 0xFFA5A5A5, 0xFFFFC000, 0xFF5B9BD5, 0xFF70AD47][i - 1],
    ];
    final series = <SlideSeries>[];
    var categories = const <String>[];
    for (final ser in _kids(kindOf, 'ser')) {
      final index = series.length;
      final name = points(_kid(ser, 'tx')).firstOrNull ?? 'Series ${index + 1}';
      final cats = points(_kid(ser, 'cat') ?? _kid(ser, 'xVal'));
      if (cats.length > categories.length) categories = cats;
      final values = <double?>[for (final v in points(_kid(ser, 'val') ?? _kid(ser, 'yVal'))) double.tryParse(v)];
      final spPr = _kid(ser, 'spPr');
      final own = spPr == null ? null : (_solidFill(spPr, colours) ?? _lineOf(spPr, colours));
      final slices = <int>[
        for (var i = 0; i < values.length; i++)
          () {
            for (final dPt in _kids(ser, 'dPt')) {
              if (int.tryParse(_at(_kid(dPt, 'idx') ?? dPt, 'val') ?? '') != i) continue;
              final fill = _kid(dPt, 'spPr');
              final colour = fill == null ? null : _solidFill(fill, colours);
              if (colour != null) return colour;
            }
            return accents[i % accents.length];
          }(),
      ];
      series.add(SlideSeries(name, values, own ?? accents[index % accents.length], colours: slices));
    }
    if (series.isEmpty) return null;
    final title = _kid(chart, 'title');
    final deleted = _at(_kid(chart, 'autoTitleDeleted') ?? chart, 'val');
    String? titleText;
    if (title != null) {
      titleText = title.descendantElements.where((e) => _ln(e) == 't').map((e) => e.innerText).join();
      if (titleText.isEmpty) titleText = points(title).firstOrNull;
    } else if (deleted != '1' && series.length == 1 && (kind == 'pie' || kind == 'doughnut')) {
      titleText = series.single.name;
    }
    return SlideChart(
      kind: kind,
      categories: categories,
      series: series,
      title: titleText == null || titleText.isEmpty ? null : titleText,
      stacked: grouping == 'stacked' || grouping == 'percentStacked',
      legend: _kid(chart, 'legend') != null,
    );
  }

  static String? _describedBy(XmlElement el) {
    final nv = _kid(el, 'nvPicPr');
    final properties = nv == null ? null : _kid(nv, 'cNvPr');
    if (properties == null) return null;
    final description = _at(properties, 'descr');
    if (description != null && description.trim().isNotEmpty) {
      return description.trim();
    }
    final name = _at(properties, 'name');
    return name == null || name.trim().isEmpty ? null : name.trim();
  }

  // Text.

  /// The layout and master a slide or layout part stands on.
  (_Frame?, _Frame?, Map<String, int>) _framesFor(String path) {
    var layoutPath = '';
    var masterPath = '';
    for (final entry in _relsOf(path).entries) {
      if (entry.value.contains('/slideLayouts/')) layoutPath = entry.value;
      if (entry.value.contains('/slideMasters/')) masterPath = entry.value;
    }
    final layout = layoutPath.isEmpty ? null : _frame(layoutPath);
    final parent = layout?.parent ?? (masterPath.isEmpty ? null : masterPath);
    final master = parent == null ? null : _frame(parent);
    final colours = layout?.colours ?? master?.colours ?? const <String, int>{};
    return (layout, master, colours);
  }

  /// How the words of the shape [id] on the slide at [path] are set: each
  /// outline level as the placeholder, the layout, the master and the
  /// shape's own list style leave it, and each paragraph and run with its
  /// own properties laid over that. Null when the slide has no such shape.
  SlideTextLooks? textLooks(String path, int id, {(int, int)? cell}) {
    _open();
    final root = _root(path);
    if (root == null) return null;
    final (layout, master, colours) = _framesFor(path);
    XmlElement? found;
    for (final el in root.descendantElements) {
      final local = _ln(el);
      if ((local == 'sp' || local == 'graphicFrame') && idOf(el) == id) {
        found = el;
        break;
      }
    }
    if (found == null) return null;
    var body = _kid(found, 'txBody');
    if (cell != null) {
      final table = _find(found, 'tbl');
      final rows = table == null ? const <XmlElement>[] : _kids(table, 'tr').toList();
      final cells = cell.$1 < rows.length ? _kids(rows[cell.$1], 'tc').toList() : const <XmlElement>[];
      if (cell.$2 >= cells.length) return null;
      body = _kid(cells[cell.$2], 'txBody');
    }
    final ph = _placeholderOf(found);
    final slot = _slotFor(found, layout, master);
    final role = _roleOf(found, ph?.type);
    final fontColour = _fontRefColour(_kid(found, 'style'), colours);
    SlideTextLook look(_Level level, int depth) => SlideTextLook(
      size: level.size ?? kSlideTextSize,
      bold: level.bold ?? false,
      italic: level.italic ?? false,
      underline: level.underline ?? false,
      colour: level.colour,
      align: level.align ?? DocAlign.start,
      bulleted: level.plain != true && (level.bullet != null || level.ordered == true),
      ordered: level.ordered == true,
      level: depth,
      bullet: level.bullet,
    );
    final bases = _bases(body, colours, slot, role, master, fontColour);
    final levels = <SlideTextLook>[
      for (var i = 0; i < 9; i++) look(bases(i), i),
    ];
    final paragraphs = <(SlideTextLook, List<SlideTextLook>)>[];
    if (body != null) {
      for (final p in _kids(body, 'p')) {
        final pPr = _kid(p, 'pPr');
        final depth = int.tryParse(pPr == null ? '' : _at(pPr, 'lvl') ?? '') ?? 0;
        final style = bases(depth);
        if (pPr != null) style.layer(_paragraphStyle(pPr, colours));
        paragraphs.add((
          look(style, depth),
          <SlideTextLook>[
            for (final child in p.childElements)
              if (_ln(child) == 'r' || _ln(child) == 'fld')
                () {
                  final run = _kid(child, 'rPr');
                  final over = style.copy();
                  if (run != null) over.layer(_runStyle(run, colours));
                  return look(over, depth);
                }(),
          ],
        ));
      }
    }
    return SlideTextLooks(levels, paragraphs);
  }

  /// A level's defaults, weakest first: the master's own list style, then
  /// the layout placeholder's, then the style's font colour, then the
  /// shape's own list style.
  _Level Function(int) _bases(
    XmlElement? body,
    Map<String, int> colours,
    _Slot? slot,
    SlideRole role,
    _Frame? master,
    int? fontColour,
  ) {
    final own = body == null ? null : _kid(body, 'lstStyle');
    final ownLevels = own == null ? const <int, _Level>{} : _listStyle(own, colours);
    final fromMaster = master?.textStyles[switch (role) {
          SlideRole.title => 'title',
          SlideRole.body => 'body',
          _ => 'other',
        }] ??
        const <int, _Level>{};
    return (level) {
      final style = _Level();
      for (final step in <_Level?>[
        fromMaster[level],
        slot?.levels[level],
        if (fontColour != null) _Level()..colour = fontColour,
        ownLevels[level],
      ]) {
        if (step != null) style.layer(step);
      }
      return style;
    };
  }

  /// The things on the slide at [path] that can be picked up, in the order
  /// they are drawn, each at the box it is drawn in.
  List<SlideObject> objectsAt(String path) {
    _open();
    final root = _root(path);
    final common = root == null ? null : _kid(root, 'cSld');
    final tree = common == null ? null : _kid(common, 'spTree');
    if (tree == null) return const <SlideObject>[];
    final (layout, master, _) = _framesFor(path);
    final out = <SlideObject>[];
    for (final el in tree.childElements) {
      final kind = _ln(el);
      if (!const <String>{'sp', 'pic', 'graphicFrame', 'grpSp', 'cxnSp'}.contains(kind)) {
        continue;
      }
      final id = idOf(el);
      if (id == null) continue;
      final slot = _slotFor(el, layout, master);
      final box = _boxOf(el) ?? slot?.box;
      if (box == null) continue;
      final properties = _kid(el, 'spPr') ?? _kid(el, 'grpSpPr');
      final transform = properties == null ? null : _kid(properties, 'xfrm');
      bool flag(String name) =>
          transform != null && (_at(transform, name) == '1' || _at(transform, name) == 'true');
      final turn = double.tryParse((transform == null ? null : _at(transform, 'rot')) ?? '');
      final nv = el.childElements.where((c) => _ln(c).startsWith('nv')).firstOrNull;
      final named = nv == null ? null : _kid(nv, 'cNvPr');
      out.add(
        SlideObject(
          id: id,
          kind: kind,
          box: box,
          rotation: turn == null ? slot?.rotation ?? 0 : turn / 60000,
          flipH: flag('flipH'),
          flipV: flag('flipV'),
          placeholder: _placeholderOf(el)?.type,
          name: named == null ? '' : _at(named, 'name') ?? '',
          hasText: kind == 'sp',
        ),
      );
    }
    return out;
  }

  /// Every layout of every master, in the order the masters list them.
  List<SlideLayoutInfo> layouts() {
    final root = _open();
    final out = <SlideLayoutInfo>[];
    final masters = _kid(root, 'sldMasterIdLst');
    final deckRels = _relsOf('ppt/presentation.xml');
    for (final id in masters == null ? const <XmlElement>[] : _kids(masters, 'sldMasterId')) {
      final master = deckRels[_relId(id) ?? ''];
      if (master == null) continue;
      final masterRoot = _root(master);
      final list = masterRoot == null ? null : _kid(masterRoot, 'sldLayoutIdLst');
      final rels = _relsOf(master);
      for (final entry in list == null ? const <XmlElement>[] : _kids(list, 'sldLayoutId')) {
        final path = rels[_relId(entry) ?? ''];
        if (path == null) continue;
        final layout = _root(path);
        if (layout == null) continue;
        final common = _kid(layout, 'cSld');
        out.add(
          SlideLayoutInfo(
            path,
            (common == null ? null : _at(common, 'name')) ?? _nameOf(path),
            master,
            _at(layout, 'type'),
          ),
        );
      }
    }
    return out;
  }

  /// A layout drawn as a slide made on it would be before anything is typed:
  /// the master's and the layout's own furniture, and each placeholder as a
  /// dashed box with its name in it.
  SlideBlock layoutAt(String path) {
    _open();
    final layout = _frame(path);
    final parent = layout?.parent;
    final master = parent == null ? null : _frame(parent);
    final root = _root(path);
    final common = root == null ? null : _kid(root, 'cSld');
    final tree = common == null ? null : _kid(common, 'spTree');
    final hints = <SlideShape>[];
    if (tree != null && layout != null) {
      for (final el in tree.childElements) {
        final ph = _placeholderOf(el);
        if (ph == null || const <String>{'dt', 'ftr', 'sldNum'}.contains(ph.type)) continue;
        final slot = _slotFor(el, layout, master);
        final box = _boxOf(el) ?? slot?.box;
        if (box == null) continue;
        final role = _roleOf(el, ph.type);
        final base = _bases(_kid(el, 'txBody'), layout.colours, slot, role, master, null)(0);
        hints.add(
          SlideShape(
            box: box,
            blocks: <DocBlock>[
              ParagraphBlock(<DocSpan>[
                DocSpan(
                  placeholderHint(ph.type),
                  fontSize: base.size ?? kSlideTextSize,
                  bold: base.bold ?? false,
                  color: 0x80000000 | ((base.colour ?? 0xFF000000) & 0xFFFFFF),
                ),
              ], align: base.align ?? DocAlign.start),
            ],
            role: role,
            line: 0x66808080,
            lineWidth: 1,
            dash: 'dash',
            verticalAlign: slot?.anchor,
            placeholder: ph.type,
          ),
        );
      }
    }
    return SlideBlock(
      width: _slideWidth,
      height: _slideHeight,
      shapes: <SlideShape>[...?master?.furniture, ...?layout?.furniture, ...hints],
      background: layout?.background ?? master?.background,
      backgroundAsset: layout?.backgroundAsset ?? master?.backgroundAsset,
      layoutName: _nameOf(path),
    );
  }

  /// What an empty placeholder of [type] asks for.
  static String placeholderHint(String type) => switch (type) {
    'title' || 'ctrTitle' => 'Title',
    'subTitle' => 'Subtitle',
    'pic' => 'Picture',
    'tbl' => 'Table',
    'chart' => 'Chart',
    _ => 'Text',
  };

  List<DocBlock> _textBody(
    XmlElement body,
    Map<String, int> colours,
    _Slot? slot,
    SlideRole role, [
    _Frame? master,
    int? fontColour,
  ]) {
    final own = _kid(body, 'lstStyle');
    final ownLevels = own == null
        ? const <int, _Level>{}
        : _listStyle(own, colours);
    final fromMaster =
        master?.textStyles[switch (role) {
          SlideRole.title => 'title',
          SlideRole.body => 'body',
          _ => 'other',
        }] ??
        const <int, _Level>{};

    final out = <DocBlock>[];
    final counters = <int, int>{};
    for (final p in _kids(body, 'p')) {
      final pPr = _kid(p, 'pPr');
      final level = int.tryParse(pPr == null ? '' : _at(pPr, 'lvl') ?? '') ?? 0;

      // The chain, weakest first: the master's own list style, then the layout
      // placeholder's, then the shape's, then the paragraph's.
      final style = _Level();
      for (final step in <_Level?>[
        fromMaster[level],
        slot?.levels[level],
        if (fontColour != null) _Level()..colour = fontColour,
        ownLevels[level],
      ]) {
        if (step != null) style.layer(step);
      }
      if (pPr != null) style.layer(_paragraphStyle(pPr, colours));

      final spans = _spans(p, colours, style);
      if (spans.isEmpty) {
        // An empty paragraph between two full ones is a deliberate gap, and a
        // deck that closes them up is a deck spaced by somebody other than its
        // author.
        if (out.isNotEmpty) out.add(const ParagraphBlock(<DocSpan>[]));
        continue;
      }

      if (role == SlideRole.title && level == 0) {
        out.add(HeadingBlock(1, spans));
        continue;
      }
      final align = style.align ?? DocAlign.start;
      final bulleted =
          style.plain != true &&
          (style.bullet != null || style.ordered == true);
      if (!bulleted) {
        out.add(ParagraphBlock(spans, align: align, indent: level));
        continue;
      }
      final ordered = style.ordered == true;
      if (ordered) {
        counters[level] = (counters[level] ?? 0) + 1;
        for (final deeper in counters.keys.toList()) {
          if (deeper > level) counters.remove(deeper);
        }
      }
      out.add(
        ListItemBlock(
          spans,
          level: level,
          ordered: ordered,
          marker: ordered ? '${counters[level]}.' : style.bullet,
        ),
      );
    }
    // A run of empty paragraphs at the end is the space left under the last
    // line, not part of what was written.
    while (out.isNotEmpty) {
      final last = out.last;
      if (last is ParagraphBlock && last.spans.isEmpty) {
        out.removeLast();
        continue;
      }
      break;
    }
    return out;
  }

  List<DocSpan> _spans(XmlElement p, Map<String, int> colours, _Level style) {
    final out = <DocSpan>[];
    for (final child in p.childElements) {
      switch (_ln(child)) {
        case 'r':
        case 'fld':
          // A field is a slide number or a date the file has already
          // rendered, and that rendering is the only version of it quire can
          // honestly show.
          final text = _kid(child, 't')?.innerText ?? '';
          if (text.isEmpty) continue;
          final run = _kid(child, 'rPr');
          final over = style.copy();
          if (run != null) over.layer(_runStyle(run, colours));
          out.add(
            DocSpan(
              text,
              bold: over.bold ?? false,
              italic: over.italic ?? false,
              underline: over.underline ?? false,
              color: over.colour,
              fontSize: over.size,
              href: run == null ? null : _linkOf(run),
            ),
          );
        case 'br':
          if (out.isNotEmpty) out.add(const DocSpan('\n'));
      }
    }
    return out;
  }

  /// A run's hyperlink target, where the relationship points outside the file.
  ///
  /// Only the address is kept and nothing is ever fetched: quire does not use
  /// the network, and a link is shown so a reader can see where the deck was
  /// pointing them.
  String? _linkOf(XmlElement rPr) {
    final click = _kid(rPr, 'hlinkClick');
    final id = click == null ? null : _at(click, 'id');
    if (id == null || id.isEmpty) return null;
    for (final part in _rels.values) {
      final target = part[id];
      if (target != null) return target;
    }
    return null;
  }

  TableBlock _table(XmlElement tbl, Map<String, int> colours) {
    final grid = _kid(tbl, 'tblGrid');
    final columns = <DocColumn>[
      if (grid != null)
        for (final col in _kids(grid, 'gridCol'))
          DocColumn(
            width: (double.tryParse(_at(col, 'w') ?? '') ?? 0) / kEmuPerPoint,
          ),
    ];
    final properties = _kid(tbl, 'tblPr');
    final banded = _at(properties ?? tbl, 'firstRow') == '1';

    final rows = <DocRow>[];
    var first = true;
    for (final tr in _kids(tbl, 'tr')) {
      final cells = <DocCell>[];
      for (final tc in _kids(tr, 'tc')) {
        final body = _kid(tc, 'txBody');
        final cellProperties = _kid(tc, 'tcPr');
        cells.add(
          DocCell(
            body == null
                ? const <DocBlock>[]
                : _textBody(body, colours, null, SlideRole.other),
            colSpan: int.tryParse(_at(tc, 'gridSpan') ?? '') ?? 1,
            rowSpan: int.tryParse(_at(tc, 'rowSpan') ?? '') ?? 1,
            merged: _at(tc, 'hMerge') == '1' || _at(tc, 'vMerge') == '1',
            background: cellProperties == null
                ? null
                : _solidFill(cellProperties, colours),
            verticalAlign: cellProperties == null
                ? null
                : _anchorOf(cellProperties),
            wrap: true,
          ),
        );
      }
      final height = double.tryParse(_at(tr, 'h') ?? '');
      rows.add(
        DocRow(
          cells,
          header: first && banded,
          height: height == null ? null : height / kEmuPerPoint,
        ),
      );
      first = false;
    }
    return TableBlock(rows, columns: columns);
  }

  /// What the speaker was going to say, as blocks.
  ///
  /// The notes live in their own part with their own placeholder, and the
  /// slide's own thumbnail sits in there beside them, which is why only the
  /// body placeholder is read.
  List<DocBlock> _notes(String path, Map<String, int> colours) {
    final root = _root(path);
    final tree = root == null ? null : _find(root, 'spTree');
    if (tree == null) return const <DocBlock>[];
    final out = <DocBlock>[];
    for (final shape in _kids(tree, 'sp')) {
      final ph = _placeholderOf(shape);
      if (ph == null || ph.type != 'body') continue;
      final body = _kid(shape, 'txBody');
      if (body == null) continue;
      out.addAll(_textBody(body, colours, null, SlideRole.body));
    }
    return out;
  }
}
