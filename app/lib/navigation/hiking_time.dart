/// The Swiss hiking time formula (SchweizMobil variant, as on
/// map.geo.admin.ch), ported from swiss/hikingtime. Times are walking time
/// without breaks.
library;

// Coefficients of the polynomial in the slope s (in tenths, s=1 ⇔ 10 %)
// giving minutes per horizontal kilometre.
const _coefficients = [
  14.271, 3.6991, 2.5922, -1.4384, //
  0.32105, 0.81542, -0.090261, -0.20757,
  0.010192, 0.028588, -0.00057466, -0.0021842,
  1.5176e-5, 8.6894e-5, -1.3584e-7, -1.4026e-6,
];

/// Walking minutes per horizontal kilometre on a slope [s] in tenths
/// (Δh·10/Δd); 14.271 on flat ground (4.2 km/h).
double minutesPerKm(double s) {
  if (s > -4 && s < 4) {
    var m = 0.0;
    for (var i = _coefficients.length - 1; i >= 0; i--) {
      m = m * s + _coefficients[i];
    }
    return m;
  }
  return s > 0 ? 17 * s : -9 * s;
}

/// Walking minutes for [d] horizontal metres climbing [dh] metres.
double segmentMinutes(double d, double dh) => d == 0 ? 0 : d * minutesPerKm(dh * 10 / d) / 1000;
