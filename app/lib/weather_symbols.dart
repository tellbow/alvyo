import 'package:flutter/material.dart';

import 'poi_icons.dart';

/// Our weather icons: layers of colour and shape (24 × 24), as on the
/// website (`web/src/lib/weather/symbols.json`, compared in a test).
const weatherIcons = <String, List<({int color, String path})>>{
  'sun': [
    (
      color: 0xFFf59e0b,
      path:
          'M7.2 12C7.2 9.35 9.35 7.2 12 7.2C14.65 7.2 16.8 9.35 16.8 12C16.8 14.65 14.65 16.8 12 16.8C9.35 16.8 7.2 14.65 7.2 12ZM18 12.75L21 12.75L21 11.25L18 11.25ZM15.71 16.77L17.83 18.89L18.89 17.83L16.77 15.71ZM11.25 18L11.25 21L12.75 21L12.75 18ZM7.23 15.71L5.11 17.83L6.17 18.89L8.29 16.77ZM6 11.25L3 11.25L3 12.75L6 12.75ZM8.29 7.23L6.17 5.11L5.11 6.17L7.23 8.29ZM12.75 6L12.75 3L11.25 3L11.25 6ZM16.77 8.29L18.89 6.17L17.83 5.11L15.71 7.23Z',
    ),
  ],
  'few_clouds': [
    (
      color: 0xFFf59e0b,
      path:
          'M5.8 10C5.8 7.68 7.68 5.8 10 5.8C12.32 5.8 14.2 7.68 14.2 10C14.2 12.32 12.32 14.2 10 14.2C7.68 14.2 5.8 12.32 5.8 10ZM15.4 10.75L18 10.75L18 9.25L15.4 9.25ZM13.29 14.35L15.13 16.19L16.19 15.13L14.35 13.29ZM9.25 15.4L9.25 18L10.75 18L10.75 15.4ZM5.65 13.29L3.81 15.13L4.87 16.19L6.71 14.35ZM4.6 9.25L2 9.25L2 10.75L4.6 10.75ZM6.71 5.65L4.87 3.81L3.81 4.87L5.65 6.71ZM10.75 4.6L10.75 2L9.25 2L9.25 4.6ZM14.35 6.71L16.19 4.87L15.13 3.81L13.29 5.65Z',
    ),
    (
      color: 0xFF94a3b8,
      path:
          'M7.08 16.28C7.08 14.69 8.37 13.4 9.96 13.4C11.55 13.4 12.84 14.69 12.84 16.28C12.84 17.87 11.55 19.16 9.96 19.16C8.37 19.16 7.08 17.87 7.08 16.28ZM9.96 13.76C9.96 11.77 11.57 10.16 13.56 10.16C15.55 10.16 17.16 11.77 17.16 13.76C17.16 15.75 15.55 17.36 13.56 17.36C11.57 17.36 9.96 15.75 9.96 13.76ZM14.06 16.28C14.06 14.77 15.29 13.54 16.8 13.54C18.31 13.54 19.54 14.77 19.54 16.28C19.54 17.79 18.31 19.02 16.8 19.02C15.29 19.02 14.06 17.79 14.06 16.28ZM9.96 14.84L16.8 14.84L16.8 19.02L9.96 19.02Z',
    ),
  ],
  'partly': [
    (
      color: 0xFFf59e0b,
      path:
          'M4.6 8C4.6 6.12 6.12 4.6 8 4.6C9.88 4.6 11.4 6.12 11.4 8C11.4 9.88 9.88 11.4 8 11.4C6.12 11.4 4.6 9.88 4.6 8ZM12.6 8.75L14.8 8.75L14.8 7.25L12.6 7.25ZM10.72 11.78L12.28 13.34L13.34 12.28L11.78 10.72ZM7.25 12.6L7.25 14.8L8.75 14.8L8.75 12.6ZM4.22 10.72L2.66 12.28L3.72 13.34L5.28 11.78ZM3.4 7.25L1.2 7.25L1.2 8.75L3.4 8.75ZM5.28 4.22L3.72 2.66L2.66 3.72L4.22 5.28ZM8.75 3.4L8.75 1.2L7.25 1.2L7.25 3.4ZM11.78 5.28L13.34 3.72L12.28 2.66L10.72 4.22Z',
    ),
    (
      color: 0xFF94a3b8,
      path:
          'M4 16C4 13.79 5.79 12 8 12C10.21 12 12 13.79 12 16C12 18.21 10.21 20 8 20C5.79 20 4 18.21 4 16ZM8 12.5C8 9.74 10.24 7.5 13 7.5C15.76 7.5 18 9.74 18 12.5C18 15.26 15.76 17.5 13 17.5C10.24 17.5 8 15.26 8 12.5ZM13.7 16C13.7 13.9 15.4 12.2 17.5 12.2C19.6 12.2 21.3 13.9 21.3 16C21.3 18.1 19.6 19.8 17.5 19.8C15.4 19.8 13.7 18.1 13.7 16ZM8 14L17.5 14L17.5 19.8L8 19.8Z',
    ),
  ],
  'cloud': [
    (
      color: 0xFF94a3b8,
      path:
          'M4 15C4 12.79 5.79 11 8 11C10.21 11 12 12.79 12 15C12 17.21 10.21 19 8 19C5.79 19 4 17.21 4 15ZM8 11.5C8 8.74 10.24 6.5 13 6.5C15.76 6.5 18 8.74 18 11.5C18 14.26 15.76 16.5 13 16.5C10.24 16.5 8 14.26 8 11.5ZM13.7 15C13.7 12.9 15.4 11.2 17.5 11.2C19.6 11.2 21.3 12.9 21.3 15C21.3 17.1 19.6 18.8 17.5 18.8C15.4 18.8 13.7 17.1 13.7 15ZM8 13L17.5 13L17.5 18.8L8 18.8Z',
    ),
  ],
  'fog': [
    (
      color: 0xFF94a3b8,
      path: 'M3 7L21 7L21 9.2L3 9.2ZM5 11L21 11L21 13.2L5 13.2ZM3 15L21 15L21 17.2L3 17.2ZM6 19L18 19L18 21.2L6 21.2Z',
    ),
  ],
  'showers': [
    (
      color: 0xFFf59e0b,
      path:
          'M4 6C4 4.34 5.34 3 7 3C8.66 3 10 4.34 10 6C10 7.66 8.66 9 7 9C5.34 9 4 7.66 4 6ZM11.2 6.75L13.2 6.75L13.2 5.25L11.2 5.25ZM9.44 9.5L10.85 10.91L11.91 9.85L10.5 8.44ZM6.25 10.2L6.25 12.2L7.75 12.2L7.75 10.2ZM3.5 8.44L2.09 9.85L3.15 10.91L4.56 9.5ZM2.8 5.25L0.8 5.25L0.8 6.75L2.8 6.75ZM4.56 2.5L3.15 1.09L2.09 2.15L3.5 3.56ZM7.75 1.8L7.75 -0.2L6.25 -0.2L6.25 1.8ZM10.5 3.56L11.91 2.15L10.85 1.09L9.44 2.5Z',
    ),
    (
      color: 0xFF94a3b8,
      path:
          'M4 13C4 10.79 5.79 9 8 9C10.21 9 12 10.79 12 13C12 15.21 10.21 17 8 17C5.79 17 4 15.21 4 13ZM8 9.5C8 6.74 10.24 4.5 13 4.5C15.76 4.5 18 6.74 18 9.5C18 12.26 15.76 14.5 13 14.5C10.24 14.5 8 12.26 8 9.5ZM13.7 13C13.7 10.9 15.4 9.2 17.5 9.2C19.6 9.2 21.3 10.9 21.3 13C21.3 15.1 19.6 16.8 17.5 16.8C15.4 16.8 13.7 15.1 13.7 13ZM8 11L17.5 11L17.5 16.8L8 16.8Z',
    ),
    (
      color: 0xFF2563eb,
      path:
          'M8.5 18.4L9.8 18.4L8.1 22.2L6.8 22.2ZM12.5 18.4L13.8 18.4L12.1 22.2L10.8 22.2ZM16.5 18.4L17.8 18.4L16.1 22.2L14.8 22.2Z',
    ),
  ],
  'rain': [
    (
      color: 0xFF64748b,
      path:
          'M4 13C4 10.79 5.79 9 8 9C10.21 9 12 10.79 12 13C12 15.21 10.21 17 8 17C5.79 17 4 15.21 4 13ZM8 9.5C8 6.74 10.24 4.5 13 4.5C15.76 4.5 18 6.74 18 9.5C18 12.26 15.76 14.5 13 14.5C10.24 14.5 8 12.26 8 9.5ZM13.7 13C13.7 10.9 15.4 9.2 17.5 9.2C19.6 9.2 21.3 10.9 21.3 13C21.3 15.1 19.6 16.8 17.5 16.8C15.4 16.8 13.7 15.1 13.7 13ZM8 11L17.5 11L17.5 16.8L8 16.8Z',
    ),
    (
      color: 0xFF2563eb,
      path:
          'M8.5 18.4L9.8 18.4L8.1 22.2L6.8 22.2ZM12.5 18.4L13.8 18.4L12.1 22.2L10.8 22.2ZM16.5 18.4L17.8 18.4L16.1 22.2L14.8 22.2Z',
    ),
  ],
  'sleet': [
    (
      color: 0xFF64748b,
      path:
          'M4 13C4 10.79 5.79 9 8 9C10.21 9 12 10.79 12 13C12 15.21 10.21 17 8 17C5.79 17 4 15.21 4 13ZM8 9.5C8 6.74 10.24 4.5 13 4.5C15.76 4.5 18 6.74 18 9.5C18 12.26 15.76 14.5 13 14.5C10.24 14.5 8 12.26 8 9.5ZM13.7 13C13.7 10.9 15.4 9.2 17.5 9.2C19.6 9.2 21.3 10.9 21.3 13C21.3 15.1 19.6 16.8 17.5 16.8C15.4 16.8 13.7 15.1 13.7 13ZM8 11L17.5 11L17.5 16.8L8 16.8Z',
    ),
    (color: 0xFF2563eb, path: 'M8.5 18.4L9.8 18.4L8.1 22.2L6.8 22.2ZM16.5 18.4L17.8 18.4L16.1 22.2L14.8 22.2Z'),
    (
      color: 0xFF38bdf8,
      path:
          'M11.1 20.5C11.1 19.73 11.73 19.1 12.5 19.1C13.27 19.1 13.9 19.73 13.9 20.5C13.9 21.27 13.27 21.9 12.5 21.9C11.73 21.9 11.1 21.27 11.1 20.5Z',
    ),
  ],
  'snow_showers': [
    (
      color: 0xFFf59e0b,
      path:
          'M4 6C4 4.34 5.34 3 7 3C8.66 3 10 4.34 10 6C10 7.66 8.66 9 7 9C5.34 9 4 7.66 4 6ZM11.2 6.75L13.2 6.75L13.2 5.25L11.2 5.25ZM9.44 9.5L10.85 10.91L11.91 9.85L10.5 8.44ZM6.25 10.2L6.25 12.2L7.75 12.2L7.75 10.2ZM3.5 8.44L2.09 9.85L3.15 10.91L4.56 9.5ZM2.8 5.25L0.8 5.25L0.8 6.75L2.8 6.75ZM4.56 2.5L3.15 1.09L2.09 2.15L3.5 3.56ZM7.75 1.8L7.75 -0.2L6.25 -0.2L6.25 1.8ZM10.5 3.56L11.91 2.15L10.85 1.09L9.44 2.5Z',
    ),
    (
      color: 0xFF94a3b8,
      path:
          'M4 13C4 10.79 5.79 9 8 9C10.21 9 12 10.79 12 13C12 15.21 10.21 17 8 17C5.79 17 4 15.21 4 13ZM8 9.5C8 6.74 10.24 4.5 13 4.5C15.76 4.5 18 6.74 18 9.5C18 12.26 15.76 14.5 13 14.5C10.24 14.5 8 12.26 8 9.5ZM13.7 13C13.7 10.9 15.4 9.2 17.5 9.2C19.6 9.2 21.3 10.9 21.3 13C21.3 15.1 19.6 16.8 17.5 16.8C15.4 16.8 13.7 15.1 13.7 13ZM8 11L17.5 11L17.5 16.8L8 16.8Z',
    ),
    (
      color: 0xFF38bdf8,
      path:
          'M6.7 20.5C6.7 19.78 7.28 19.2 8 19.2C8.72 19.2 9.3 19.78 9.3 20.5C9.3 21.22 8.72 21.8 8 21.8C7.28 21.8 6.7 21.22 6.7 20.5ZM11.2 20.5C11.2 19.78 11.78 19.2 12.5 19.2C13.22 19.2 13.8 19.78 13.8 20.5C13.8 21.22 13.22 21.8 12.5 21.8C11.78 21.8 11.2 21.22 11.2 20.5ZM15.7 20.5C15.7 19.78 16.28 19.2 17 19.2C17.72 19.2 18.3 19.78 18.3 20.5C18.3 21.22 17.72 21.8 17 21.8C16.28 21.8 15.7 21.22 15.7 20.5Z',
    ),
  ],
  'snow': [
    (
      color: 0xFF64748b,
      path:
          'M4 13C4 10.79 5.79 9 8 9C10.21 9 12 10.79 12 13C12 15.21 10.21 17 8 17C5.79 17 4 15.21 4 13ZM8 9.5C8 6.74 10.24 4.5 13 4.5C15.76 4.5 18 6.74 18 9.5C18 12.26 15.76 14.5 13 14.5C10.24 14.5 8 12.26 8 9.5ZM13.7 13C13.7 10.9 15.4 9.2 17.5 9.2C19.6 9.2 21.3 10.9 21.3 13C21.3 15.1 19.6 16.8 17.5 16.8C15.4 16.8 13.7 15.1 13.7 13ZM8 11L17.5 11L17.5 16.8L8 16.8Z',
    ),
    (
      color: 0xFF38bdf8,
      path:
          'M6.7 20.5C6.7 19.78 7.28 19.2 8 19.2C8.72 19.2 9.3 19.78 9.3 20.5C9.3 21.22 8.72 21.8 8 21.8C7.28 21.8 6.7 21.22 6.7 20.5ZM11.2 20.5C11.2 19.78 11.78 19.2 12.5 19.2C13.22 19.2 13.8 19.78 13.8 20.5C13.8 21.22 13.22 21.8 12.5 21.8C11.78 21.8 11.2 21.22 11.2 20.5ZM15.7 20.5C15.7 19.78 16.28 19.2 17 19.2C17.72 19.2 18.3 19.78 18.3 20.5C18.3 21.22 17.72 21.8 17 21.8C16.28 21.8 15.7 21.22 15.7 20.5Z',
    ),
  ],
  'thunder': [
    (
      color: 0xFF64748b,
      path:
          'M4 12.5C4 10.29 5.79 8.5 8 8.5C10.21 8.5 12 10.29 12 12.5C12 14.71 10.21 16.5 8 16.5C5.79 16.5 4 14.71 4 12.5ZM8 9C8 6.24 10.24 4 13 4C15.76 4 18 6.24 18 9C18 11.76 15.76 14 13 14C10.24 14 8 11.76 8 9ZM13.7 12.5C13.7 10.4 15.4 8.7 17.5 8.7C19.6 8.7 21.3 10.4 21.3 12.5C21.3 14.6 19.6 16.3 17.5 16.3C15.4 16.3 13.7 14.6 13.7 12.5ZM8 10.5L17.5 10.5L17.5 16.3L8 16.3Z',
    ),
    (color: 0xFFeab308, path: 'M12.5 14L9 19.5L11.8 19.5L10.5 23.5L15.5 17.2L12.6 17.2L14.3 14Z'),
  ],
};

/// MeteoSwiss's pictogram numbers: our icon and MeteoSwiss's words.
const weatherSymbols = <int, ({String icon, String de, String fr, String it, String en})>{
  1: (icon: 'sun', de: 'sonnig', fr: 'ensoleillé', it: 'soleggiato', en: 'sunny'),
  2: (
    icon: 'few_clouds',
    de: 'ziemlich sonnig',
    fr: 'assez ensoleillé, quelques passages nuageux',
    it: 'abbastanza soleggiato',
    en: 'mostly sunny, some clouds',
  ),
  3: (
    icon: 'partly',
    de: 'teilweise sonnig',
    fr: 'en partie ensoleillé, passages nuageux parfois denses',
    it: 'parzialmente soleggiato',
    en: 'partly sunny, thick passing clouds',
  ),
  4: (icon: 'cloud', de: 'wechselnd bewölkt', fr: 'nuageux', it: 'nuvoloso', en: 'overcast'),
  5: (icon: 'cloud', de: 'bedeckt', fr: 'très nuageux', it: 'coperto', en: 'very cloudy'),
  6: (
    icon: 'showers',
    de: 'Aufhellungen, einzelne Regenschauer',
    fr: 'éclaircies, averses isolées',
    it: 'nuvolosità variabile con rovesci di pioggia isolati',
    en: 'sunny intervals, isolated showers',
  ),
  7: (
    icon: 'sleet',
    de: 'Aufhellungen, einzelne Regen- oder Schneeschauer',
    fr: 'éclaircies, averses isolées de pluie et neige mêlées',
    it: 'nuvolosità variabile con rovesci di pioggia e neve isolati',
    en: 'sunny intervals, isolated sleet',
  ),
  8: (
    icon: 'snow_showers',
    de: 'Aufhellungen, einzelne Schneeschauer',
    fr: 'éclaircies, giboulées de neige',
    it: 'nuvolosità variabile con rovesci di neve isolati',
    en: 'sunny intervals, snow showers',
  ),
  9: (
    icon: 'rain',
    de: 'bewölkt, einige Regenschauer',
    fr: 'nuageux, quelques averses',
    it: 'nuvoloso con rovesci di pioggia',
    en: 'overcast, some rain showers',
  ),
  10: (
    icon: 'sleet',
    de: 'bewölkt, einige Regen- oder Schneeschauer',
    fr: 'nuageux, quelques averses de pluie et neige mêlées',
    it: 'nuvoloso con rovesci di pioggia e neve',
    en: 'overcast, some sleet',
  ),
  11: (
    icon: 'snow',
    de: 'bewölkt, einige Schneeschauer',
    fr: 'nuageux, quelques averses de neige',
    it: 'nuvoloso con rovesci di neve',
    en: 'overcast, some snow showers',
  ),
  12: (
    icon: 'thunder',
    de: 'Aufhellungen, leicht gewitterhaft',
    fr: 'éclaircies, faiblement orageux',
    it: 'nuvolosità variabile, con temporali possibili',
    en: 'sunny intervals, chance of thunderstorms',
  ),
  13: (
    icon: 'thunder',
    de: 'Aufhellungen und gewitterhaft',
    fr: 'éclaircies, orageux',
    it: 'nuvolosità variabile e temporalesco',
    en: 'sunny intervals, possible thunderstorms',
  ),
  14: (
    icon: 'rain',
    de: 'stark bewölkt, schwacher Regen',
    fr: 'très nuageux, faibles pluies',
    it: 'molto nuvoloso, deboli piogge',
    en: 'very cloudy, light rain',
  ),
  15: (
    icon: 'sleet',
    de: 'stark bewölkt, schwacher Schnee oder Regen',
    fr: 'très nuageux, faibles chutes de pluie et neige mêlées',
    it: 'molto nuvoloso, debole pioggia frammista a neve',
    en: 'very cloudy, light sleet',
  ),
  16: (
    icon: 'snow',
    de: 'stark bewölkt, schwacher Schnee',
    fr: 'très nuageux, faibles chutes de neige',
    it: 'molto nuvoloso, deboli nevicate',
    en: 'very cloudy, light snow showers',
  ),
  17: (
    icon: 'rain',
    de: 'stark bewölkt, zeitweise Regen',
    fr: 'très nuageux, pluies intermittentes',
    it: 'molto nuvoloso, piogge intermittenti',
    en: 'very cloudy, intermittent rain',
  ),
  18: (
    icon: 'sleet',
    de: 'stark bewölkt, zeitweise Schnee oder Regen',
    fr: 'très nuageux, chutes intermittentes de pluie et neige mêlées',
    it: 'molto nuvoloso, pioggia frammista a neve intermittente',
    en: 'very cloudy, intermittent sleet',
  ),
  19: (
    icon: 'snow',
    de: 'stark bewölkt, zeitweise Schnee',
    fr: 'très nuageux, chutes de neige intermittentes',
    it: 'molto nuvoloso, nevicate intermittenti',
    en: 'very cloudy, intermittent snow',
  ),
  20: (
    icon: 'rain',
    de: 'stark bewölkt, anhaltender Regen',
    fr: 'très nuageux, pluie continue',
    it: 'molto nuvoloso, piogge intense',
    en: 'very overcast with rain',
  ),
  21: (
    icon: 'sleet',
    de: 'stark bewölkt, anhaltender Regen oder Schnee',
    fr: 'très nuageux, fréquentes chutes de pluie et neige mêlées',
    it: 'molto nuvoloso, piogge e nevicate intense',
    en: 'very overcast with frequent sleet',
  ),
  22: (
    icon: 'snow',
    de: 'stark bewölkt, anhaltender Schnee',
    fr: 'très nuageux, fortes chutes de neige',
    it: 'molto nuvoloso, nevicate intense',
    en: 'very overcast with heavy snow',
  ),
  23: (
    icon: 'thunder',
    de: 'stark bewölkt, leicht gewitterhaft',
    fr: 'très nuageux, faiblement orageux',
    it: 'molto nuvoloso, temporali isolati',
    en: 'very overcast, slight chance of storms',
  ),
  24: (
    icon: 'thunder',
    de: 'stark bewölkt, gewitterhaft',
    fr: 'très nuageux, orageux',
    it: 'molto nuvoloso, temporalesco',
    en: 'very overcast with storms',
  ),
  25: (
    icon: 'thunder',
    de: 'stark bewölkt, stark gewitterhaft',
    fr: 'très nuageux, très orageux',
    it: 'molto nuvoloso con temporali intensi',
    en: 'very cloudy, very stormy',
  ),
  26: (
    icon: 'few_clouds',
    de: 'Hohe Bewölkung',
    fr: 'nuages élevés',
    it: 'a tratti nuvolosità ad alta quota',
    en: 'high clouds',
  ),
  27: (icon: 'fog', de: 'Hochnebel', fr: 'stratus', it: 'nebbia alta', en: 'stratus'),
  28: (icon: 'fog', de: 'Nebel', fr: 'brouillard', it: 'nebbia', en: 'fog'),
  29: (
    icon: 'showers',
    de: 'leicht bewölkt, einzelne Regenschauer',
    fr: 'belles éclaircies, averses éparses',
    it: 'in parte nuvoloso, isolati rovesci',
    en: 'sunny intervals, scattered showers',
  ),
  30: (
    icon: 'snow_showers',
    de: 'leicht bewölkt, leichter Schneefall',
    fr: 'belles éclaircies, giboulées de neige',
    it: 'in parte nuvoloso, isolati rovesci di neve',
    en: 'sunny intervals, scattered snow showers',
  ),
  31: (
    icon: 'sleet',
    de: 'teilweise sonnig, einige Schnee- oder Regenschauer',
    fr: 'belles éclaircies, giboulées de pluie et de neige mêlées',
    it: 'in parte nuvoloso, con rovesci di pioggia e di neve',
    en: 'sunny intervals, scattered sleet',
  ),
  32: (
    icon: 'showers',
    de: 'teilweise sonnig, einige Regenschauer',
    fr: 'éclaircies, quelques averses',
    it: 'in parte nuvoloso con rovesci',
    en: 'sunny intervals, some showers',
  ),
  33: (
    icon: 'rain',
    de: 'bewölkt, häufige Regenschauer',
    fr: 'rares éclaircies, fréquentes averses',
    it: 'nuvoloso con frequenti rovesci di pioggia',
    en: 'short sunny intervals, frequent rain',
  ),
  34: (
    icon: 'snow',
    de: 'bewölkt, häufige Schneeschauer',
    fr: 'rares éclaircies, fréquentes averses de neige',
    it: 'nuvoloso con frequenti rovesci di neve',
    en: 'short sunny intervals, frequent snowfalls',
  ),
  35: (
    icon: 'cloud',
    de: 'bedeckt und trocken',
    fr: 'couvert et sec',
    it: 'estesa nuvolosità ad alta quota',
    en: 'overcast and dry',
  ),
  36: (
    icon: 'thunder',
    de: 'teilweise sonnig, gewitterhaft',
    fr: 'partiellement ensoleillé, orageux',
    it: 'in parte nuvoloso, temporali isolati',
    en: 'partly sunny, slightly stormy',
  ),
  37: (
    icon: 'thunder',
    de: 'teilweise sonnig, Gewitter und Schneeschauer',
    fr: 'partiellement ensoleillé, averses de neige orageuses',
    it: 'in parte nuvoloso, temporali con rovesci di neve',
    en: 'partly sunny, stormy snow showers',
  ),
  38: (
    icon: 'thunder',
    de: 'bewölkt, Gewitter und häufige Regenschauer',
    fr: 'nuageux, averses orageuses',
    it: 'nuvoloso, temporalesco',
    en: 'overcast, thundery showers',
  ),
  39: (
    icon: 'thunder',
    de: 'bewölkt, Gewitter und häufige Schneeschauer',
    fr: 'nuageux, averses de neige orageuses',
    it: 'nuvoloso, temporali con rovesci di neve',
    en: 'overcast, thundery snow showers',
  ),
  40: (
    icon: 'thunder',
    de: 'stark bewölkt, leicht gewitterhaft',
    fr: 'très nuageux, faiblement orageux',
    it: 'molto nuvoloso, con temporali possibili',
    en: 'very cloudy, slightly stormy',
  ),
  41: (
    icon: 'thunder',
    de: 'bewölkt, leicht gewitterhaft',
    fr: 'nuageux, faiblement orageux',
    it: 'nuvoloso, con temporali possibili',
    en: 'overcast, slightly stormy',
  ),
  42: (
    icon: 'thunder',
    de: 'stark bewölkt, Gewitter und häufige Schneeschauer',
    fr: 'très nuageux, averses de neige orageuses',
    it: 'molto nuvoloso, temporali con rovesci di neve',
    en: 'very cloudy, thundery snow showers',
  ),
};

/// The symbol of [code] (the night's 101–142 as the day's) in [language].
({String icon, String text})? weatherSymbol(int? code, String language) {
  final s = weatherSymbols[code != null && code > 100 ? code - 100 : code];
  if (s == null) return null;
  final text = switch (language) {
    'fr' => s.fr,
    'it' => s.it,
    'en' => s.en,
    _ => s.de,
  };
  return (icon: s.icon, text: text);
}

/// MeteoSwiss's symbol as our icon, named for screen readers.
class WeatherIcon extends StatelessWidget {
  const WeatherIcon(this.code, {super.key, this.size = 28});
  final int? code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = weatherSymbol(code, Localizations.localeOf(context).languageCode);
    if (s == null) return const SizedBox.shrink();
    return Semantics(
      label: s.text,
      child: Tooltip(
        message: s.text,
        child: CustomPaint(key: const Key('weather-icon'), size: Size.square(size), painter: _WeatherPainter(s.icon)),
      ),
    );
  }
}

class _WeatherPainter extends CustomPainter {
  _WeatherPainter(this.icon);
  final String icon;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    for (final l in weatherIcons[icon] ?? const <({int color, String path})>[]) {
      canvas.drawPath(iconPath(l.path), Paint()..color = Color(l.color));
    }
  }

  @override
  bool shouldRepaint(_WeatherPainter old) => old.icon != icon;
}
