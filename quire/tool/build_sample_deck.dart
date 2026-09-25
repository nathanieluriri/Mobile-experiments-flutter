/// Writes `assets/documents/press-day-briefing.pptx`, the deck quire ships
/// with and tests against.
///
/// It is generated rather than saved out of PowerPoint for two reasons. A real
/// deck belongs to whoever made it, and quire's samples are all written for
/// quire. And a deck written here can be made to carry exactly the things the
/// parser has to survive: a title that states no box and inherits one from its
/// layout, a scheme colour that is only a tint of a theme colour, a table, a
/// picture, speaker notes, and a slide whose ground is set by the master.
///
/// Run it from the app directory:
///
///     dart run tool/build_sample_deck.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// The stage, in EMU: sixteen by nine at 13.333 by 7.5 inches, which is what
/// every deck written this decade uses.
const int kStageWidth = 12192000;
const int kStageHeight = 6858000;

/// EMU per inch, for saying where things go in units a person can check.
const int kEmuPerInch = 914400;

int inches(double value) => (value * kEmuPerInch).round();

void main() {
  final files = <String, List<int>>{};

  void put(String path, String xml) =>
      files[path] = utf8.encode('$_xmlHead\n$xml');

  put('[Content_Types].xml', _contentTypes());
  put('_rels/.rels', _rootRels());
  put('docProps/core.xml', _core());
  put('docProps/app.xml', _app());
  put('ppt/presentation.xml', _presentation());
  put('ppt/_rels/presentation.xml.rels', _presentationRels());
  put('ppt/theme/theme1.xml', _theme());
  put('ppt/slideMasters/slideMaster1.xml', _master());
  put('ppt/slideMasters/_rels/slideMaster1.xml.rels', _masterRels());
  for (var i = 1; i <= _layouts.length; i++) {
    put('ppt/slideLayouts/slideLayout$i.xml', _layouts[i - 1]);
    put('ppt/slideLayouts/_rels/slideLayout$i.xml.rels', _layoutRels());
  }
  for (var i = 1; i <= _slides.length; i++) {
    put('ppt/slides/slide$i.xml', _slides[i - 1].xml);
    put('ppt/slides/_rels/slide$i.xml.rels', _slideRels(_slides[i - 1], i));
  }
  put('ppt/notesSlides/notesSlide1.xml', _notes());
  put('ppt/notesSlides/_rels/notesSlide1.xml.rels', _notesRels());
  files['ppt/media/image1.png'] = _proofSheetPng();

  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(
      ArchiveFile(entry.key, entry.value.length, entry.value),
    );
  }
  // Stored rather than deflated for the first entry is a convention quire's
  // own reader does not need, so the whole package is simply written out.
  final zipped = ZipEncoder().encode(archive);
  final out = File('assets/documents/press-day-briefing.pptx');
  out.writeAsBytesSync(zipped);
  stdout.writeln('wrote ${out.path}, ${zipped.length} bytes');
}

const String _xmlHead =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

const String _nsP =
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';

String _contentTypes() {
  final overrides = StringBuffer();
  for (var i = 1; i <= _layouts.length; i++) {
    overrides.write(
      '<Override PartName="/ppt/slideLayouts/slideLayout$i.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.'
      'presentationml.slideLayout+xml"/>',
    );
  }
  for (var i = 1; i <= _slides.length; i++) {
    overrides.write(
      '<Override PartName="/ppt/slides/slide$i.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.'
      'presentationml.slide+xml"/>',
    );
  }
  return '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
      'content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-'
      'package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Default Extension="png" ContentType="image/png"/>'
      '<Override PartName="/ppt/presentation.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.'
      'presentationml.presentation.main+xml"/>'
      '<Override PartName="/ppt/slideMasters/slideMaster1.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.'
      'presentationml.slideMaster+xml"/>'
      '<Override PartName="/ppt/theme/theme1.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
      '<Override PartName="/ppt/notesSlides/notesSlide1.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.'
      'presentationml.notesSlide+xml"/>'
      '$overrides'
      '<Override PartName="/docProps/core.xml" ContentType="application/vnd.'
      'openxmlformats-package.core-properties+xml"/>'
      '<Override PartName="/docProps/app.xml" ContentType="application/vnd.'
      'openxmlformats-officedocument.extended-properties+xml"/>'
      '</Types>';
}

String _rootRels() =>
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
    'relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/officeDocument" '
    'Target="ppt/presentation.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/'
    '2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
    '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/extended-properties" '
    'Target="docProps/app.xml"/>'
    '</Relationships>';

String _core() =>
    '<cp:coreProperties '
    'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/'
    'core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" '
    'xmlns:dcterms="http://purl.org/dc/terms/" '
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
    '<dc:title>Press Day Briefing</dc:title>'
    '<dc:creator>the bindery</dc:creator>'
    '<cp:lastModifiedBy>the bindery</cp:lastModifiedBy>'
    '<dcterms:created xsi:type="dcterms:W3CDTF">2026-01-06T08:00:00Z'
    '</dcterms:created>'
    '</cp:coreProperties>';

String _app() =>
    '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/'
    'extended-properties">'
    '<Application>quire</Application>'
    '<Slides>${_slides.length}</Slides>'
    '</Properties>';

String _presentation() {
  final ids = StringBuffer();
  for (var i = 1; i <= _slides.length; i++) {
    ids.write('<p:sldId id="${255 + i}" r:id="rId${i + 1}"/>');
  }
  return '<p:presentation $_nsP saveSubsetFonts="1">'
      '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/>'
      '</p:sldMasterIdLst>'
      '<p:sldIdLst>$ids</p:sldIdLst>'
      '<p:sldSz cx="$kStageWidth" cy="$kStageHeight"/>'
      '<p:notesSz cx="$kStageHeight" cy="$kStageWidth"/>'
      '</p:presentation>';
}

String _presentationRels() {
  final out = StringBuffer(
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
    'relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/slideMaster" '
    'Target="slideMasters/slideMaster1.xml"/>',
  );
  for (var i = 1; i <= _slides.length; i++) {
    out.write(
      '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/'
      'officeDocument/2006/relationships/slide" Target="slides/slide$i.xml"/>',
    );
  }
  out.write(
    '<Relationship Id="rId${_slides.length + 2}" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
    'relationships/theme" Target="theme/theme1.xml"/>',
  );
  return (out..write('</Relationships>')).toString();
}

/// The press palette: warm paper, two inks and a gilt.
String _theme() =>
    '<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'name="Press">'
    '<a:themeElements>'
    '<a:clrScheme name="Press">'
    '<a:dk1><a:srgbClr val="1A1A1A"/></a:dk1>'
    '<a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>'
    '<a:dk2><a:srgbClr val="3C3A36"/></a:dk2>'
    '<a:lt2><a:srgbClr val="F4EFE6"/></a:lt2>'
    '<a:accent1><a:srgbClr val="8A4B2A"/></a:accent1>'
    '<a:accent2><a:srgbClr val="2E5E4E"/></a:accent2>'
    '<a:accent3><a:srgbClr val="B08D57"/></a:accent3>'
    '<a:accent4><a:srgbClr val="6B6257"/></a:accent4>'
    '<a:accent5><a:srgbClr val="9C3B2E"/></a:accent5>'
    '<a:accent6><a:srgbClr val="47576B"/></a:accent6>'
    '<a:hlink><a:srgbClr val="2E5E4E"/></a:hlink>'
    '<a:folHlink><a:srgbClr val="6B6257"/></a:folHlink>'
    '</a:clrScheme>'
    '<a:fontScheme name="Press">'
    '<a:majorFont><a:latin typeface="Georgia"/><a:ea typeface=""/>'
    '<a:cs typeface=""/></a:majorFont>'
    '<a:minorFont><a:latin typeface="Georgia"/><a:ea typeface=""/>'
    '<a:cs typeface=""/></a:minorFont>'
    '</a:fontScheme>'
    '<a:fmtScheme name="Press">'
    '<a:fillStyleLst>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '</a:fillStyleLst>'
    '<a:lnStyleLst>'
    '<a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '</a:ln>'
    '<a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '</a:ln>'
    '<a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '</a:ln>'
    '</a:lnStyleLst>'
    '<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle>'
    '<a:effectStyle><a:effectLst/></a:effectStyle>'
    '<a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>'
    '<a:bgFillStyleLst>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '</a:bgFillStyleLst>'
    '</a:fmtScheme>'
    '</a:themeElements>'
    '</a:theme>';

/// The master: the deck's paper ground, its running foot, and the text styles
/// every slide inherits.
String _master() =>
    '<p:sldMaster $_nsP>'
    '<p:cSld>'
    '<p:bg><p:bgPr><a:solidFill><a:schemeClr val="bg2"/></a:solidFill>'
    '<a:effectLst/></p:bgPr></p:bg>'
    '<p:spTree>'
    '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/>'
    '</p:nvGrpSpPr>'
    '<p:grpSpPr/>'
    // The rule under every title, which no slide owns and every slide shows.
    '${_rect(
      id: 9,
      name: 'Head rule',
      x: inches(0.9),
      y: inches(1.55),
      cx: inches(11.5),
      cy: 22225,
      fill: '<a:solidFill><a:schemeClr val="accent3"/></a:solidFill>',
    )}'
    '${_textBox(
      id: 10,
      name: 'Running foot',
      x: inches(0.9),
      y: inches(6.75),
      cx: inches(6),
      cy: inches(0.4),
      paragraphs: '<a:p><a:pPr><a:buNone/></a:pPr>'
          '<a:r><a:rPr lang="en-GB" sz="1000">'
          '<a:solidFill><a:schemeClr val="tx2"><a:alpha val="70000"/>'
          '</a:schemeClr></a:solidFill></a:rPr>'
          '<a:t>the bindery, michaelmas run</a:t></a:r></a:p>',
    )}'
    '<p:sp>'
    '<p:nvSpPr><p:cNvPr id="2" name="Title Placeholder 1"/>'
    '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
    '<p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>'
    '<p:spPr><a:xfrm><a:off x="${inches(0.9)}" y="${inches(0.5)}"/>'
    '<a:ext cx="${inches(11.5)}" cy="${inches(1)}"/></a:xfrm></p:spPr>'
    '<p:txBody><a:bodyPr anchor="b"/><a:lstStyle/><a:p/></p:txBody>'
    '</p:sp>'
    '<p:sp>'
    '<p:nvSpPr><p:cNvPr id="3" name="Body Placeholder 2"/>'
    '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
    '<p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>'
    '<p:spPr><a:xfrm><a:off x="${inches(0.9)}" y="${inches(1.9)}"/>'
    '<a:ext cx="${inches(11.5)}" cy="${inches(4.6)}"/></a:xfrm></p:spPr>'
    '<p:txBody><a:bodyPr anchor="t"/><a:lstStyle/><a:p/></p:txBody>'
    '</p:sp>'
    '</p:spTree>'
    '</p:cSld>'
    '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" '
    'accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" '
    'accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
    '<p:sldLayoutIdLst>'
    '<p:sldLayoutId id="2147483649" r:id="rId1"/>'
    '<p:sldLayoutId id="2147483650" r:id="rId2"/>'
    '<p:sldLayoutId id="2147483651" r:id="rId3"/>'
    '</p:sldLayoutIdLst>'
    '<p:txStyles>'
    '<p:titleStyle>'
    '<a:lvl1pPr algn="l"><a:buNone/>'
    '<a:defRPr sz="4000" b="1"><a:solidFill><a:schemeClr val="tx1"/>'
    '</a:solidFill></a:defRPr></a:lvl1pPr>'
    '</p:titleStyle>'
    '<p:bodyStyle>'
    '<a:lvl1pPr marL="285750" indent="-285750">'
    '<a:buChar char="•"/>'
    '<a:defRPr sz="2000"><a:solidFill><a:schemeClr val="tx2"/></a:solidFill>'
    '</a:defRPr></a:lvl1pPr>'
    '<a:lvl2pPr marL="628650" indent="-285750">'
    '<a:buChar char="–"/>'
    '<a:defRPr sz="1700"><a:solidFill><a:schemeClr val="tx2"/>'
    '</a:solidFill></a:defRPr></a:lvl2pPr>'
    '</p:bodyStyle>'
    '<p:otherStyle>'
    '<a:lvl1pPr><a:buNone/><a:defRPr sz="1600"/></a:lvl1pPr>'
    '</p:otherStyle>'
    '</p:txStyles>'
    '</p:sldMaster>';

String _masterRels() {
  final out = StringBuffer(
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
    'relationships">',
  );
  for (var i = 1; i <= _layouts.length; i++) {
    out.write(
      '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/'
      'officeDocument/2006/relationships/slideLayout" '
      'Target="../slideLayouts/slideLayout$i.xml"/>',
    );
  }
  out.write(
    '<Relationship Id="rId${_layouts.length + 1}" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
    'relationships/theme" Target="../theme/theme1.xml"/>',
  );
  return (out..write('</Relationships>')).toString();
}

String _layoutRels() =>
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
    'relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/slideMaster" '
    'Target="../slideMasters/slideMaster1.xml"/>'
    '</Relationships>';

/// Three layouts: the opening, the ordinary slide, and one for a closing line
/// set large in the middle of the paper.
final List<String> _layouts = <String>[
  // 1: the title slide. Its title sits in the middle of the stage rather than
  // at the top, which is the whole reason a slide can inherit a box.
  '<p:sldLayout $_nsP type="title" preserve="1">'
      '<p:cSld name="Title Slide">'
      '<p:spTree>'
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/>'
      '</p:nvGrpSpPr><p:grpSpPr/>'
      '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title 1"/>'
      '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
      '<p:nvPr><p:ph type="ctrTitle"/></p:nvPr></p:nvSpPr>'
      '<p:spPr><a:xfrm><a:off x="${inches(1.2)}" y="${inches(2.3)}"/>'
      '<a:ext cx="${inches(10.9)}" cy="${inches(1.8)}"/></a:xfrm></p:spPr>'
      '<p:txBody><a:bodyPr anchor="b"/>'
      '<a:lstStyle><a:lvl1pPr><a:buNone/><a:defRPr sz="5400" b="1"/>'
      '</a:lvl1pPr></a:lstStyle><a:p/></p:txBody></p:sp>'
      '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Subtitle 2"/>'
      '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
      '<p:nvPr><p:ph type="subTitle" idx="1"/></p:nvPr></p:nvSpPr>'
      '<p:spPr><a:xfrm><a:off x="${inches(1.2)}" y="${inches(4.2)}"/>'
      '<a:ext cx="${inches(10.9)}" cy="${inches(1.1)}"/></a:xfrm></p:spPr>'
      '<p:txBody><a:bodyPr anchor="t"/>'
      '<a:lstStyle><a:lvl1pPr marL="0" indent="0"><a:buNone/>'
      '<a:defRPr sz="2000"><a:solidFill><a:schemeClr val="accent1"/>'
      '</a:solidFill></a:defRPr></a:lvl1pPr></a:lstStyle><a:p/></p:txBody>'
      '</p:sp>'
      '</p:spTree></p:cSld>'
      '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
      '</p:sldLayout>',
  // 2: title and content, the layout most of the deck stands on.
  '<p:sldLayout $_nsP type="obj" preserve="1">'
      '<p:cSld name="Title and Content">'
      '<p:spTree>'
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/>'
      '</p:nvGrpSpPr><p:grpSpPr/>'
      '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title 1"/>'
      '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
      '<p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>'
      '<p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/><a:p/></p:txBody></p:sp>'
      '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Content 2"/>'
      '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
      '<p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>'
      '<p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/><a:p/></p:txBody></p:sp>'
      '</p:spTree></p:cSld>'
      '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
      '</p:sldLayout>',
  // 3: a single line set large in the middle, for the last slide.
  '<p:sldLayout $_nsP type="titleOnly" preserve="1">'
      '<p:cSld name="Statement">'
      '<p:spTree>'
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/>'
      '</p:nvGrpSpPr><p:grpSpPr/>'
      '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title 1"/>'
      '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
      '<p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>'
      '<p:spPr><a:xfrm><a:off x="${inches(1.4)}" y="${inches(2.6)}"/>'
      '<a:ext cx="${inches(10.5)}" cy="${inches(2)}"/></a:xfrm></p:spPr>'
      '<p:txBody><a:bodyPr anchor="ctr"/>'
      '<a:lstStyle><a:lvl1pPr algn="ctr"><a:buNone/>'
      '<a:defRPr sz="4400" b="1"><a:solidFill><a:schemeClr val="bg1"/>'
      '</a:solidFill></a:defRPr></a:lvl1pPr></a:lstStyle><a:p/></p:txBody>'
      '</p:sp>'
      '</p:spTree></p:cSld>'
      '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
      '</p:sldLayout>',
];

/// One slide of the sample, with the layout it stands on and whether it
/// carries a picture or notes.
class _Slide {
  const _Slide(
    this.xml, {
    required this.layout,
    this.picture = false,
    this.notes = false,
  });
  final String xml;
  final int layout;
  final bool picture;
  final bool notes;
}

String _slideRels(_Slide slide, int index) {
  final out = StringBuffer(
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
    'relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/slideLayout" '
    'Target="../slideLayouts/slideLayout${slide.layout}.xml"/>',
  );
  if (slide.picture) {
    out.write(
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/'
      'officeDocument/2006/relationships/image" Target="../media/image1.png"/>',
    );
  }
  if (slide.notes) {
    out.write(
      '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/'
      'officeDocument/2006/relationships/notesSlide" '
      'Target="../notesSlides/notesSlide1.xml"/>',
    );
  }
  return (out..write('</Relationships>')).toString();
}

/// A plain filled rectangle.
String _rect({
  required int id,
  required String name,
  required int x,
  required int y,
  required int cx,
  required int cy,
  required String fill,
}) =>
    '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="$name"/><p:cNvSpPr/><p:nvPr/>'
    '</p:nvSpPr>'
    '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
    '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>$fill</p:spPr>'
    '<p:txBody><a:bodyPr/><a:lstStyle/><a:p/></p:txBody></p:sp>';

/// A text box owning nothing but its words.
String _textBox({
  required int id,
  required String name,
  required int x,
  required int y,
  required int cx,
  required int cy,
  required String paragraphs,
  String anchor = 't',
}) =>
    '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="$name"/>'
    '<p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
    '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
    '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>'
    '<p:txBody><a:bodyPr wrap="square" anchor="$anchor"/><a:lstStyle/>'
    '$paragraphs</p:txBody></p:sp>';

/// A placeholder shape that states no box at all, so it has to inherit one.
String _placeholder({
  required int id,
  required String name,
  required String type,
  int? index,
  required String paragraphs,
}) =>
    '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="$name"/>'
    '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
    '<p:nvPr><p:ph type="$type"${index == null ? '' : ' idx="$index"'}/>'
    '</p:nvPr></p:nvSpPr>'
    '<p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>$paragraphs</p:txBody></p:sp>';

String _slideHead(String tail) =>
    '<p:sld $_nsP><p:cSld>$tail</p:cSld>'
    '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>';

/// One run of text, with whatever is said about it.
String _run(String text, {int? size, bool bold = false, String? colour}) {
  final properties = StringBuffer('<a:rPr lang="en-GB"');
  if (size != null) properties.write(' sz="$size"');
  if (bold) properties.write(' b="1"');
  properties.write('>');
  if (colour != null) {
    properties.write('<a:solidFill>$colour</a:solidFill>');
  }
  properties.write('</a:rPr>');
  return '<a:r>$properties<a:t>${_escape(text)}</a:t></a:r>';
}

String _bullet(String text, {int level = 0}) =>
    '<a:p><a:pPr lvl="$level"/>${_run(text)}</a:p>';

String _line(String text, {int? size, bool bold = false, String? colour}) =>
    '<a:p><a:pPr><a:buNone/></a:pPr>'
    '${_run(text, size: size, bold: bold, colour: colour)}</a:p>';

String _numbered(String text) =>
    '<a:p><a:pPr marL="285750" indent="-285750">'
    '<a:buAutoNum type="arabicPeriod"/></a:pPr>${_run(text)}</a:p>';

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

final List<_Slide> _slides = <_Slide>[
  // 1. The opening. Neither shape states a box: both inherit from the layout,
  // which is the case a parser that reads only the slide gets wrong.
  _Slide(
    _slideHead(
      '<p:spTree>'
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/>'
      '</p:nvGrpSpPr><p:grpSpPr/>'
      '${_placeholder(
        id: 2,
        name: 'Title 1',
        type: 'ctrTitle',
        paragraphs: '<a:p>${_run('Press Day Briefing')}</a:p>',
      )}'
      '${_placeholder(
        id: 3,
        name: 'Subtitle 2',
        type: 'subTitle',
        index: 1,
        paragraphs: '<a:p>${_run('Michaelmas run, sheet fed, six formes')}'
            '</a:p>',
      )}'
      '</p:spTree>',
    ),
    layout: 1,
  ),
  // 2. Bullets at two levels, inherited from the master's body style.
  _Slide(
    _slideHead(
      '<p:spTree>'
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/>'
      '</p:nvGrpSpPr><p:grpSpPr/>'
      '${_placeholder(
        id: 2,
        name: 'Title 1',
        type: 'title',
        paragraphs: '<a:p>${_run('What changes today')}</a:p>',
      )}'
      '${_placeholder(
        id: 3,
        name: 'Content 2',
        type: 'body',
        index: 1,
        paragraphs: '${_bullet('Forme three comes off the stone at eleven')}'
            '${_bullet('The long grain stock is held back for the covers')}'
            '${_bullet('Two of the six formes are being reset', level: 1)}'
            '${_bullet('Ink up warm: the shop is cold until noon', level: 1)}'
            '${_bullet('Proofs go up on the wall, not in the tray')}',
      )}'
      '</p:spTree>',
    ),
    layout: 2,
  ),
  // 3. A table, with a header row and a tinted scheme colour behind it.
  _Slide(
    _slideHead(
      '<p:spTree>'
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/>'
      '</p:nvGrpSpPr><p:grpSpPr/>'
      '${_placeholder(
        id: 2,
        name: 'Title 1',
        type: 'title',
        paragraphs: '<a:p>${_run('The run in numbers')}</a:p>',
      )}'
      '${_tableFrame()}'
      '</p:spTree>',
    ),
    layout: 2,
  ),
  // 4. A picture with a caption under it.
  _Slide(
    _slideHead(
      '<p:spTree>'
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/>'
      '</p:nvGrpSpPr><p:grpSpPr/>'
      '${_placeholder(
        id: 2,
        name: 'Title 1',
        type: 'title',
        paragraphs: '<a:p>${_run('The proof from forme two')}</a:p>',
      )}'
      '${_picture()}'
      '${_textBox(
        id: 5,
        name: 'Caption',
        x: inches(7.6),
        y: inches(2.4),
        cx: inches(4.8),
        cy: inches(3),
        paragraphs: '${_line('Pulled at 09:40, before the reset.', size: 1800)}'
            '${_line('The gutter is a quarter pica wide on the left, and the '
                'head margin is short by a line.', size: 1800)}',
      )}'
      '</p:spTree>',
    ),
    layout: 2,
    picture: true,
  ),
  // 5. A numbered list, and the one slide carrying speaker notes.
  _Slide(
    _slideHead(
      '<p:spTree>'
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/>'
      '</p:nvGrpSpPr><p:grpSpPr/>'
      '${_placeholder(
        id: 2,
        name: 'Title 1',
        type: 'title',
        paragraphs: '<a:p>${_run('House rules at the press')}</a:p>',
      )}'
      '${_placeholder(
        id: 3,
        name: 'Content 2',
        type: 'body',
        index: 1,
        paragraphs: '${_numbered('Lock the forme before you lift it')}'
            '${_numbered('Wash the rollers down at every colour change')}'
            '${_numbered('Sign the sheet you approved, and date it')}'
            '${_numbered('Nothing leaves the shop without a docket')}',
      )}'
      '</p:spTree>',
    ),
    layout: 2,
    notes: true,
  ),
  // 6. The closing line, over a ground the slide sets for itself.
  _Slide(
    _slideHead(
      '<p:bg><p:bgPr><a:solidFill><a:schemeClr val="accent1">'
      '<a:lumMod val="75000"/></a:schemeClr></a:solidFill><a:effectLst/>'
      '</p:bgPr></p:bg>'
      '<p:spTree>'
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/>'
      '</p:nvGrpSpPr><p:grpSpPr/>'
      '${_placeholder(
        id: 2,
        name: 'Title 1',
        type: 'title',
        paragraphs: '<a:p>${_run('Sheets off by four, or not at all')}</a:p>',
      )}'
      '</p:spTree>',
    ),
    layout: 3,
  ),
];

String _tableFrame() {
  const headers = <String>['Forme', 'Sheets', 'Waste', 'Off at'];
  const rows = <List<String>>[
    <String>['One', '1,200', '38', '09:10'],
    <String>['Two', '1,200', '61', '10:25'],
    <String>['Three', '900', '24', '11:40'],
    <String>['Four', '900', '19', '13:05'],
  ];
  final width = inches(11.5);
  final column = width ~/ headers.length;

  final grid = StringBuffer('<a:tblGrid>');
  for (var i = 0; i < headers.length; i++) {
    grid.write('<a:gridCol w="$column"/>');
  }
  grid.write('</a:tblGrid>');

  String cell(String text, {bool header = false}) =>
      '<a:tc><a:txBody><a:bodyPr/><a:lstStyle/>'
      '<a:p><a:pPr><a:buNone/></a:pPr>'
      '${_run(text, size: header ? 1700 : 1600, bold: header, colour: header ? '<a:schemeClr val="bg1"/>' : null)}'
      '</a:p></a:txBody>'
      '<a:tcPr${header ? '' : ''}>'
      '${header ? '<a:solidFill><a:schemeClr val="accent2"/></a:solidFill>' : '<a:solidFill><a:schemeClr val="bg1"/></a:solidFill>'}'
      '</a:tcPr></a:tc>';

  final body = StringBuffer();
  body.write('<a:tr h="${inches(0.45)}">');
  for (final head in headers) {
    body.write(cell(head, header: true));
  }
  body.write('</a:tr>');
  for (final row in rows) {
    body.write('<a:tr h="${inches(0.4)}">');
    for (final value in row) {
      body.write(cell(value));
    }
    body.write('</a:tr>');
  }

  return '<p:graphicFrame>'
      '<p:nvGraphicFramePr><p:cNvPr id="4" name="Run table"/>'
      '<p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/>'
      '</p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>'
      '<p:xfrm><a:off x="${inches(0.9)}" y="${inches(2.1)}"/>'
      '<a:ext cx="$width" cy="${inches(2.05)}"/></p:xfrm>'
      '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/'
      'drawingml/2006/table">'
      '<a:tbl><a:tblPr firstRow="1" bandRow="1"/>$grid$body</a:tbl>'
      '</a:graphicData></a:graphic>'
      '</p:graphicFrame>';
}

String _picture() =>
    '<p:pic>'
    '<p:nvPicPr><p:cNvPr id="4" name="Proof sheet" '
    'descr="A proof pulled from forme two, ruled and marked up"/>'
    '<p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/>'
    '</p:nvPicPr>'
    '<p:blipFill><a:blip r:embed="rId2"/><a:stretch><a:fillRect/></a:stretch>'
    '</p:blipFill>'
    '<p:spPr><a:xfrm><a:off x="${inches(0.9)}" y="${inches(2.1)}"/>'
    '<a:ext cx="${inches(6.4)}" cy="${inches(3.6)}"/></a:xfrm>'
    '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
    '</p:pic>';

String _notes() =>
    '<p:notes $_nsP><p:cSld><p:spTree>'
    '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/>'
    '</p:nvGrpSpPr><p:grpSpPr/>'
    '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Notes Placeholder 1"/>'
    '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
    '<p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>'
    '<p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>'
    '${_line('Read the four out, then stop. The docket rule is the one they '
        'break, so leave a beat after it.')}'
    '${_line('If anyone asks about the reset formes, that is slide two, not '
        'this one.')}'
    '</p:txBody></p:sp>'
    '</p:spTree></p:cSld></p:notes>';

String _notesRels() =>
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
    'relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/slide" Target="../slides/slide5.xml"/>'
    '</Relationships>';

// The picture.

/// A proof sheet: warm paper, a block of ruled lines, and a mark in the
/// margin where the head is short.
///
/// Drawn here rather than shipped as a file so the sample owes nothing to
/// anybody, and small enough that the deck stays a few kilobytes.
Uint8List _proofSheetPng() {
  const width = 480;
  const height = 270;
  final pixels = Uint8List(width * height * 3);

  void set(int x, int y, int r, int g, int b) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    final at = (y * width + x) * 3;
    pixels[at] = r;
    pixels[at + 1] = g;
    pixels[at + 2] = b;
  }

  void fill(int x0, int y0, int x1, int y1, int r, int g, int b) {
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        set(x, y, r, g, b);
      }
    }
  }

  // The paper, and the plate mark around it.
  fill(0, 0, width, height, 0x3C, 0x3A, 0x36);
  fill(18, 14, width - 18, height - 14, 0xF7, 0xF2, 0xE8);
  fill(20, 16, width - 20, height - 16, 0xFD, 0xFA, 0xF3);

  // A heading rule, then the lines of a set page.
  fill(58, 44, 250, 50, 0x1A, 0x1A, 0x1A);
  for (var line = 0; line < 12; line++) {
    final y = 68 + line * 14;
    final long = line % 4 != 3;
    fill(58, y, long ? width - 92 : 300, y + 5, 0x55, 0x51, 0x4B);
  }

  // The margin mark: a short head, called out in the press's own red.
  fill(width - 74, 36, width - 70, 92, 0x9C, 0x3B, 0x2E);
  fill(width - 86, 36, width - 58, 40, 0x9C, 0x3B, 0x2E);

  return _encodePng(width, height, pixels);
}

/// The smallest honest PNG: one colour type, one filter, one pass.
Uint8List _encodePng(int width, int height, Uint8List rgb) {
  final raw = BytesBuilder(copy: false);
  for (var y = 0; y < height; y++) {
    raw.addByte(0);
    raw.add(Uint8List.sublistView(rgb, y * width * 3, (y + 1) * width * 3));
  }
  final header = BytesBuilder(copy: false)
    ..add(_be32(width))
    ..add(_be32(height))
    ..add(<int>[8, 2, 0, 0, 0]);

  final out = BytesBuilder(copy: false)
    ..add(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_chunk('IHDR', header.takeBytes()))
    ..add(
      _chunk(
        'IDAT',
        // The platform codec, named in full: `archive` exports a ZLibEncoder
        // of its own and the two take different arguments.
        Uint8List.fromList(ZLibCodec(level: 9).encode(raw.takeBytes())),
      ),
    )
    ..add(_chunk('IEND', Uint8List(0)));
  return out.takeBytes();
}

Uint8List _chunk(String name, Uint8List data) {
  final body = BytesBuilder(copy: false)
    ..add(ascii.encode(name))
    ..add(data);
  final bytes = body.takeBytes();
  return Uint8List.fromList(<int>[
    ..._be32(data.length),
    ...bytes,
    ..._be32(_crc32(bytes)),
  ]);
}

List<int> _be32(int value) => <int>[
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

final List<int> _crcTable = List<int>.generate(256, (i) {
  var c = i;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final byte in bytes) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
