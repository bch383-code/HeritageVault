class CoinSeriesReference {
  final String series;
  final String denomination;
  final String years;
  final String designer;
  final String composition;
  final List<String> mints;
  final String history;
  final String imageAsset;

  const CoinSeriesReference({
    required this.series,
    required this.denomination,
    required this.years,
    required this.designer,
    required this.composition,
    required this.mints,
    required this.history,
    required this.imageAsset,
  });
}

class CoinSeriesLibrary {
  static const List<CoinSeriesReference> series = [
    CoinSeriesReference(
      series: 'Morgan Dollars',
      denomination: 'Dollar',
      years: '1878–1921',
      designer: 'George T. Morgan',
      composition: '90% silver, 10% copper',
      mints: ['P', 'CC', 'O', 'S', 'D'],
      history:
          'The Morgan dollar is one of the most widely collected United States silver dollar series.',
      imageAsset: '',
    ),
    CoinSeriesReference(
      series: 'Peace Dollars',
      denomination: 'Dollar',
      years: '1921–1935',
      designer: 'Anthony de Francisci',
      composition: '90% silver, 10% copper',
      mints: ['P', 'D', 'S'],
      history:
          'The Peace dollar was created to commemorate peace following World War I.',
      imageAsset: '',
    ),
    CoinSeriesReference(
      series: 'Lincoln Wheat Cents',
      denomination: 'Cent',
      years: '1909–1958',
      designer: 'Victor David Brenner',
      composition: 'Primarily bronze; wartime composition varied',
      mints: ['P', 'D', 'S'],
      history:
          'The Lincoln cent introduced a portrait of Abraham Lincoln in 1909 and originally featured wheat ears on the reverse.',
      imageAsset: '',
    ),
    CoinSeriesReference(
      series: 'Buffalo Nickels',
      denomination: 'Nickel',
      years: '1913–1938',
      designer: 'James Earle Fraser',
      composition: '75% copper, 25% nickel',
      mints: ['P', 'D', 'S'],
      history:
          'The Buffalo nickel features a Native American portrait on the obverse and an American bison on the reverse.',
      imageAsset: '',
    ),
    CoinSeriesReference(
      series: 'Mercury Dimes',
      denomination: 'Dime',
      years: '1916–1945',
      designer: 'Adolph A. Weinman',
      composition: '90% silver, 10% copper',
      mints: ['P', 'D', 'S'],
      history:
          'Commonly called the Mercury dime, the obverse actually depicts Liberty wearing a winged cap.',
      imageAsset: '',
    ),
  ];

  static CoinSeriesReference? find(String seriesName) {
    final normalized = seriesName.trim().toLowerCase();

    for (final reference in series) {
      if (reference.series.toLowerCase() == normalized) {
        return reference;
      }
    }

    return null;
  }
}