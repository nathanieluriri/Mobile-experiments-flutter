import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quill/flutter_quill.dart' show Document, QuillController;
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/edit/pptx_deck.dart';
import 'package:quire/edit/pptx_text.dart';
import 'package:quire/edit/pptx_themes.dart';
import 'package:quire/format/pptx_parser.dart';
import 'package:quire/model/document.dart';
import 'package:quire/screens/reader/bodies/slide_sheet.dart';
import 'package:xml/xml.dart';

import 'support/evidence.dart';
import 'support/fixtures.dart';

Map<String, String> _parts(Uint8List bytes) => <String, String>{
  for (final f in ZipDecoder().decodeBytes(bytes).files)
    if (f.isFile && (f.name.endsWith('.xml') || f.name.endsWith('.rels')))
      f.name: utf8.decode(f.content),
};

Set<String> _names(Uint8List bytes) => <String>{
  for (final f in ZipDecoder().decodeBytes(bytes).files) f.name,
};

/// The deck as a fresh reader sees it after a save.
PptxDeck _reopen(PptxDeck deck) => PptxDeck(deck.write());

/// Every relationship of every part points at a part the package holds,
/// and every part has a content type.
void _expectWhole(Uint8List bytes) {
  final names = _names(bytes);
  final parts = _parts(bytes);
  final types = XmlDocument.parse(parts['[Content_Types].xml']!).rootElement;
  final overrides = <String>{
    for (final e in types.childElements)
      if (e.name.local == 'Override') e.getAttribute('PartName')!.substring(1),
  };
  final defaults = <String>{
    for (final e in types.childElements)
      if (e.name.local == 'Default') e.getAttribute('Extension')!.toLowerCase(),
  };
  for (final name in names) {
    if (name.endsWith('/')) continue;
    final ext = name.substring(name.lastIndexOf('.') + 1).toLowerCase();
    expect(overrides.contains(name) || defaults.contains(ext), isTrue, reason: '$name has no content type');
  }
  for (final o in overrides) {
    expect(names.contains(o), isTrue, reason: 'content type for missing $o');
  }
  String resolve(String owner, String target) {
    final dir = owner.contains('/') ? owner.substring(0, owner.lastIndexOf('/')) : '';
    final steps = <String>[if (dir.isNotEmpty) ...dir.split('/')];
    for (final step in target.split('/')) {
      if (step == '..') {
        steps.removeLast();
      } else if (step.isNotEmpty && step != '.') {
        steps.add(step);
      }
    }
    return target.startsWith('/') ? target.substring(1) : steps.join('/');
  }
  for (final entry in parts.entries) {
    if (!entry.key.endsWith('.rels')) continue;
    final owner = entry.key.replaceFirst('_rels/', '').replaceFirst(RegExp(r'\.rels$'), '');
    for (final rel in XmlDocument.parse(entry.value).rootElement.childElements) {
      if (rel.getAttribute('TargetMode') == 'External') continue;
      final resolved = resolve(owner, rel.getAttribute('Target')!);
      expect(names.contains(resolved), isTrue, reason: '${entry.key} points at missing $resolved');
    }
  }
  final reached = <String>{'[Content_Types].xml'};
  final queue = <String>[''];
  while (queue.isNotEmpty) {
    final owner = queue.removeLast();
    final cut = owner.lastIndexOf('/');
    final rels = owner.isEmpty ? '_rels/.rels' : '${owner.substring(0, cut + 1)}_rels/${owner.substring(cut + 1)}.rels';
    final xml = parts[rels];
    if (xml == null) continue;
    reached.add(rels);
    for (final rel in XmlDocument.parse(xml).rootElement.childElements) {
      if (rel.getAttribute('TargetMode') == 'External') continue;
      final to = resolve(owner, rel.getAttribute('Target')!);
      if (reached.add(to)) queue.add(to);
    }
  }
  for (final name in names) {
    if (name.endsWith('/')) continue;
    expect(reached.contains(name), isTrue, reason: '$name is in the file with nothing pointing at it');
  }
}

/// The sample deck with its six slides in two PowerPoint sections, three
/// each.
Uint8List _sectioned(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    if (f.name == 'ppt/presentation.xml') {
      final xml = utf8.decode(f.content).replaceFirst(
        '</p:presentation>',
        '<p:extLst><p:ext uri="{521415D9-36F7-43E2-AB2F-B90AF26B5E84}">'
            '<p14:sectionLst xmlns:p14="http://schemas.microsoft.com/office/powerpoint/2010/main">'
            '<p14:section name="One" id="{11111111-1111-1111-1111-111111111111}"><p14:sldIdLst>'
            '<p14:sldId id="256"/><p14:sldId id="257"/><p14:sldId id="258"/></p14:sldIdLst></p14:section>'
            '<p14:section name="Two" id="{22222222-2222-2222-2222-222222222222}"><p14:sldIdLst>'
            '<p14:sldId id="259"/><p14:sldId id="260"/><p14:sldId id="261"/></p14:sldIdLst></p14:section>'
            '</p14:sectionLst></p:ext></p:extLst></p:presentation>',
      );
      out.addFile(ArchiveFile.string(f.name, xml));
    } else {
      out.addFile(ArchiveFile.bytes(f.name, f.content));
    }
  }
  return ZipEncoder().encodeBytes(out);
}

/// Each section's slide ids, in order.
List<List<String>> _sections(Uint8List bytes) {
  final xml = XmlDocument.parse(_parts(bytes)['ppt/presentation.xml']!);
  return <List<String>>[
    for (final section in xml.rootElement.descendantElements.where((e) => e.name.local == 'section'))
      <String>[
        for (final id in section.descendantElements.where((e) => e.name.local == 'sldId')) id.getAttribute('id')!,
      ],
  ];
}

/// The sample deck with a clustered column chart, and no picture of it, on
/// its last slide.
Uint8List _charted(Uint8List bytes) {
  const chart = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><c:chart><c:autoTitleDeleted val="1"/><c:plotArea>'
      '<c:barChart><c:barDir val="col"/><c:grouping val="clustered"/>'
      '<c:ser><c:idx val="0"/><c:order val="0"/><c:tx><c:strRef><c:strCache><c:ptCount val="1"/><c:pt idx="0"><c:v>Monday</c:v></c:pt></c:strCache></c:strRef></c:tx>'
      '<c:cat><c:strRef><c:strCache><c:ptCount val="3"/><c:pt idx="0"><c:v>One</c:v></c:pt><c:pt idx="1"><c:v>Two</c:v></c:pt><c:pt idx="2"><c:v>Three</c:v></c:pt></c:strCache></c:strRef></c:cat>'
      '<c:val><c:numRef><c:numCache><c:ptCount val="3"/><c:pt idx="0"><c:v>1200</c:v></c:pt><c:pt idx="1"><c:v>1180</c:v></c:pt><c:pt idx="2"><c:v>900</c:v></c:pt></c:numCache></c:numRef></c:val></c:ser>'
      '<c:ser><c:idx val="1"/><c:order val="1"/><c:tx><c:strRef><c:strCache><c:ptCount val="1"/><c:pt idx="0"><c:v>Tuesday</c:v></c:pt></c:strCache></c:strRef></c:tx>'
      '<c:spPr><a:solidFill><a:srgbClr val="C0504D"/></a:solidFill></c:spPr>'
      '<c:val><c:numRef><c:numCache><c:ptCount val="3"/><c:pt idx="0"><c:v>1100</c:v></c:pt><c:pt idx="2"><c:v>950</c:v></c:pt></c:numCache></c:numRef></c:val></c:ser>'
      '<c:axId val="11"/><c:axId val="12"/></c:barChart>'
      '<c:catAx><c:axId val="11"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="b"/><c:crossAx val="12"/></c:catAx>'
      '<c:valAx><c:axId val="12"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="l"/><c:crossAx val="11"/></c:valAx>'
      '</c:plotArea><c:legend><c:legendPos val="b"/></c:legend></c:chart></c:chartSpace>';
  const frame = '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="30" name="Chart 30"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>'
      '<p:xfrm><a:off x="914400" y="1828800"/><a:ext cx="6096000" cy="3048000"/></p:xfrm><a:graphic>'
      '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">'
      '<c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" r:id="rId9"/></a:graphicData></a:graphic></p:graphicFrame>';
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    var text = f.name.endsWith('.xml') || f.name.endsWith('.rels') ? utf8.decode(f.content) : null;
    if (f.name == 'ppt/slides/slide6.xml') text = text!.replaceFirst('</p:spTree>', '$frame</p:spTree>');
    if (f.name == 'ppt/slides/_rels/slide6.xml.rels') {
      text = text!.replaceFirst(
        '</Relationships>',
        '<Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart1.xml"/></Relationships>',
      );
    }
    if (f.name == '[Content_Types].xml') {
      text = text!.replaceFirst(
        '</Types>',
        '<Override PartName="/ppt/charts/chart1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/></Types>',
      );
    }
    out.addFile(text == null ? ArchiveFile.bytes(f.name, f.content) : ArchiveFile.string(f.name, text));
  }
  out.addFile(ArchiveFile.string('ppt/charts/chart1.xml', chart));
  return ZipEncoder().encodeBytes(out);
}

/// The sample deck with slide 2's body holding a plain paragraph, a
/// Japanese one in its own East Asian face, one with a link to a web page
/// and one to slide 6, and a second-level one in Georgia.
Uint8List _linked(Uint8List bytes) {
  const body = '<p:txBody><a:bodyPr/><a:lstStyle/>'
      '<a:p><a:r><a:rPr lang="en-GB"/><a:t>Forme three</a:t></a:r></a:p>'
      '<a:p><a:r><a:rPr lang="ja-JP" altLang="en-US"><a:ea typeface="MS Mincho"/></a:rPr><a:t>\u65E5\u672C\u8A9E\u306E\u30C6\u30AD\u30B9\u30C8\u3067\u3059</a:t></a:r></a:p>'
      '<a:p><a:r><a:rPr lang="en-GB"><a:hlinkClick r:id="rId2"/></a:rPr><a:t>Visit the site</a:t></a:r>'
      '<a:r><a:rPr lang="en-GB"/><a:t> or </a:t></a:r>'
      '<a:r><a:rPr lang="en-GB"><a:hlinkClick r:id="rId3" action="ppaction://hlinksldjump"/></a:rPr><a:t>jump to wrap up</a:t></a:r></a:p>'
      '<a:p><a:pPr lvl="1"/><a:r><a:rPr lang="en-GB" sz="2000"><a:latin typeface="Georgia"/></a:rPr><a:t>Second level in Georgia</a:t></a:r></a:p>'
      '</p:txBody>';
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    var text = f.name.endsWith('.xml') || f.name.endsWith('.rels') ? utf8.decode(f.content) : null;
    if (f.name == 'ppt/slides/slide2.xml') {
      final at = text!.indexOf('<p:txBody>', text.indexOf('name="Content 2"'));
      final end = text.indexOf('</p:txBody>', at) + '</p:txBody>'.length;
      text = text.replaceRange(at, end, body);
    }
    if (f.name == 'ppt/slides/_rels/slide2.xml.rels') {
      text = text!.replaceFirst(
        '</Relationships>',
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://example.com/" TargetMode="External"/>'
            '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slide6.xml"/></Relationships>',
      );
    }
    out.addFile(text == null ? ArchiveFile.bytes(f.name, f.content) : ArchiveFile.string(f.name, text));
  }
  return ZipEncoder().encodeBytes(out);
}

/// The sample deck with a table on its last slide that leaves its look
/// to PowerPoint's Medium Style 2 in the first accent: a heading row and
/// banded rows, no fills of its own.
Uint8List _styledTable(Uint8List bytes) {
  String row(String a, String b) => '<a:tr h="370840">'
      '<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-GB"/><a:t>$a</a:t></a:r></a:p></a:txBody><a:tcPr/></a:tc>'
      '<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-GB"/><a:t>$b</a:t></a:r></a:p></a:txBody><a:tcPr/></a:tc></a:tr>';
  final frame = '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="31" name="Table 31"/><p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>'
      '<p:xfrm><a:off x="914400" y="1828800"/><a:ext cx="4572000" cy="1112520"/></p:xfrm><a:graphic>'
      '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table"><a:tbl>'
      '<a:tblPr firstRow="1" bandRow="1"><a:tableStyleId>{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}</a:tableStyleId></a:tblPr>'
      '<a:tblGrid><a:gridCol w="2286000"/><a:gridCol w="2286000"/></a:tblGrid>'
      '${row('Forme', 'Stock')}${row('One', 'Laid')}${row('Two', 'Wove')}'
      '</a:tbl></a:graphicData></a:graphic></p:graphicFrame>';
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    if (f.name == 'ppt/slides/slide6.xml') {
      out.addFile(ArchiveFile.string(f.name, utf8.decode(f.content).replaceFirst('</p:spTree>', '$frame</p:spTree>')));
    } else {
      out.addFile(ArchiveFile.bytes(f.name, f.content));
    }
  }
  return ZipEncoder().encodeBytes(out);
}

/// [bytes] with a shape on slide 6 whose click jumps back to slide 2.
Uint8List _backLinked(Uint8List bytes) {
  const shape = '<p:sp><p:nvSpPr><p:cNvPr id="40" name="Back"><a:hlinkClick r:id="rId9" action="ppaction://hlinksldjump"/></p:cNvPr>'
      '<p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="457200" y="4572000"/><a:ext cx="914400" cy="457200"/></a:xfrm>'
      '<a:prstGeom prst="leftArrow"><a:avLst/></a:prstGeom></p:spPr></p:sp>';
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    var text = f.name.endsWith('.xml') || f.name.endsWith('.rels') ? utf8.decode(f.content) : null;
    if (f.name == 'ppt/slides/slide6.xml') text = text!.replaceFirst('</p:spTree>', '$shape</p:spTree>');
    if (f.name == 'ppt/slides/_rels/slide6.xml.rels') {
      text = text!.replaceFirst(
        '</Relationships>',
        '<Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slide2.xml"/></Relationships>',
      );
    }
    out.addFile(text == null ? ArchiveFile.bytes(f.name, f.content) : ArchiveFile.string(f.name, text));
  }
  return ZipEncoder().encodeBytes(out);
}

/// The sample deck with a SmartArt on its last slide, laid out as
/// PowerPoint writes one: its data part names its drawing through the
/// slide's own relationship.
Uint8List _smartArt(Uint8List bytes) {
  const dgm = 'http://schemas.openxmlformats.org/drawingml/2006/diagram';
  const frame = '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="50" name="Diagram 50"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>'
      '<p:xfrm><a:off x="914400" y="1828800"/><a:ext cx="6096000" cy="2286000"/></p:xfrm><a:graphic>'
      '<a:graphicData uri="$dgm"><dgm:relIds xmlns:dgm="$dgm" r:dm="rId20" r:lo="rId21" r:qs="rId22" r:cs="rId23"/></a:graphicData></a:graphic></p:graphicFrame>';
  const rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  const parts = <String, String>{
    'ppt/diagrams/data1.xml': '<dgm:dataModel xmlns:dgm="$dgm" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><dgm:ptLst/>'
        '<dgm:extLst><a:ext uri="http://schemas.microsoft.com/office/drawing/2008/diagram">'
        '<dsp:dataModelExt xmlns:dsp="http://schemas.microsoft.com/office/drawing/2008/diagram" relId="rId24" minVer="$dgm"/>'
        '</a:ext></dgm:extLst></dgm:dataModel>',
    'ppt/diagrams/layout1.xml': '<dgm:layoutDef xmlns:dgm="$dgm"/>',
    'ppt/diagrams/quickStyle1.xml': '<dgm:styleDef xmlns:dgm="$dgm"/>',
    'ppt/diagrams/colors1.xml': '<dgm:colorsDef xmlns:dgm="$dgm"/>',
    'ppt/diagrams/drawing1.xml': '<dsp:drawing xmlns:dsp="http://schemas.microsoft.com/office/drawing/2008/diagram"><dsp:spTree/></dsp:drawing>',
  };
  const types = <String, String>{
    'data1': 'application/vnd.openxmlformats-officedocument.drawingml.diagramData+xml',
    'layout1': 'application/vnd.openxmlformats-officedocument.drawingml.diagramLayout+xml',
    'quickStyle1': 'application/vnd.openxmlformats-officedocument.drawingml.diagramStyle+xml',
    'colors1': 'application/vnd.openxmlformats-officedocument.drawingml.diagramColors+xml',
    'drawing1': 'application/vnd.ms-office.drawingml.diagramDrawing+xml',
  };
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    var text = f.name.endsWith('.xml') || f.name.endsWith('.rels') ? utf8.decode(f.content) : null;
    if (f.name == 'ppt/slides/slide6.xml') text = text!.replaceFirst('</p:spTree>', '$frame</p:spTree>');
    if (f.name == 'ppt/slides/_rels/slide6.xml.rels') {
      text = text!.replaceFirst(
        '</Relationships>',
        '<Relationship Id="rId20" Type="$rel/diagramData" Target="../diagrams/data1.xml"/>'
            '<Relationship Id="rId21" Type="$rel/diagramLayout" Target="../diagrams/layout1.xml"/>'
            '<Relationship Id="rId22" Type="$rel/diagramQuickStyle" Target="../diagrams/quickStyle1.xml"/>'
            '<Relationship Id="rId23" Type="$rel/diagramColors" Target="../diagrams/colors1.xml"/>'
            '<Relationship Id="rId24" Type="http://schemas.microsoft.com/office/2007/relationships/diagramDrawing" Target="../diagrams/drawing1.xml"/>'
            '</Relationships>',
      );
    }
    if (f.name == '[Content_Types].xml') {
      text = text!.replaceFirst('</Types>', '${types.entries.map((e) => '<Override PartName="/ppt/diagrams/${e.key}.xml" ContentType="${e.value}"/>').join()}</Types>');
    }
    out.addFile(text == null ? ArchiveFile.bytes(f.name, f.content) : ArchiveFile.string(f.name, text));
  }
  for (final e in parts.entries) {
    out.addFile(ArchiveFile.string(e.key, e.value));
  }
  return ZipEncoder().encodeBytes(out);
}

/// The sample deck with slide 4's caption and a plain frame put in a group,
/// id 9.
Uint8List _grouped(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    if (f.name == 'ppt/slides/slide4.xml') {
      var xml = utf8.decode(f.content);
      final start = xml.indexOf('<p:sp><p:nvSpPr><p:cNvPr id="5" name="Caption"/>');
      final end = xml.indexOf('</p:sp>', start) + '</p:sp>'.length;
      final caption = xml.substring(start, end);
      xml = xml.replaceRange(
        start,
        end,
        '<p:grpSp><p:nvGrpSpPr><p:cNvPr id="9" name="Group 9"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="6949440" y="2194560"/><a:ext cx="4389120" cy="2743200"/>'
        '<a:chOff x="6949440" y="2194560"/><a:chExt cx="4389120" cy="2743200"/></a:xfrm></p:grpSpPr>'
        '$caption<p:sp><p:nvSpPr><p:cNvPr id="12" name="Frame"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="6949440" y="2194560"/><a:ext cx="914400" cy="914400"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:sp>'
        '</p:grpSp>',
      );
      out.addFile(ArchiveFile.string(f.name, xml));
    } else {
      out.addFile(ArchiveFile.bytes(f.name, f.content));
    }
  }
  return ZipEncoder().encodeBytes(out);
}

/// The sample deck with slide 4's caption fading in on a click, and then
/// its picture flying in.
Uint8List _animated(Uint8List bytes) {
  String effect(int node, String spid, String preset) => '<p:par><p:cTn id="$node" fill="hold"><p:stCondLst><p:cond delay="indefinite"/></p:stCondLst><p:childTnLst>'
      '<p:par><p:cTn id="${node + 1}" fill="hold"><p:stCondLst><p:cond delay="0"/></p:stCondLst><p:childTnLst>'
      '<p:par><p:cTn id="${node + 2}" presetID="$preset" presetClass="entr" presetSubtype="0" fill="hold" grpId="0" nodeType="clickEffect">'
      '<p:stCondLst><p:cond delay="0"/></p:stCondLst><p:childTnLst>'
      '<p:set><p:cBhvr><p:cTn id="${node + 3}" dur="1" fill="hold"><p:stCondLst><p:cond delay="0"/></p:stCondLst></p:cTn>'
      '<p:tgtEl><p:spTgt spid="$spid"/></p:tgtEl><p:attrNameLst><p:attrName>style.visibility</p:attrName></p:attrNameLst></p:cBhvr>'
      '<p:to><p:strVal val="visible"/></p:to></p:set>'
      '</p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par>';
  final timing = '<p:timing><p:tnLst><p:par><p:cTn id="1" dur="indefinite" restart="never" nodeType="tmRoot"><p:childTnLst>'
      '<p:seq concurrent="1" nextAc="seek"><p:cTn id="2" dur="indefinite" nodeType="mainSeq"><p:childTnLst>'
      '${effect(3, '5', '10')}${effect(7, '4', '2')}'
      '</p:childTnLst></p:cTn><p:prevCondLst><p:cond evt="onPrev" delay="0"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:prevCondLst>'
      '<p:nextCondLst><p:cond evt="onNext" delay="0"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:nextCondLst></p:seq>'
      '</p:childTnLst></p:cTn></p:par></p:tnLst><p:bldLst><p:bldP spid="5" grpId="0"/></p:bldLst></p:timing>';
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    if (f.name == 'ppt/slides/slide4.xml') {
      out.addFile(ArchiveFile.string(f.name, utf8.decode(f.content).replaceFirst('</p:clrMapOvr>', '</p:clrMapOvr>$timing')));
    } else {
      out.addFile(ArchiveFile.bytes(f.name, f.content));
    }
  }
  return ZipEncoder().encodeBytes(out);
}

/// The sample deck with two boxes on its last slide and a connector glued
/// from the right of the first, id 20, to the left of the second, id 21.
Uint8List _glued(Uint8List bytes) {
  String box(int id, int x) => '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="Box $id"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
      '<p:spPr><a:xfrm><a:off x="$x" y="2540000"/><a:ext cx="1270000" cy="1270000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:sp>';
  final shapes = '${box(20, 1270000)}${box(21, 5080000)}'
      '<p:cxnSp><p:nvCxnSpPr><p:cNvPr id="22" name="Connector 22"/><p:cNvCxnSpPr><a:stCxn id="20" idx="3"/><a:endCxn id="21" idx="1"/></p:cNvCxnSpPr><p:nvPr/></p:nvCxnSpPr>'
      '<p:spPr><a:xfrm><a:off x="2540000" y="3175000"/><a:ext cx="2540000" cy="0"/></a:xfrm><a:prstGeom prst="straightConnector1"><a:avLst/></a:prstGeom>'
      '<a:ln w="12700"><a:solidFill><a:srgbClr val="000000"/></a:solidFill></a:ln></p:spPr></p:cxnSp>';
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    if (f.name == 'ppt/slides/slide6.xml') {
      out.addFile(ArchiveFile.string(f.name, utf8.decode(f.content).replaceFirst('</p:spTree>', '$shapes</p:spTree>')));
    } else {
      out.addFile(ArchiveFile.bytes(f.name, f.content));
    }
  }
  return ZipEncoder().encodeBytes(out);
}

/// The sample deck with a designed master: a rounded, filled and outlined
/// title band in capitals with wide spacing in the heading face, and body
/// bullets in red Wingdings at 80%.
Uint8List _designed(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    if (f.name == 'ppt/slideMasters/slideMaster1.xml') {
      var xml = utf8.decode(f.content);
      final title = xml.indexOf('<a:xfrm>', xml.indexOf('name="Title Placeholder 1"'));
      final end = xml.indexOf('</a:xfrm>', title) + '</a:xfrm>'.length;
      xml = xml.replaceRange(
        end,
        end,
        '<a:prstGeom prst="roundRect"><a:avLst/></a:prstGeom><a:solidFill><a:schemeClr val="accent2"><a:lumMod val="20000"/><a:lumOff val="80000"/></a:schemeClr></a:solidFill>'
        '<a:ln w="38100"><a:solidFill><a:schemeClr val="accent2"/></a:solidFill></a:ln>',
      );
      xml = xml.replaceFirst(
        '<a:defRPr sz="4000" b="1"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill></a:defRPr>',
        '<a:defRPr sz="4000" b="1" cap="all" spc="300"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill><a:latin typeface="+mj-lt"/></a:defRPr>',
      );
      xml = xml.replaceFirst(
        '<a:lvl1pPr marL="285750" indent="-285750"><a:buChar char="\u2022"/>',
        '<a:lvl1pPr marL="285750" indent="-285750"><a:buClr><a:srgbClr val="FF0000"/></a:buClr><a:buSzPct val="80000"/><a:buFont typeface="Wingdings"/><a:buChar char="\u00A7"/>',
      );
      out.addFile(ArchiveFile.string(f.name, xml));
    } else {
      out.addFile(ArchiveFile.bytes(f.name, f.content));
    }
  }
  return ZipEncoder().encodeBytes(out);
}

/// The sample deck with slide 4's picture made the layout's content
/// placeholder, placed where the layout puts it.
Uint8List _pictureHolder(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    if (f.name == 'ppt/slides/slide4.xml') {
      var xml = utf8.decode(f.content);
      final at = xml.indexOf('name="Proof sheet"');
      final nvPr = xml.indexOf('<p:nvPr/>', at);
      xml = xml.replaceRange(nvPr, nvPr + '<p:nvPr/>'.length, '<p:nvPr><p:ph type="pic" idx="1"/></p:nvPr>');
      final xfrm = xml.indexOf('<a:xfrm>', nvPr);
      final done = xml.indexOf('</a:xfrm>', xfrm) + '</a:xfrm>'.length;
      xml = xml.replaceRange(xfrm, done, '');
      out.addFile(ArchiveFile.string(f.name, xml));
    } else {
      out.addFile(ArchiveFile.bytes(f.name, f.content));
    }
  }
  return ZipEncoder().encodeBytes(out);
}

/// The sample deck with a master that has PowerPoint's date, footer and
/// slide number placeholders at idx 2, 3 and 4, each centred low, grey
/// and set right, and slide 2 given a second content placeholder at idx 2.
Uint8List _footed(Uint8List bytes) {
  String furniture(int id, String type, int idx) => '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="$type $idx"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
      '<p:nvPr><p:ph type="$type" sz="quarter" idx="$idx"/></p:nvPr></p:nvSpPr>'
      '<p:spPr><a:xfrm><a:off x="${822960 + idx * 1000000}" y="6356350"/><a:ext cx="2743200" cy="365125"/></a:xfrm></p:spPr>'
      '<p:txBody><a:bodyPr anchor="ctr"/><a:lstStyle><a:lvl1pPr algn="r"><a:defRPr sz="1200"><a:solidFill><a:srgbClr val="8C8C8C"/></a:solidFill></a:defRPr></a:lvl1pPr></a:lstStyle><a:p/></p:txBody></p:sp>';
  const second = '<p:sp><p:nvSpPr><p:cNvPr id="9" name="Content 9"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph idx="2"/></p:nvPr></p:nvSpPr>'
      '<p:spPr><a:xfrm><a:off x="6400800" y="1737360"/><a:ext cx="4572000" cy="3200400"/></a:xfrm></p:spPr>'
      '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-GB"/><a:t>Right column point</a:t></a:r></a:p></p:txBody></p:sp>';
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    var text = f.name.endsWith('.xml') ? utf8.decode(f.content) : null;
    if (f.name == 'ppt/slideMasters/slideMaster1.xml') {
      text = text!.replaceFirst('</p:spTree>', '${furniture(20, 'dt', 2)}${furniture(21, 'ftr', 3)}${furniture(22, 'sldNum', 4)}</p:spTree>');
    }
    if (f.name == 'ppt/slides/slide2.xml') text = text!.replaceFirst('</p:spTree>', '$second</p:spTree>');
    out.addFile(text == null ? ArchiveFile.bytes(f.name, f.content) : ArchiveFile.string(f.name, text));
  }
  return ZipEncoder().encodeBytes(out);
}

/// The sample deck with slide 4's picture cropped to its middle half.
Uint8List _cropped(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    if (f.name == 'ppt/slides/slide4.xml') {
      out.addFile(ArchiveFile.string(
        f.name,
        utf8.decode(f.content).replaceFirst('<a:blip r:embed="rId2"/><a:stretch>', '<a:blip r:embed="rId2"/><a:srcRect l="25000" r="25000"/><a:stretch>'),
      ));
    } else {
      out.addFile(ArchiveFile.bytes(f.name, f.content));
    }
  }
  return ZipEncoder().encodeBytes(out);
}

/// The sample deck with slide 4's caption set to run on one line, as
/// PowerPoint's click-made boxes do.
Uint8List _unwrapped(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    if (f.name == 'ppt/slides/slide4.xml') {
      final xml = utf8.decode(f.content);
      final at = xml.indexOf('<a:bodyPr', xml.indexOf('name="Caption"'));
      final end = xml.indexOf('>', at);
      final tag = xml.substring(at, end + 1);
      final unwrapped = tag.contains('wrap="') ? tag.replaceFirst(RegExp(r'wrap="[^"]*"'), 'wrap="none"') : tag.replaceFirst('<a:bodyPr', '<a:bodyPr wrap="none"');
      out.addFile(ArchiveFile.string(f.name, xml.replaceRange(at, end + 1, unwrapped)));
    } else {
      out.addFile(ArchiveFile.bytes(f.name, f.content));
    }
  }
  return ZipEncoder().encodeBytes(out);
}

/// The sample deck with slide 2's body shrunk to 55% by PowerPoint.
Uint8List _shrunk(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    if (f.name == 'ppt/slides/slide2.xml') {
      final xml = utf8.decode(f.content);
      final at = xml.indexOf('<a:bodyPr/>', xml.indexOf('name="Content 2"'));
      out.addFile(ArchiveFile.string(
        f.name,
        xml.replaceRange(at, at + '<a:bodyPr/>'.length, '<a:bodyPr><a:normAutofit fontScale="55000" lnSpcReduction="20000"/></a:bodyPr>'),
      ));
    } else {
      out.addFile(ArchiveFile.bytes(f.name, f.content));
    }
  }
  return ZipEncoder().encodeBytes(out);
}

/// The sample deck with slide 2 on a dark blue to black ground and slide
/// 4's caption filled from red to gold.
Uint8List _graded(Uint8List bytes) {
  const ground = '<p:bg><p:bgPr><a:gradFill><a:gsLst><a:gs pos="0"><a:srgbClr val="1F3864"/></a:gs>'
      '<a:gs pos="100000"><a:srgbClr val="000000"/></a:gs></a:gsLst><a:lin ang="5400000" scaled="0"/></a:gradFill><a:effectLst/></p:bgPr></p:bg>';
  const fill = '<a:gradFill><a:gsLst><a:gs pos="0"><a:srgbClr val="C00000"/></a:gs><a:gs pos="100000"><a:srgbClr val="FFC000"/></a:gs></a:gsLst>'
      '<a:lin ang="0" scaled="0"/></a:gradFill>';
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    var text = f.name.endsWith('.xml') ? utf8.decode(f.content) : null;
    if (f.name == 'ppt/slides/slide2.xml') text = text!.replaceFirst('<p:cSld>', '<p:cSld>$ground');
    if (f.name == 'ppt/slides/slide4.xml') {
      final at = text!.indexOf('<a:noFill/>', text.indexOf('name="Caption"'));
      text = text.replaceRange(at, at + '<a:noFill/>'.length, fill);
    }
    out.addFile(text == null ? ArchiveFile.bytes(f.name, f.content) : ArchiveFile.string(f.name, text));
  }
  return ZipEncoder().encodeBytes(out);
}

void main() {
  late Uint8List bytes;

  setUpAll(() async {
    bytes = await documentBytes(kPressDayBriefing);
  });

  group('the deck model', () {
    test('writes back the very bytes it read when nothing changed', () {
      final deck = PptxDeck(bytes);
      expect(deck.slides.length, 6);
      expect(deck.write(), same(bytes));
    });

    test('moves, sizes and turns a shape, and undo takes each step back', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[3];
      final picture = deck.objects(slide).firstWhere((o) => o.isPicture);
      deck.place(slide, picture.id, const SlideBox(100, 120, 300, 200));
      deck.place(slide, picture.id, const SlideBox(100, 120, 300, 200), rotation: 30);
      final again = _reopen(deck);
      final moved = again.object(again.slides[3], picture.id)!;
      expect(moved.box, const SlideBox(100, 120, 300, 200));
      expect(moved.rotation, closeTo(30, 0.01));
      deck.undo();
      expect(deck.object(slide, picture.id)!.rotation, 0);
      deck.undo();
      expect(deck.object(slide, picture.id)!.box, picture.box);
      expect(deck.write(), same(bytes));
      deck.redo();
      expect(deck.object(slide, picture.id)!.box, const SlideBox(100, 120, 300, 200));
    });

    test('moving a placeholder gives it a box of its own', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[1];
      final title = deck.objects(slide).firstWhere((o) => o.placeholder == 'title');
      deck.place(slide, title.id, SlideBox(title.box.left + 40, title.box.top, title.box.width, title.box.height));
      final again = _reopen(deck);
      expect(again.object(again.slides[1], title.id)!.box.left, closeTo(title.box.left + 40, 0.01));
      final shape = again.slide(again.slides[1]).shapes.firstWhere((s) => s.id == title.id);
      expect(shape.text, 'What changes today');
    });

    test('deletes a shape, and copies one onto another slide with its picture', () {
      final deck = PptxDeck(bytes);
      final from = deck.slides[3];
      final to = deck.slides[5];
      final picture = deck.objects(from).firstWhere((o) => o.isPicture);
      final clip = deck.copy(from, <int>{picture.id});
      final made = deck.paste(to, clip);
      expect(made, hasLength(1));
      deck.delete(from, <int>{picture.id});
      final out = deck.write();
      _expectWhole(out);
      final again = PptxDeck(out);
      expect(again.objects(again.slides[3]).where((o) => o.isPicture), isEmpty);
      final pasted = again.slide(again.slides[5]).shapes.where((s) => s.blocks.any((b) => b is ImageBlock));
      expect(pasted, hasLength(1));
      final image = pasted.single.blocks.whereType<ImageBlock>().single;
      expect(again.assets[image.assetKey], isNotNull);
    });

    test('a pasted copy on its own slide lands down and to the right', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[3];
      final caption = deck.objects(slide).firstWhere((o) => o.name == 'Caption');
      final made = deck.duplicate(slide, <int>{caption.id}).single;
      final copy = deck.object(slide, made)!;
      expect(copy.box.left, closeTo(caption.box.left + 10, 0.01));
      expect(copy.box.top, closeTo(caption.box.top + 10, 0.01));
      expect(deck.shape(slide, made)!.text, deck.shape(slide, caption.id)!.text);
    });

    test('a copied placeholder states its own box and look', () {
      final deck = PptxDeck(bytes);
      final from = deck.slides[1];
      final body = deck.objects(from).firstWhere((o) => o.placeholder == 'body');
      final was = deck.shape(from, body.id)!;
      final made = deck.paste(deck.slides[3], deck.copy(from, <int>{body.id})).single;
      final again = _reopen(deck);
      final pasted = again.shape(again.slides[3], made)!;
      expect(pasted.box, was.box);
      final wasItems = was.blocks.whereType<ListItemBlock>().toList();
      final nowItems = pasted.blocks.whereType<ListItemBlock>().toList();
      expect(nowItems.length, wasItems.length);
      expect(nowItems.first.spans.first.fontSize, wasItems.first.spans.first.fontSize);
      expect(nowItems[2].level, 1);
    });

    test('adds a slide from a layout, with the layout placeholders empty', () {
      final deck = PptxDeck(bytes);
      final layout = deck.layouts.firstWhere((l) => l.type == 'obj');
      final made = deck.addSlide(layout.path, 2);
      expect(deck.slides.length, 7);
      expect(deck.slides[2], made);
      final objects = deck.objects(made);
      expect(objects.map((o) => o.placeholder), containsAll(<String>['title', 'body']));
      final out = deck.write();
      _expectWhole(out);
      final reread = PptxParser(out).parse();
      expect(reread.sections.length, 7);
    });

    test('duplicates a slide with its notes, and deletes slides cleanly', () {
      final deck = PptxDeck(bytes);
      final first = deck.slides.first;
      final noted = deck.slides[4];
      final made = deck.duplicateSlides(<String>[noted]).single;
      expect(deck.slides[5], made);
      final reread = PptxParser(deck.write()).parse();
      final notes = reread.sections[5].blocks.whereType<SlideBlock>().single.notes;
      expect(notes, isNotEmpty);
      expect(notes.length, reread.sections[4].blocks.whereType<SlideBlock>().single.notes.length);
      final copyNotes = _parts(deck.write()).entries.where((e) => e.key.startsWith('ppt/notesSlides/_rels/') && e.value.contains(made.split('/').last));
      expect(copyNotes, hasLength(1));
      deck.deleteSlides(<String>{first, deck.slides[2]});
      expect(deck.slides, isNot(contains(first)));
      final out = deck.write();
      _expectWhole(out);
      expect(_names(out).contains(first), isFalse);
      final after = PptxParser(out).parse();
      expect(after.sections.length, 5);
      expect(after.sections.first.title, 'What changes today');
    });

    test('keeps PowerPoint\'s sections in step with the slides', () {
      final deck = PptxDeck(_sectioned(bytes));
      final order = deck.slides;
      deck.deleteSlides(<String>{order[1]});
      expect(_sections(deck.write()), <List<String>>[
        <String>['256', '258'],
        <String>['259', '260', '261'],
      ]);
      deck.moveSlides(<String>[order[5]], 0);
      expect(_sections(deck.write()), <List<String>>[
        <String>['261', '256', '258'],
        <String>['259', '260'],
      ]);
      final layout = deck.layouts.first.path;
      deck.addSlide(layout, 3);
      expect(_sections(deck.write()), <List<String>>[
        <String>['261', '256', '258', '262'],
        <String>['259', '260'],
      ]);
      _expectWhole(deck.write());
    });

    test('reads a chart with no picture of it from its cached values', () {
      final deck = PptxDeck(_charted(bytes));
      final shape = deck.shape(deck.slides[5], 30)!;
      final chart = shape.chart!;
      expect(chart.kind, 'col');
      expect(chart.categories, <String>['One', 'Two', 'Three']);
      expect(chart.series.map((s) => s.name), <String>['Monday', 'Tuesday']);
      expect(chart.series[1].values, <double?>[1100, null, 950]);
      expect(chart.series[1].colour, 0xFFC0504D);
      expect(chart.legend, isTrue);
      // A copy of the chart has a chart part of its own.
      final made = deck.paste(deck.slides[4], deck.copy(deck.slides[5], <int>{30})).single;
      final out = deck.write();
      _expectWhole(out);
      final again = PptxDeck(out);
      expect(again.shape(again.slides[4], made)!.chart!.series, hasLength(2));
      expect(_names(out).where((n) => n.startsWith('ppt/charts/chart')), hasLength(2));
    });

    testWidgets('a chart with no picture of it is drawn on its slide', (tester) async {
      final deck = PptxDeck(_charted(bytes));
      await tester.pumpWidget(MaterialApp(home: Center(child: SlideSheet(slide: deck.slide(deck.slides[5]), assets: deck.assets, width: 400))));
      final painters = tester.widgetList<CustomPaint>(find.byType(CustomPaint)).map((w) => w.painter).whereType<SlideChartPainter>();
      expect(painters, hasLength(1));
      expect(painters.single.chart.series, hasLength(2));
    });

    test('never deletes the last slide', () {
      final deck = PptxDeck(bytes);
      deck.deleteSlides(deck.slides.toSet());
      expect(deck.slides.length, 6);
      expect(deck.canUndo, isFalse);
    });

    test('moves slides together to a new place', () {
      final deck = PptxDeck(bytes);
      final order = deck.slides;
      deck.moveSlides(<String>[order[4], order[1]], 0);
      expect(deck.slides, <String>[order[1], order[4], order[0], order[2], order[3], order[5]]);
      final reread = PptxParser(deck.write()).parse();
      expect(reread.sections[1].title, PptxParser(bytes).parse().sections[4].title);
    });

    test('cut slides paste back after their neighbours are gone', () {
      final deck = PptxDeck(bytes);
      final order = deck.slides;
      final clip = deck.copySlides(<String>[order[0]]);
      deck.deleteSlides(<String>{order[0]});
      final made = deck.pasteSlides(clip, 3);
      expect(deck.slides[3], made.single);
      final out = deck.write();
      _expectWhole(out);
      expect(PptxParser(out).parse().sections[3].title, 'Press Day Briefing');
    });

    test('fills, outlines, dashes and shadows a shape, and fades a picture', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[3];
      final caption = deck.objects(slide).firstWhere((o) => o.name == 'Caption');
      final picture = deck.objects(slide).firstWhere((o) => o.isPicture);
      deck.setFill(slide, caption.id, 0xFF336699);
      deck.setLineColour(slide, caption.id, 0xFFCC0000);
      deck.setLineWeight(slide, caption.id, 3);
      deck.setLineDash(slide, caption.id, 'dash');
      deck.setShadowed(slide, caption.id, true);
      deck.setOpacity(slide, picture.id, 0.5);
      final again = _reopen(deck);
      final shape = again.shape(again.slides[3], caption.id)!;
      expect(shape.fill, 0xFF336699);
      expect(shape.line, 0xFFCC0000);
      expect(shape.lineWidth, 3);
      expect(shape.dash, 'dash');
      expect(shape.shadow, isTrue);
      expect(again.shape(again.slides[3], picture.id)!.opacity, closeTo(0.5, 0.001));
      final xml = _parts(deck.write())['ppt/slides/slide4.xml']!;
      // noFill made way for the new fill, and the order is the schema's.
      expect(xml, isNot(contains('<a:noFill/><a:solidFill>')));
      expect(xml.indexOf('<a:solidFill><a:srgbClr val="336699"/>'), lessThan(xml.indexOf('<a:ln ')));
    });

    test('adds a text box, a shape, a line and a picture', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[5];
      final box = deck.addTextBox(slide, const SlideBox(100, 100, 300, 40));
      final shape = deck.addShape(slide, 'ellipse', const SlideBox(400, 100, 120, 120));
      final line = deck.addLine(slide, (500, 400), (100, 300));
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      );
      final picture = deck.addPicture(slide, png, 'png', const SlideBox(10, 10, 50, 50));
      final out = deck.write();
      _expectWhole(out);
      final again = PptxDeck(out);
      final s = again.slides[5];
      expect(again.object(s, box)!.hasText, isTrue);
      expect(again.shape(s, shape)!.geometry, 'ellipse');
      final drawn = again.object(s, line)!;
      expect(drawn.isLine, isTrue);
      expect(drawn.flipH, isTrue);
      expect(drawn.flipV, isTrue);
      expect(drawn.box, const SlideBox(100, 300, 400, 100));
      expect(again.object(s, picture)!.isPicture, isTrue);
      expect(again.shape(s, picture)!.blocks.whereType<ImageBlock>().single.assetKey, startsWith('ppt/media/'));
    });

    test('moves a shape through the stack', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[3];
      final ids = deck.objects(slide).map((o) => o.id).toList();
      deck.order(slide, ids.last, SlideOrder.back);
      expect(deck.objects(slide).map((o) => o.id).first, ids.last);
      deck.order(slide, ids.last, SlideOrder.front);
      expect(deck.objects(slide).map((o) => o.id).toList(), ids);
    });

    test('a slide can be moved to another layout, and given its own ground', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[1];
      final title = deck.layouts.firstWhere((l) => l.type == 'title');
      deck.setLayout(slide, title.path);
      expect(deck.layoutOf(slide), title.path);
      deck.setBackground(slide, 0xFF223344);
      final again = _reopen(deck);
      expect(again.slide(again.slides[1]).background, 0xFF223344);
    });

    test('a theme gives every master its colours and faces', () {
      final deck = PptxDeck(bytes);
      final master = deck.masters.single;
      deck.applyTheme(
        name: 'Night',
        colours: const <String, int>{'dk1': 0x101010, 'lt1': 0xFAFAFA, 'accent1': 0x2266CC},
        headings: 'Arial',
        body: 'Arial',
        dark: true,
      );
      final again = _reopen(deck);
      expect(again.themeName(master), 'Night');
      expect(again.themeColours(master)['accent1'], 0x2266CC);
      // A dark theme sets its dark colour as the ground.
      expect(again.slide(again.slides[0]).background, 0xFF101010);
    });
  });

  group('slide text', () {
    SlideText read(PptxDeck deck, String slide, int id) =>
        SlideText.read(deck.textBody(slide, id), deck.looks(slide, id)!);

    test('reads each paragraph as a line with its level and list', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[1];
      final body = deck.objects(slide).firstWhere((o) => o.placeholder == 'body');
      final text = read(deck, slide, body.id);
      final lines = Delta.fromJson(text.ops).toList().where((op) => op.data == '\n').toList();
      expect(lines, hasLength(5));
      expect(lines[0].attributes, <String, dynamic>{'list': 'bullet'});
      expect(lines[2].attributes, <String, dynamic>{'indent': 1, 'list': 'bullet'});
    });

    test('an unchanged text body writes back paragraph for paragraph', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[1];
      final body = deck.objects(slide).firstWhere((o) => o.placeholder == 'body');
      final text = read(deck, slide, body.id);
      final written = text.write(deck.slideDoc(slide), text.ops);
      expect(written.toXmlString(), deck.textBody(slide, body.id)!.toXmlString());
    });

    test('typing keeps each run its own properties and changes only the words', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[3];
      final caption = deck.objects(slide).firstWhere((o) => o.name == 'Caption');
      final text = read(deck, slide, caption.id);
      final doc = Delta.fromJson(text.ops);
      final edited = doc.compose(Delta()..retain(7)..insert('late ', <String, dynamic>{'size': '18'}));
      deck.setText(slide, caption.id, text.write(deck.slideDoc(slide), edited.toJson()));
      final again = _reopen(deck);
      final shape = again.shape(again.slides[3], caption.id)!;
      expect(shape.text, startsWith('Pulled late at 09:40'));
      final xml = _parts(again.write())['ppt/slides/slide4.xml']!;
      expect(xml, contains('<a:rPr lang="en-GB" sz="1800"/><a:t>Pulled late at 09:40, before the reset.</a:t>'));
      // The second paragraph was not touched and is written as it was.
      expect(xml, contains('<a:p><a:pPr><a:buNone/></a:pPr><a:r><a:rPr lang="en-GB" sz="1800"></a:rPr><a:t>The gutter'));
    });

    test('bold on one word writes b on that run alone', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[3];
      final caption = deck.objects(slide).firstWhere((o) => o.name == 'Caption');
      final text = read(deck, slide, caption.id);
      final edited = Delta.fromJson(text.ops).compose(Delta()..retain(7)..retain(2, <String, dynamic>{'bold': true}));
      deck.setText(slide, caption.id, text.write(deck.slideDoc(slide), edited.toJson()));
      final xml = _parts(deck.write())['ppt/slides/slide4.xml']!;
      expect(xml, contains('<a:r><a:rPr lang="en-GB" sz="1800" b="1"/><a:t>at</a:t></a:r>'));
      expect(xml, contains('<a:t>Pulled </a:t>'));
    });

    test('a line break inside a paragraph stays one', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[3];
      final caption = deck.objects(slide).firstWhere((o) => o.name == 'Caption');
      final text = read(deck, slide, caption.id);
      final edited = Delta.fromJson(text.ops).compose(Delta()..retain(6)..insert(kSlideBreak, <String, dynamic>{'size': '18'}));
      deck.setText(slide, caption.id, text.write(deck.slideDoc(slide), edited.toJson()));
      final again = _reopen(deck);
      final looks = again.looks(again.slides[3], caption.id)!;
      expect(looks.paragraphs, hasLength(2));
      final xml = _parts(again.write())['ppt/slides/slide4.xml']!;
      expect(xml, contains('<a:t>Pulled</a:t></a:r><a:br><a:rPr lang="en-GB" sz="1800"/></a:br><a:r>'));
    });

    test('indenting a bullet moves it to the next level and drops its own margin', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[1];
      final body = deck.objects(slide).firstWhere((o) => o.placeholder == 'body');
      final text = read(deck, slide, body.id);
      final first = Delta.fromJson(text.ops).toList().first.data as String;
      final edited = Delta.fromJson(text.ops).compose(
        Delta()
          ..retain(first.length)
          ..retain(1, <String, dynamic>{'indent': 1}),
      );
      deck.setText(slide, body.id, text.write(deck.slideDoc(slide), edited.toJson()));
      final again = _reopen(deck);
      final items = again.shape(again.slides[1], body.id)!.blocks.whereType<ListItemBlock>().toList();
      expect(items.first.level, 1);
      expect(items.first.marker, '–');
      expect(items.first.spans.first.fontSize, 17);
    });
  });

  group('after the round one bar critic, the minors', () {
    test('a change that changes nothing is no step to undo', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[3];
      final top = deck.objects(slide).last;
      deck.order(slide, top.id, SlideOrder.front);
      expect(deck.steps, 0);
      final theme = kSlideThemes[2];
      void paper() => deck.applyTheme(name: theme.name, colours: theme.colours, headings: theme.headings, body: theme.body, dark: theme.dark);
      paper();
      expect(deck.steps, 1);
      paper();
      expect(deck.steps, 1);
      deck.setFill(slide, top.id, 0xFF112233);
      deck.setFill(slide, top.id, 0xFF112233);
      expect(deck.steps, 2);
    });

    test('a picture takes brightness and contrast', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[3];
      final picture = deck.objects(slide).firstWhere((o) => o.isPicture);
      deck.setPictureLight(slide, picture.id, brightness: 0.2, contrast: -0.2);
      expect(_parts(deck.write())['ppt/slides/slide4.xml'], contains('<a:lum bright="20000" contrast="-20000"/>'));
      _expectWhole(deck.write());
      final again = _reopen(deck);
      final shape = again.shape(again.slides[3], picture.id)!;
      expect(shape.brightness, closeTo(0.2, 1e-9));
      expect(shape.contrast, closeTo(-0.2, 1e-9));
    });

    testWidgets('a lightened picture is drawn lighter', (tester) async {
      final deck = PptxDeck((await tester.runAsync(() => documentBytes(kPressDayBriefing)))!);
      final slide = deck.slides[3];
      final picture = deck.objects(slide).firstWhere((o) => o.isPicture);
      await tester.pumpWidget(MaterialApp(home: SlideSheet(slide: deck.slide(slide), assets: deck.assets, width: 400)));
      expect(find.byType(ColorFiltered), findsNothing);
      deck.setPictureLight(slide, picture.id, brightness: 0.4, contrast: 0);
      await tester.pumpWidget(MaterialApp(home: SlideSheet(slide: deck.slide(slide), assets: deck.assets, width: 400)));
      final filter = tester.widget<ColorFiltered>(find.byType(ColorFiltered));
      expect(filter.colorFilter, const ColorFilter.matrix(<double>[1, 0, 0, 0, 102, 0, 1, 0, 0, 102, 0, 0, 1, 0, 102, 0, 0, 0, 1, 0]));
    });

    test('a table in PowerPoint\'s own style is drawn in it', () {
      final deck = PptxDeck(_styledTable(bytes));
      final table = deck.slide(deck.slides[5]).shapes.expand((s) => s.blocks).whereType<TableBlock>().single;
      final accent = deck.themeColours(deck.masters.single)['accent1']!;
      final head = table.rows.first.cells.first;
      expect(head.background! & 0xFFFFFF, accent & 0xFFFFFF);
      final span = head.blocks.whereType<ParagraphBlock>().first.spans.first;
      expect(span.bold, isTrue);
      expect(span.color! & 0xFFFFFF, deck.themeColours(deck.masters.single)['lt1']! & 0xFFFFFF);
      final one = table.rows[1].cells.first.background;
      final two = table.rows[2].cells.first.background;
      expect(one, isNotNull);
      expect(two, isNotNull);
      expect(one, isNot(two));
      final looks = deck.looks(deck.slides[5], 31, cell: (0, 0))!;
      expect(looks.levels.first.bold, isTrue);
    });

    testWidgets('list numbers stand on one line in a slide as small as the strip draws', (tester) async {
      final deck = PptxDeck((await tester.runAsync(() => documentBytes(kPressDayBriefing)))!);
      final slide = deck.slides[1];
      final body = deck.objects(slide).firstWhere((o) => o.placeholder == 'body');
      final text = SlideText.read(deck.textBody(slide, body.id), deck.looks(slide, body.id)!);
      final ops = <Map<String, dynamic>>[
        for (var i = 1; i <= 12; i++) ...<Map<String, dynamic>>[
          <String, dynamic>{'insert': 'Point $i'},
          <String, dynamic>{'insert': '\n', 'attributes': <String, dynamic>{'list': 'ordered'}},
        ],
      ];
      deck.setText(slide, body.id, text.write(deck.slideDoc(slide), ops));
      await tester.pumpWidget(MaterialApp(home: Center(child: SlideSheet(slide: deck.slide(slide), assets: deck.assets, width: 100))));
      final marker = find.text('12.', findRichText: true);
      expect(marker, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(marker);
      final boxes = paragraph.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 3));
      expect(boxes.map((b) => b.top.round()).toSet(), hasLength(1));
      // The number ends before its words begin.
      final words = find.text('Point 12', findRichText: true);
      expect(tester.getTopLeft(marker).dx + boxes.last.right, lessThanOrEqualTo(tester.getTopLeft(words).dx + 0.01));
    });
  });

  group('after the round one file critic', () {
    XmlElement shapeIn(Uint8List out, String slide, int id) => XmlDocument.parse(_parts(out)['ppt/slides/${slide.split('/').last}']!)
        .descendantElements
        .firstWhere((e) => e.name.local == 'sp' && e.descendantElements.any((c) => c.name.local == 'cNvPr' && c.getAttribute('id') == '$id'));

    test('a pasted title keeps the band, outline, anchor, capitals, spacing and face it took from its master', () {
      final deck = PptxDeck(_designed(bytes));
      final from = deck.slides[1];
      final title = deck.objects(from).firstWhere((o) => o.placeholder == 'title');
      final made = deck.paste(deck.slides[5], deck.copy(from, <int>{title.id})).single;
      final out = deck.write();
      writeEvidence('D/files', 'a_pasted_title_keeps_the_band_outline_anchor_cap.pptx', out);
      _expectWhole(out);
      final sp = shapeIn(out, deck.slides[5], made).toXmlString();
      expect(sp, isNot(contains('<p:ph')));
      expect(sp, contains('<a:prstGeom prst="roundRect">'));
      expect(sp, contains('<a:lumOff val="80000"/>'));
      expect(sp, contains('<a:ln w="38100">'));
      expect(sp, contains('anchor="b"'));
      final level = RegExp(r'<a:lvl1pPr[^>]*>.*?</a:lvl1pPr>').firstMatch(sp)!.group(0)!;
      expect(level, contains('cap="all"'));
      expect(level, contains('spc="300"'));
      expect(level, contains('<a:latin typeface="+mj-lt"/>'));
      expect(level, contains('<a:buNone/>'));
    });

    test('pasted bullets keep their face, colour and size', () {
      final deck = PptxDeck(_designed(bytes));
      final from = deck.slides[1];
      final body = deck.objects(from).firstWhere((o) => o.placeholder == 'body');
      final made = deck.paste(deck.slides[5], deck.copy(from, <int>{body.id})).single;
      final sp = shapeIn(deck.write(), deck.slides[5], made).toXmlString();
      final first = RegExp(r'<a:lvl1pPr[^>]*>.*?</a:lvl1pPr>').firstMatch(sp)!.group(0)!;
      expect(first, contains('<a:buClr><a:srgbClr val="FF0000"/></a:buClr><a:buSzPct val="80000"/><a:buFont typeface="Wingdings"/><a:buChar char="\u00A7"/>'));
      final second = RegExp(r'<a:lvl2pPr[^>]*>.*?</a:lvl2pPr>').firstMatch(sp)!.group(0)!;
      expect(second, contains('<a:buChar char="\u2013"/>'));
      expect(second, contains('sz="1700"'));
    });

    test('a layout change keeps what has no place on the new layout where and as it was', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[1];
      final body = deck.objects(slide).firstWhere((o) => o.placeholder == 'body');
      final was = deck.shape(slide, body.id)!;
      final statement = deck.layouts.firstWhere((l) => l.name == 'Statement');
      deck.setLayout(slide, statement.path);
      final out = deck.write();
      writeEvidence('D/files', 'a_layout_change_keeps_what_has_no_place_on_the_n.pptx', out);
      _expectWhole(out);
      final again = PptxDeck(out);
      final kept = again.object(again.slides[1], body.id)!;
      expect(kept.placeholder, isNull);
      expect(kept.box, was.box);
      final items = again.shape(again.slides[1], body.id)!.blocks.whereType<ListItemBlock>().toList();
      expect(items, hasLength(was.blocks.whereType<ListItemBlock>().length));
      expect(items.first.marker, '\u2022');
      expect(items[2].level, 1);
      expect(items.first.spans.first.fontSize, was.blocks.whereType<ListItemBlock>().first.spans.first.fontSize);
      expect(again.objects(again.slides[1]).firstWhere((o) => o.placeholder == 'title').id, 2);
    });

    test('a layout change drops an empty placeholder with no place, and a picture keeps its place', () {
      final deck = PptxDeck(_pictureHolder(bytes));
      final slide = deck.slides[3];
      expect(deck.object(slide, 4), isNotNull);
      final made = deck.addSlide(deck.layouts.firstWhere((l) => l.type == 'obj').path, 6);
      final statement = deck.layouts.firstWhere((l) => l.name == 'Statement');
      deck.setLayout(made, statement.path);
      final objects = deck.objects(made);
      expect(objects.map((o) => o.placeholder), <String?>['title']);
      deck.setLayout(slide, statement.path);
      final again = _reopen(deck);
      final picture = again.object(again.slides[3], 4);
      expect(picture, isNotNull);
      expect(picture!.isPicture, isTrue);
    });

    test('a line glued to a shape comes along when the shape moves, and lets go when moved itself', () {
      final deck = PptxDeck(_glued(bytes));
      final slide = deck.slides[5];
      final second = deck.object(slide, 21)!;
      deck.place(slide, 21, SlideBox(second.box.left + 100, second.box.top - 50, second.box.width, second.box.height));
      var line = deck.object(slide, 22)!;
      expect(line.box.left, closeTo(200, 0.01));
      expect(line.box.width, closeTo(300, 0.01));
      expect(line.box.height, closeTo(50, 0.01));
      expect(line.flipV, isTrue);
      final first = deck.object(slide, 20)!;
      deck.place(slide, 20, SlideBox(first.box.left, first.box.top, first.box.width * 2, first.box.height));
      line = deck.object(slide, 22)!;
      expect(line.box.left, closeTo(300, 0.01));
      var xml = _parts(deck.write())['ppt/slides/slide6.xml']!;
      expect(xml, contains('<a:stCxn id="20" idx="3"/>'));
      writeEvidence('D/files', 'glued_follow.pptx', deck.write());
      deck.place(slide, 22, SlideBox(line.box.left, line.box.top + 20, line.box.width, line.box.height));
      xml = _parts(deck.write())['ppt/slides/slide6.xml']!;
      expect(xml, isNot(contains('stCxn')));
      expect(xml, isNot(contains('endCxn')));
    });

    test('a line glued to a deleted shape lets go of it', () {
      final deck = PptxDeck(_glued(bytes));
      deck.delete(deck.slides[5], <int>{20});
      final xml = _parts(deck.write())['ppt/slides/slide6.xml']!;
      expect(xml, isNot(contains('stCxn')));
      expect(xml, contains('<a:endCxn id="21" idx="1"/>'));
    });

    test('a deleted shape takes its animation with it', () {
      final deck = PptxDeck(_animated(bytes));
      final slide = deck.slides[3];
      deck.delete(slide, <int>{5});
      writeEvidence('D/files', 'animation_delete.pptx', deck.write());
      var xml = _parts(deck.write())['ppt/slides/slide4.xml']!;
      expect(xml, isNot(contains('spid="5"')));
      expect(xml, contains('<p:spTgt spid="4"/>'));
      expect(xml, isNot(contains('bldLst')));
      expect(RegExp('presetClass').allMatches(xml), hasLength(1));
      deck.delete(slide, <int>{4});
      xml = _parts(deck.write())['ppt/slides/slide4.xml']!;
      expect(xml, isNot(contains('p:timing')));
    });

    test('a group\'s border, fill and shadow go on the shapes in it', () {
      final deck = PptxDeck(_grouped(bytes));
      final slide = deck.slides[3];
      deck.setLineColour(slide, 9, 0xFFCC0000);
      deck.setLineWeight(slide, 9, 3);
      deck.setLineDash(slide, 9, 'dash');
      deck.setFill(slide, 9, 0xFF2266CC);
      deck.setShadowed(slide, 9, true);
      writeEvidence('D/files', 'group_format.pptx', deck.write());
      final xml = XmlDocument.parse(_parts(deck.write())['ppt/slides/slide4.xml']!);
      final group = xml.descendantElements.firstWhere((e) => e.name.local == 'grpSp');
      final own = group.childElements.firstWhere((e) => e.name.local == 'grpSpPr');
      expect(own.childElements.map((e) => e.name.local), <String>['xfrm']);
      final shapes = group.childElements.where((e) => e.name.local == 'sp').toList();
      expect(shapes, hasLength(2));
      for (final sp in shapes) {
        final properties = sp.childElements.firstWhere((e) => e.name.local == 'spPr').toXmlString();
        expect(properties, contains('<a:ln w="38100"><a:solidFill><a:srgbClr val="CC0000"/></a:solidFill><a:prstDash val="dash"/></a:ln>'));
        expect(properties, contains('<a:srgbClr val="2266CC"/>'));
        expect(properties, contains('outerShdw'));
      }
    });

    test('a chart takes no fill or border and makes no step', () {
      final deck = PptxDeck(_charted(bytes));
      final slide = deck.slides[5];
      deck.setFill(slide, 30, 0xFF2266CC);
      deck.setLineColour(slide, 30, 0xFFCC0000);
      expect(deck.steps, 0);
    });

    test('a pasted SmartArt brings the drawing it is laid out as', () {
      final deck = PptxDeck(_smartArt(bytes));
      final to = deck.slides[1];
      deck.paste(to, deck.copy(deck.slides[5], <int>{50}));
      final out = deck.write();
      writeEvidence('D/files', 'a_pasted_smartart_brings_the_drawing_it_is_laid_.pptx', out);
      _expectWhole(out);
      final parts = _parts(out);
      final rels = XmlDocument.parse(parts['ppt/slides/_rels/slide2.xml.rels']!).rootElement.childElements.toList();
      String targetOf(String kind) => rels.firstWhere((r) => r.getAttribute('Type')!.endsWith('/$kind')).getAttribute('Target')!;
      final data = 'ppt/diagrams/${targetOf('diagramData').split('/').last}';
      expect(data, isNot('ppt/diagrams/data1.xml'));
      final relId = RegExp(r'relId="([^"]+)"').firstMatch(parts[data]!)!.group(1);
      final drawing = rels.firstWhere((r) => r.getAttribute('Id') == relId);
      expect(drawing.getAttribute('Type'), endsWith('/diagramDrawing'));
      final drawn = 'ppt/diagrams/${drawing.getAttribute('Target')!.split('/').last}';
      expect(drawn, isNot('ppt/diagrams/drawing1.xml'));
      expect(parts[drawn], contains('dsp:drawing'));
    });

    /// The slide parts [part]'s relationships link to.
    Set<String> slideLinks(Uint8List out, String part) {
      final name = part.split('/').last;
      final rels = _parts(out)['ppt/slides/_rels/$name.rels']!;
      return <String>{
        for (final rel in XmlDocument.parse(rels).rootElement.childElements)
          if (rel.getAttribute('Type')!.endsWith('/slide')) 'ppt/slides/${rel.getAttribute('Target')!.split('/').last}',
      };
    }

    test('slides cut and pasted together link to each other still', () {
      final deck = PptxDeck(_backLinked(_linked(bytes)));
      final two = deck.slides[1], six = deck.slides[5];
      final clip = deck.copySlides(<String>[two, six]);
      deck.deleteSlides(<String>{two, six}, label: 'Cut');
      final made = deck.pasteSlides(clip, 0);
      final out = deck.write();
      writeEvidence('D/files', 'slides_cut_and_pasted_together_link_to_each_othe.pptx', out);
      _expectWhole(out);
      expect(slideLinks(out, made[0]), <String>{made[1]});
      expect(slideLinks(out, made[1]), <String>{made[0]});
      final again = PptxDeck(out);
      expect(again.slides.take(2), made);
    });

    test('a shape pasted after the slide it jumps to is gone loses the jump', () {
      final deck = PptxDeck(_backLinked(bytes));
      final six = deck.slides[5];
      final clip = deck.copy(six, <int>{40});
      deck.delete(six, <int>{40});
      deck.deleteSlides(<String>{deck.slides[1]});
      final made = deck.paste(deck.slides[2], clip).single;
      final out = deck.write();
      writeEvidence('D/files', 'a_shape_pasted_after_the_slide_it_jumps_to_is_go.pptx', out);
      _expectWhole(out);
      final pasted = PptxDeck(out);
      final slide = pasted.slides[2];
      expect(pasted.object(slide, made), isNotNull);
      expect(_parts(out)['ppt/slides/${slide.split('/').last}'], isNot(contains('hlinkClick')));
      expect(slideLinks(out, slide), isEmpty);
    });

    test('a slide pasted after the slide it links to is gone loses the link', () {
      final deck = PptxDeck(_backLinked(bytes));
      final clip = deck.copySlides(<String>[deck.slides[5]]);
      deck.deleteSlides(<String>{deck.slides[5], deck.slides[1]}, label: 'Cut');
      final made = deck.pasteSlides(clip, 0).single;
      final out = deck.write();
      writeEvidence('D/files', 'a_slide_pasted_after_the_slide_it_links_to_is_go.pptx', out);
      _expectWhole(out);
      expect(slideLinks(out, made), isEmpty);
      expect(_parts(out)['ppt/slides/${made.split('/').last}'], isNot(contains('hlinkClick')));
    });


    /// Edits slide 2's body of [deck] through the editor's own controller
    /// and saves the typing; returns the slide's written XML.
    String typeInBody(PptxDeck deck, void Function(QuillController c) edit) {
      final slide = deck.slides[1];
      final text = SlideText.read(deck.textBody(slide, 3), deck.looks(slide, 3)!);
      final c = QuillController(document: Document.fromJson(text.ops), selection: const TextSelection.collapsed(offset: 0));
      edit(c);
      deck.setText(slide, 3, text.write(deck.slideDoc(slide), c.document.toDelta().toJson()));
      final out = deck.write();
      writeEvidence('D/files', 'a_slide_pasted_after_the_slide_it_links_to_is_go_2.pptx', out);
      _expectWhole(out);
      return _parts(out)['ppt/slides/slide2.xml']!;
    }

    List<XmlElement> paragraphs(String xml) {
      final doc = XmlDocument.parse(xml);
      final body = doc.rootElement.descendantElements.where((e) => e.name.local == 'sp').elementAt(1);
      return body.descendantElements.where((e) => e.name.local == 'p').toList();
    }

    String textOf(XmlElement p) => p.descendantElements.where((e) => e.name.local == 't').map((e) => e.innerText).join();

    XmlElement runWith(XmlElement p, String words) =>
        p.childElements.firstWhere((r) => r.name.local == 'r' && textOf(r).contains(words));

    int at(QuillController c, String words) => c.document.toPlainText().indexOf(words);

    test('a paragraph split before a link keeps that link on its words', () {
      final xml = typeInBody(PptxDeck(_linked(bytes)), (c) => c.replaceText(at(c, 'jump to'), 0, '\n', null));
      final ps = paragraphs(xml);
      expect(ps.map(textOf), <String>['Forme three', '\u65E5\u672C\u8A9E\u306E\u30C6\u30AD\u30B9\u30C8\u3067\u3059', 'Visit the site or ', 'jump to wrap up', 'Second level in Georgia']);
      expect(runWith(ps[3], 'jump').toXmlString(), contains('r:id="rId3"'));
      expect(runWith(ps[2], 'Visit').toXmlString(), contains('r:id="rId2"'));
      expect(runWith(ps[2], ' or ').toXmlString(), isNot(contains('hlinkClick')));
    });

    test('a line typed after a link is plain', () {
      final xml = typeInBody(PptxDeck(_linked(bytes)), (c) {
        final end = at(c, 'wrap up') + 'wrap up'.length;
        c.replaceText(end, 0, '\n', null);
        c.replaceText(end + 1, 0, 'A plain new point', null);
      });
      final ps = paragraphs(xml);
      expect(textOf(ps[3]), 'A plain new point');
      expect(ps[3].toXmlString(), isNot(contains('hlinkClick')));
      expect(runWith(ps[2], 'jump').toXmlString(), contains('r:id="rId3"'));
    });

    test('joined paragraphs keep each word its own face, language and link', () {
      final deck = PptxDeck(_linked(bytes));
      var xml = typeInBody(deck, (c) => c.replaceText(at(c, 'Visit') - 1, 1, '', null));
      var ps = paragraphs(xml);
      expect(ps, hasLength(3));
      final japanese = runWith(ps[1], '\u65E5\u672C').toXmlString();
      expect(japanese, contains('lang="ja-JP"'));
      expect(japanese, contains('<a:ea typeface="MS Mincho"/>'));
      expect(japanese, isNot(contains('hlinkClick')));
      expect(runWith(ps[1], 'Visit').toXmlString(), contains('r:id="rId2"'));
      xml = typeInBody(deck, (c) => c.replaceText(at(c, 'Second level') - 1, 1, '', null));
      ps = paragraphs(xml);
      final georgia = runWith(ps.last, 'Second level').toXmlString();
      expect(georgia, contains('<a:latin typeface="Georgia"/>'));
      expect(georgia, isNot(contains('hlinkClick')));
      expect(runWith(ps.last, 'jump').toXmlString(), contains('r:id="rId3"'));
    });

    test('a pasted control character is a line break or nothing, never a bad character', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[0];
      final title = deck.objects(slide).firstWhere((o) => o.placeholder == 'ctrTitle' || o.placeholder == 'title');
      final text = SlideText.read(deck.textBody(slide, title.id), deck.looks(slide, title.id)!);
      final c = QuillController(document: Document.fromJson(text.ops), selection: const TextSelection.collapsed(offset: 0));
      final controls = String.fromCharCodes(<int>[for (var u = 0; u < 0x20; u++) if (u != 0x09 && u != 0x0A && u != 0x0D && u != 0x0B) u]);
      c.replaceText(0, 0, 'Line one\u000Bline two$controls ', null);
      deck.setText(slide, title.id, text.write(deck.slideDoc(slide), c.document.toDelta().toJson()));
      final xml = _parts(deck.write())['ppt/slides/slide1.xml']!;
      expect(RegExp(r'&#x?[0-9A-Fa-f]+;').hasMatch(xml), isFalse);
      expect(xml.runes.where((u) => u < 0x20 && u != 0x09 && u != 0x0A && u != 0x0D), isEmpty);
      expect(xml, contains('<a:t>Line one</a:t></a:r><a:br>'));
      expect(xml, contains('<a:t>line two '));
    });
    test('a deleted slide takes the parts only it pointed at', () {
      final deck = PptxDeck(bytes);
      deck.deleteSlides(<String>{deck.slides[3]});
      final out = deck.write();
      writeEvidence('D/files', 'a_deleted_slide_takes_the_parts_only_it_pointed_.pptx', out);
      _expectWhole(out);
      expect(_names(out), isNot(contains('ppt/media/image1.png')));
      final charted = PptxDeck(_charted(bytes));
      final clip = charted.copySlides(<String>[charted.slides[5]]);
      charted.deleteSlides(<String>{charted.slides[5]}, label: 'Cut');
      charted.pasteSlides(clip, 0);
      final pasted = charted.write();
      writeEvidence('D/files', 'a_deleted_slide_takes_the_parts_only_it_pointed__2.pptx', pasted);
      _expectWhole(pasted);
      expect(_names(pasted).where((n) => n.startsWith('ppt/charts/')), hasLength(1));
      expect(_parts(pasted)['[Content_Types].xml'], isNot(contains('/ppt/charts/chart1.xml')));
    });
  });

  group('after the round two critic', () {
    test('a content placeholder sharing an index with the master\'s footer takes the body\'s look', () {
      final deck = PptxDeck(_footed(bytes));
      final slide = deck.slides[1];
      final looks = deck.looks(slide, 9)!.levels.first;
      final body = deck.looks(slide, 3)!.levels.first;
      expect(looks.align, DocAlign.start);
      expect(looks.colour, body.colour);
      expect(looks.size, body.size);
      final shape = deck.shape(slide, 9)!;
      expect(shape.verticalAlign, isNot(DocVerticalAlign.center));
    });

    test('a title and a bullet are drawn in the alignment the deck and the typing give them', () {
      final deck = PptxDeck(bytes);
      final statement = deck.slide(deck.slides[5]).shapes.expand((s) => s.blocks).whereType<HeadingBlock>().single;
      expect(statement.align, DocAlign.center);
      final slide = deck.slides[1];
      final text = SlideText.read(deck.textBody(slide, 2), deck.looks(slide, 2)!);
      final ops = Delta.fromJson(text.ops).compose(Delta()..retain(text.ops.first['insert'].length as int)..retain(1, <String, dynamic>{'align': 'center'}));
      deck.setText(slide, 2, text.write(deck.slideDoc(slide), ops.toJson()));
      final body = deck.objects(slide).firstWhere((o) => o.placeholder == 'body');
      final bullets = SlideText.read(deck.textBody(slide, body.id), deck.looks(slide, body.id)!);
      final first = (bullets.ops.first['insert'] as String).length;
      final centred = Delta.fromJson(bullets.ops).compose(Delta()..retain(first)..retain(1, <String, dynamic>{'align': 'center'}));
      deck.setText(slide, body.id, bullets.write(deck.slideDoc(slide), centred.toJson()));
      final again = _reopen(deck);
      final blocks = again.slide(again.slides[1]).shapes.expand((s) => s.blocks).toList();
      expect(blocks.whereType<HeadingBlock>().single.align, DocAlign.center);
      expect(blocks.whereType<ListItemBlock>().first.align, DocAlign.center);
    });

    testWidgets('a centred title is drawn centred', (tester) async {
      final deck = PptxDeck((await tester.runAsync(() => documentBytes(kPressDayBriefing)))!);
      await tester.pumpWidget(MaterialApp(home: SlideSheet(slide: deck.slide(deck.slides[5]), assets: deck.assets, width: 400)));
      final title = find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('Sheets off by four'));
      expect(tester.widget<RichText>(title).textAlign, TextAlign.center);
    });
  });

  group('after the round two critic, pictures', () {
    testWidgets('a picture is stretched over its frame, as a widened one is saved', (tester) async {
      final deck = PptxDeck((await tester.runAsync(() => documentBytes(kPressDayBriefing)))!);
      final slide = deck.slides[3];
      final picture = deck.objects(slide).firstWhere((o) => o.isPicture);
      deck.place(slide, picture.id, SlideBox(picture.box.left, picture.box.top, picture.box.width * 1.6, picture.box.height));
      final image = deck.slide(slide).shapes.expand((s) => s.blocks).whereType<ImageBlock>().single;
      expect(image.stretch, isTrue);
      await tester.pumpWidget(MaterialApp(home: SlideSheet(slide: deck.slide(slide), assets: deck.assets, width: 400)));
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.fill);
    });

    testWidgets('a cropped picture shows only what the crop keeps, over the whole frame', (tester) async {
      final deck = PptxDeck(_cropped((await tester.runAsync(() => documentBytes(kPressDayBriefing)))!));
      final slide = deck.slides[3];
      final image = deck.slide(slide).shapes.expand((s) => s.blocks).whereType<ImageBlock>().single;
      expect(image.crop, (0.25, 0.0, 0.25, 0.0));
      await tester.pumpWidget(MaterialApp(home: SlideSheet(slide: deck.slide(slide), assets: deck.assets, width: 400)));
      final frame = tester.getSize(find.ancestor(of: find.byType(Image), matching: find.byType(ClipRect)).first);
      final drawn = tester.getSize(find.byType(Image));
      expect(drawn.width, closeTo(frame.width * 2, 0.5));
      expect(drawn.height, closeTo(frame.height, 0.5));
      expect(tester.getTopLeft(find.byType(Image)).dx, closeTo(tester.getTopLeft(find.ancestor(of: find.byType(Image), matching: find.byType(ClipRect)).first).dx - frame.width / 2, 0.5));
    });
  });

  group('after the round two critic, tables', () {
    test('sizing a table by its handles sizes its columns and rows with it', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[2];
      final table = deck.objects(slide).firstWhere((o) => o.kind == 'graphicFrame');
      final to = SlideBox(table.box.left, table.box.top, table.box.width * 0.6, table.box.height * 2);
      deck.place(slide, table.id, to);
      final (columns, rows) = deck.tableGrid(slide, table.id)!;
      expect(columns.reduce((a, b) => a + b), closeTo(to.width, 0.05));
      expect(rows.reduce((a, b) => a + b), closeTo(to.height, 0.05));
      final again = _reopen(deck);
      final (againColumns, _) = again.tableGrid(again.slides[2], table.id)!;
      expect(againColumns.first, closeTo(columns.first, 0.01));
    });
  });

  group('after the round two critic, boxes on one line', () {
    testWidgets('a box that runs its words on one line is drawn that way', (tester) async {
      final deck = PptxDeck(_unwrapped((await tester.runAsync(() => documentBytes(kPressDayBriefing)))!));
      final slide = deck.slides[3];
      final caption = deck.objects(slide).firstWhere((o) => o.name == 'Caption');
      expect(deck.shape(slide, caption.id)!.wrap, isFalse);
      await tester.pumpWidget(MaterialApp(home: SlideSheet(slide: deck.slide(slide), assets: deck.assets, width: 400)));
      final words = find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().startsWith('The gutter'));
      expect(tester.widget<RichText>(words).softWrap, isFalse);
    });

    test('words typed into such a box are saved wrapping as the editor showed them', () {
      final deck = PptxDeck(_unwrapped(bytes));
      final slide = deck.slides[3];
      final caption = deck.objects(slide).firstWhere((o) => o.name == 'Caption');
      final text = SlideText.read(deck.textBody(slide, caption.id), deck.looks(slide, caption.id)!);
      final typed = Delta.fromJson(text.ops).compose(Delta()..insert('Note: '));
      deck.setText(slide, caption.id, text.write(deck.slideDoc(slide), typed.toJson()));
      expect(deck.shape(slide, caption.id)!.wrap, isTrue);
      final untouched = PptxDeck(_unwrapped(bytes));
      untouched.setText(slide, caption.id, SlideText.read(untouched.textBody(slide, caption.id), untouched.looks(slide, caption.id)!).write(untouched.slideDoc(slide), text.ops));
      expect(untouched.shape(slide, caption.id)!.wrap, isFalse);
    });
  });

  group('after the round two critic, shrunk words', () {
    test('words PowerPoint shrank to fit their box are drawn and typed shrunk, and written as the file states them', () {
      final plain = PptxDeck(bytes);
      final deck = PptxDeck(_shrunk(bytes));
      final slide = deck.slides[1];
      final body = deck.objects(slide).firstWhere((o) => o.placeholder == 'body');
      double first(PptxDeck d) => d.shape(d.slides[1], body.id)!.blocks.whereType<ListItemBlock>().first.spans.first.fontSize!;
      expect(first(deck), closeTo(first(plain) * 0.55, 0.01));
      final looks = deck.looks(slide, body.id)!;
      expect(looks.scale, closeTo(0.55, 1e-9));
      expect(looks.levels.first.size, closeTo(plain.looks(slide, body.id)!.levels.first.size * 0.55, 0.01));
      final text = SlideText.read(deck.textBody(slide, body.id), looks);
      final words = (text.ops.first['insert'] as String).length;
      final bigger = Delta.fromJson(text.ops).compose(Delta()..retain(words, <String, dynamic>{'size': '22'}));
      deck.setText(slide, body.id, text.write(deck.slideDoc(slide), bigger.toJson()));
      expect(_parts(deck.write())['ppt/slides/slide2.xml'], contains('sz="4000"'));
    });
  });

  group('after the round two critic, gradients', () {
    test('a gradient ground and a gradient fill are read', () {
      final deck = PptxDeck(_graded(bytes));
      final ground = deck.slide(deck.slides[1]).backgroundGradient!;
      expect(ground.stops, <(double, int)>[(0.0, 0xFF1F3864), (1.0, 0xFF000000)]);
      expect(ground.angle, closeTo(90, 1e-9));
      final caption = deck.objects(deck.slides[3]).firstWhere((o) => o.name == 'Caption');
      expect(deck.shape(deck.slides[3], caption.id)!.gradient!.stops.last.$2, 0xFFFFC000);
    });

    testWidgets('a gradient ground is drawn', (tester) async {
      final deck = PptxDeck(_graded((await tester.runAsync(() => documentBytes(kPressDayBriefing)))!));
      await tester.pumpWidget(MaterialApp(home: SlideSheet(slide: deck.slide(deck.slides[1]), assets: deck.assets, width: 400)));
      final grounds = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).where((b) => (b.decoration as BoxDecoration?)?.gradient != null);
      expect(grounds, isNotEmpty);
      final gradient = (grounds.first.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(gradient.colors.first, const Color(0xFF1F3864));
      expect((gradient.begin as Alignment).y, closeTo(-1, 1e-9));
    });
  });

  group('after the round two critic, links', () {
    test('a link is drawn in the theme\'s link colour, underlined', () {
      final deck = PptxDeck(_linked(bytes));
      final spans = deck.shape(deck.slides[1], 3)!.blocks.expand((b) => switch (b) {
            ListItemBlock() => b.spans,
            ParagraphBlock() => b.spans,
            _ => const <DocSpan>[],
          });
      final link = spans.firstWhere((s) => s.text == 'Visit the site');
      final plain = spans.firstWhere((s) => s.text == ' or ');
      expect(link.underline, isTrue);
      expect(link.color, deck.themeColours(deck.masters.single)['hlink']! | 0xFF000000);
      expect(plain.underline, isFalse);
    });
  });
}
