/// A theme quire can give a deck: its twelve colours, its two faces, and
/// whether its slides are dark with light words.
class SlideTheme {
  const SlideTheme({
    required this.name,
    required this.colours,
    required this.headings,
    required this.body,
    this.dark = false,
  });

  final String name;

  /// dk1, lt1, dk2, lt2, accent1 to accent6, hlink and folHlink, as
  /// 0xRRGGBB.
  final Map<String, int> colours;
  final String headings;
  final String body;
  final bool dark;

  /// The ground a slide in this theme has.
  int get ground => dark ? colours['dk1']! : colours['lt1']!;

  /// The words on that ground.
  int get ink => dark ? colours['lt1']! : colours['dk1']!;

  List<int> get accents => <int>[
    for (var i = 1; i <= 6; i++) colours['accent$i']!,
  ];
}

/// The themes quire offers, in the faces every copy of PowerPoint and
/// LibreOffice has.
const List<SlideTheme> kSlideThemes = <SlideTheme>[
  SlideTheme(
    name: 'Simple light',
    headings: 'Arial',
    body: 'Arial',
    colours: <String, int>{
      'dk1': 0x000000,
      'lt1': 0xFFFFFF,
      'dk2': 0x595959,
      'lt2': 0xEEEEEE,
      'accent1': 0x4285F4,
      'accent2': 0x212121,
      'accent3': 0x78909C,
      'accent4': 0xFFAB40,
      'accent5': 0x0097A7,
      'accent6': 0xEEFF41,
      'hlink': 0x0097A7,
      'folHlink': 0x0097A7,
    },
  ),
  SlideTheme(
    name: 'Simple dark',
    headings: 'Arial',
    body: 'Arial',
    dark: true,
    colours: <String, int>{
      'dk1': 0x212121,
      'lt1': 0xFFFFFF,
      'dk2': 0x424242,
      'lt2': 0xBDBDBD,
      'accent1': 0x8AB4F8,
      'accent2': 0xF28B82,
      'accent3': 0xFDD663,
      'accent4': 0x81C995,
      'accent5': 0xC58AF9,
      'accent6': 0x78D9EC,
      'hlink': 0x8AB4F8,
      'folHlink': 0xC58AF9,
    },
  ),
  SlideTheme(
    name: 'Paper',
    headings: 'Georgia',
    body: 'Georgia',
    colours: <String, int>{
      'dk1': 0x2B2B2B,
      'lt1': 0xFBF8F1,
      'dk2': 0x4A4238,
      'lt2': 0xEFE8DA,
      'accent1': 0x9C4A2F,
      'accent2': 0x2F5D50,
      'accent3': 0xB88A44,
      'accent4': 0x5B6770,
      'accent5': 0x7A3E65,
      'accent6': 0x3F6E8C,
      'hlink': 0x2F5D50,
      'folHlink': 0x7A3E65,
    },
  ),
  SlideTheme(
    name: 'Coral',
    headings: 'Trebuchet MS',
    body: 'Trebuchet MS',
    colours: <String, int>{
      'dk1': 0x1F2933,
      'lt1': 0xFFFFFF,
      'dk2': 0x3E4C59,
      'lt2': 0xFFF1EC,
      'accent1': 0xF26B5B,
      'accent2': 0xFFB84D,
      'accent3': 0x2BB3A3,
      'accent4': 0x5D6D7E,
      'accent5': 0xA35EAB,
      'accent6': 0x3A7BD5,
      'hlink': 0x3A7BD5,
      'folHlink': 0xA35EAB,
    },
  ),
  SlideTheme(
    name: 'Forest',
    headings: 'Verdana',
    body: 'Verdana',
    dark: true,
    colours: <String, int>{
      'dk1': 0x1B2A22,
      'lt1': 0xF4F1E8,
      'dk2': 0x2E4234,
      'lt2': 0xC9D6C3,
      'accent1': 0x8BC34A,
      'accent2': 0xE0B84E,
      'accent3': 0x5FB3A1,
      'accent4': 0xD9825B,
      'accent5': 0xA7C4A0,
      'accent6': 0x7FA7D4,
      'hlink': 0xE0B84E,
      'folHlink': 0xA7C4A0,
    },
  ),
  SlideTheme(
    name: 'Ocean',
    headings: 'Calibri',
    body: 'Calibri',
    colours: <String, int>{
      'dk1': 0x0B2545,
      'lt1': 0xFFFFFF,
      'dk2': 0x13315C,
      'lt2': 0xE8F1F8,
      'accent1': 0x1B6CA8,
      'accent2': 0x27A4C3,
      'accent3': 0xF2A541,
      'accent4': 0x8DA9C4,
      'accent5': 0x5C4D7D,
      'accent6': 0x2E8B57,
      'hlink': 0x1B6CA8,
      'folHlink': 0x5C4D7D,
    },
  ),
  SlideTheme(
    name: 'Slate',
    headings: 'Arial',
    body: 'Arial',
    dark: true,
    colours: <String, int>{
      'dk1': 0x263238,
      'lt1': 0xECEFF1,
      'dk2': 0x37474F,
      'lt2': 0xB0BEC5,
      'accent1': 0xFFB74D,
      'accent2': 0x4DD0E1,
      'accent3': 0xE57373,
      'accent4': 0xAED581,
      'accent5': 0x9575CD,
      'accent6': 0xF06292,
      'hlink': 0x4DD0E1,
      'folHlink': 0x9575CD,
    },
  ),
];
