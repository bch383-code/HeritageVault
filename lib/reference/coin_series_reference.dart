import '../widgets/history_timeline.dart';

class CoinSeriesReference {
  final String series;
  final String denomination;
  final String years;
  final String designer;
  final String composition;
  final List<String> mints;
  final String history;
  final String imageAsset;
  final String thumbnailAsset;

  const CoinSeriesReference({
    required this.series,
    required this.denomination,
    required this.years,
    required this.designer,
    required this.composition,
    required this.mints,
    required this.history,
    required this.imageAsset,
    required this.thumbnailAsset,
  });
}

class CoinSeriesLibrary {
  static const List<CoinSeriesReference> series = [
    CoinSeriesReference(
      series: 'Liberty Head Half Cents',
      denomination: 'Half Cent',
      years: '1793–1857',
      designer: 'Various',
      composition: 'Copper',
      mints: ['P'],
      history: 'Heritage Vault groups the early United States half-cent types together as Liberty Head Half Cents.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/liberty_head_half_cent_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Wreath Cents',
      denomination: 'Cent',
      years: '1793',
      designer: 'Henry Voigt',
      composition: 'Copper',
      mints: ['P'],
      history: 'The Wreath cent was one of the earliest large-cent designs issued by the United States Mint.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/wreath_cent_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Liberty Cap Cents',
      denomination: 'Cent',
      years: '1793–1796',
      designer: 'Joseph Wright / Robert Scot',
      composition: 'Copper',
      mints: ['P'],
      history: 'Liberty Cap cents were an early large-cent type featuring Liberty with a cap and pole.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/liberty_cap_cent_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Chain Cents',
      denomination: 'Cent',
      years: '1793',
      designer: 'Henry Voigt',
      composition: 'Copper',
      mints: ['P'],
      history: 'The Chain cent was the first regular-issue United States cent.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/chain_cent_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Draped Bust Cents',
      denomination: 'Cent',
      years: '1796–1807',
      designer: 'Robert Scot',
      composition: 'Copper',
      mints: ['P'],
      history: 'Draped Bust large cents paired the Draped Bust portrait with early federal reverse designs.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/draped_bust_cent_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Classic Head Cents',
      denomination: 'Cent',
      years: '1808–1814',
      designer: 'John Reich',
      composition: 'Copper',
      mints: ['P'],
      history: 'Classic Head cents were an early nineteenth-century large-cent design.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/classic_head_cent_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Coronet Cents',
      denomination: 'Cent',
      years: '1816–1857',
      designer: 'Robert Scot / Christian Gobrecht',
      composition: 'Copper',
      mints: ['P'],
      history: 'Coronet large cents, also called Matron Head and Braided Hair cents, closed the large-cent era.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/coronet_cent_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Flying Eagle Cents',
      denomination: 'Cent',
      years: '1856–1858',
      designer: 'James B. Longacre',
      composition: 'Copper-nickel',
      mints: ['P'],
      history: 'The Flying Eagle cent introduced the smaller cent format that remains familiar today.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/flying_eagle_cent_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Indian Head Cents',
      denomination: 'Cent',
      years: '1859–1909',
      designer: 'James Barton Longacre',
      composition: 'Copper-nickel initially; later bronze',
      mints: ['P', 'S'],
      history: 'The Indian Head cent was produced for fifty years and became one of the classic early United States small-cent designs.',
      imageAsset: 'assets/images/series/indian_head_cent.png',
      thumbnailAsset: 'assets/images/series/indian_head_cent_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Lincoln Wheat Cents',
      denomination: 'Cent',
      years: '1909–1958',
      designer: 'Victor David Brenner',
      composition: 'Primarily bronze; wartime composition varied',
      mints: ['P', 'D', 'S'],
      history: 'The Lincoln cent introduced a portrait of Abraham Lincoln in 1909 and originally featured wheat ears on the reverse.',
      imageAsset: 'assets/images/series/lincoln_wheat_cent.png',
      thumbnailAsset: 'assets/images/series/lincoln_wheat_cent_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Lincoln Shield Cents',
      denomination: 'Cent',
      years: '2010–Present',
      designer: 'Victor David Brenner / Lyndall Bass',
      composition: 'Copper-plated zinc',
      mints: ['P', 'D', 'S', 'W'],
      history: 'The Lincoln Shield cent pairs the long-running Lincoln portrait with a Union Shield reverse.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/lincoln_shield_cent_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Two Cent Pieces',
      denomination: 'Two Cent',
      years: '1864–1873',
      designer: 'James B. Longacre',
      composition: 'Bronze',
      mints: ['P'],
      history: 'The two-cent piece was the first U.S. coin to carry the motto IN GOD WE TRUST.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/two_cent_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Three Cent Silver',
      denomination: 'Three Cent',
      years: '1851–1873',
      designer: 'James B. Longacre',
      composition: 'Silver alloy',
      mints: ['P', 'O'],
      history: 'The small three-cent silver coin was introduced in 1851 and is often called a trime.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/three_cent_silver_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Three Cent Nickel',
      denomination: 'Three Cent',
      years: '1865–1889',
      designer: 'James B. Longacre',
      composition: 'Copper-nickel',
      mints: ['P'],
      history: 'The three-cent nickel was introduced during the Civil War era and remained in production through 1889.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/three_cent_nickel_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Shield Nickels',
      denomination: 'Nickel',
      years: '1866–1883',
      designer: 'James B. Longacre',
      composition: '75% copper, 25% nickel',
      mints: ['P'],
      history: 'The Shield nickel was the first five-cent coin struck in the copper-nickel alloy used for later nickels.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/shield_nickel_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Liberty Head Nickels',
      denomination: 'Nickel',
      years: '1883–1913',
      designer: 'Charles E. Barber',
      composition: '75% copper, 25% nickel',
      mints: ['P'],
      history: 'The Liberty Head or V nickel followed the Shield nickel and was produced from 1883 through 1913.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/liberty_head_nickel_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Buffalo Nickels',
      denomination: 'Nickel',
      years: '1913–1938',
      designer: 'James Earle Fraser',
      composition: '75% copper, 25% nickel',
      mints: ['P', 'D', 'S'],
      history: 'The Buffalo nickel features a Native American portrait on the obverse and an American bison on the reverse.',
      imageAsset: 'assets/images/series/buffalo_nickel.png',
      thumbnailAsset: 'assets/images/series/buffalo_nickel_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Jefferson Nickels',
      denomination: 'Nickel',
      years: '1938–Present',
      designer: 'Felix Schlag and later artists',
      composition: 'Primarily 75% copper, 25% nickel',
      mints: ['P', 'D', 'S'],
      history: 'The Jefferson nickel replaced the Buffalo nickel in 1938 and originally paired Thomas Jefferson with Monticello.',
      imageAsset: 'assets/images/series/jefferson_nickel.png',
      thumbnailAsset: 'assets/images/series/jefferson_nickel_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Flowing Hair Half Dimes',
      denomination: 'Half Dime',
      years: '1794–1795',
      designer: 'Robert Scot',
      composition: 'Silver',
      mints: ['P'],
      history: 'Flowing Hair half dimes were among the earliest silver coins of the United States.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/flowing_hair_half_dime_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Draped Bust Half Dimes',
      denomination: 'Half Dime',
      years: '1796–1797',
      designer: 'Robert Scot',
      composition: 'Silver',
      mints: ['P'],
      history: 'Early Draped Bust half dimes used the Small Eagle reverse.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/draped_bust_half_dime_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Draped Bust Half Dimes - Heraldic Eagle',
      denomination: 'Half Dime',
      years: '1800–1805',
      designer: 'Robert Scot',
      composition: 'Silver',
      mints: ['P'],
      history: 'Later Draped Bust half dimes used the Heraldic Eagle reverse.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/draped_bust_heraldic_half_dime_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Capped Bust Half Dimes',
      denomination: 'Half Dime',
      years: '1829–1837',
      designer: 'William Kneass / John Reich influence',
      composition: 'Silver',
      mints: ['P'],
      history: 'Capped Bust half dimes returned the denomination to production in 1829.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/capped_bust_half_dime_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Liberty Seated Half Dimes',
      denomination: 'Half Dime',
      years: '1837–1873',
      designer: 'Christian Gobrecht',
      composition: 'Silver',
      mints: ['P', 'O', 'S'],
      history: 'Liberty Seated half dimes were the final series of the half-dime denomination.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/liberty_seated_half_dime_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Draped Bust Dimes',
      denomination: 'Dime',
      years: '1796–1807',
      designer: 'Robert Scot',
      composition: 'Silver',
      mints: ['P'],
      history: 'Draped Bust dimes were among the earliest ten-cent coins produced by the United States Mint.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/draped_bust_dime_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Capped Bust Dimes',
      denomination: 'Dime',
      years: '1809–1837',
      designer: 'John Reich / William Kneass',
      composition: 'Silver',
      mints: ['P'],
      history: 'Capped Bust dimes were struck from 1809 through 1837.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/capped_bust_dime_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Liberty Seated Dimes',
      denomination: 'Dime',
      years: '1837–1891',
      designer: 'Christian Gobrecht',
      composition: 'Silver',
      mints: ['P', 'O', 'S', 'CC'],
      history: 'Liberty Seated dimes were issued for more than half a century with several design modifications.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/liberty_seated_dime_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Barber Dimes',
      denomination: 'Dime',
      years: '1892–1916',
      designer: 'Charles E. Barber',
      composition: '90% silver, 10% copper',
      mints: ['P', 'D', 'O', 'S'],
      history: 'The Barber dime was part of Charles E. Barber’s coordinated silver coinage redesign.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/barber_dime_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Mercury Dimes',
      denomination: 'Dime',
      years: '1916–1945',
      designer: 'Adolph A. Weinman',
      composition: '90% silver, 10% copper',
      mints: ['P', 'D', 'S'],
      history: 'Commonly called the Mercury dime, the obverse actually depicts Liberty wearing a winged cap.',
      imageAsset: 'assets/images/series/mercury_dime.png',
      thumbnailAsset: 'assets/images/series/mercury_dime_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Roosevelt Dimes',
      denomination: 'Dime',
      years: '1946–Present',
      designer: 'John R. Sinnock',
      composition: 'Silver through 1964; copper-nickel clad thereafter',
      mints: ['P', 'D', 'S', 'W'],
      history: 'The Roosevelt dime was introduced in 1946 in honor of President Franklin D. Roosevelt.',
      imageAsset: 'assets/images/series/roosevelt_dime.png',
      thumbnailAsset: 'assets/images/series/roosevelt_dime_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Liberty Seated Twenty Cent Pieces',
      denomination: 'Twenty Cent',
      years: '1875–1878',
      designer: 'William Barber',
      composition: '90% silver, 10% copper',
      mints: ['P', 'S', 'CC'],
      history: 'The short-lived twenty-cent denomination was struck from 1875 through 1878.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/liberty_seated_twenty_cent_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Draped Bust Quarters',
      denomination: 'Quarter',
      years: '1796–1807',
      designer: 'Robert Scot',
      composition: 'Silver',
      mints: ['P'],
      history: 'Draped Bust quarters were the first regular United States quarter dollars.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/draped_bust_quarter_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Capped Bust Quarters',
      denomination: 'Quarter',
      years: '1815–1838',
      designer: 'John Reich / William Kneass',
      composition: 'Silver',
      mints: ['P'],
      history: 'Capped Bust quarters were issued intermittently from 1815 through 1838.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/capped_bust_quarter_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Liberty Seated Quarters',
      denomination: 'Quarter',
      years: '1838–1891',
      designer: 'Christian Gobrecht',
      composition: 'Silver',
      mints: ['P', 'O', 'S', 'CC'],
      history: 'Liberty Seated quarters were produced for more than five decades with multiple design varieties.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/liberty_seated_quarter_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Barber Quarters',
      denomination: 'Quarter',
      years: '1892–1916',
      designer: 'Charles E. Barber',
      composition: '90% silver, 10% copper',
      mints: ['P', 'D', 'O', 'S'],
      history: 'The Barber quarter was part of Charles E. Barber’s coordinated redesign of U.S. silver coinage.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/barber_quarter_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Standing Liberty Quarters',
      denomination: 'Quarter',
      years: '1916–1930',
      designer: 'Hermon A. MacNeil',
      composition: '90% silver, 10% copper',
      mints: ['P', 'D', 'S'],
      history: 'The Standing Liberty quarter depicts Liberty standing between a gateway while holding a shield and olive branch.',
      imageAsset: 'assets/images/series/standing_liberty_quarter.png',
      thumbnailAsset: 'assets/images/series/standing_liberty_quarter_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Washington Quarters',
      denomination: 'Quarter',
      years: '1932–1998',
      designer: 'John Flanagan',
      composition: 'Silver through 1964; copper-nickel clad thereafter',
      mints: ['P', 'D', 'S'],
      history: 'The original Washington quarter series ran from 1932 through 1998 before the modern rotating reverse programs.',
      imageAsset: 'assets/images/series/washington_quarter.png',
      thumbnailAsset: 'assets/images/series/washington_quarter_thumb.png',
    ),
    CoinSeriesReference(
      series: 'State & Territory Quarters',
      denomination: 'Quarter',
      years: '1999–2009',
      designer: 'John Flanagan obverse; various reverse artists',
      composition: 'Copper-nickel clad; silver collector issues',
      mints: ['P', 'D', 'S'],
      history: 'The State and Territory quarter programs featured rotating reverse designs honoring the states, District of Columbia, and U.S. territories.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/state_quarter_thumb.png',
    ),
    CoinSeriesReference(
      series: 'America the Beautiful Quarters',
      denomination: 'Quarter',
      years: '2010–2021',
      designer: 'John Flanagan obverse; various reverse artists',
      composition: 'Copper-nickel clad; silver collector issues',
      mints: ['P', 'D', 'S', 'W'],
      history: 'America the Beautiful quarters honored national parks and other national sites from 2010 through 2021.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/america_beautiful_quarter_thumb.png',
    ),
    CoinSeriesReference(
      series: 'American Women Quarters',
      denomination: 'Quarter',
      years: '2022–2025',
      designer: 'Laura Gardin Fraser obverse; various reverse artists',
      composition: 'Copper-nickel clad; silver collector issues',
      mints: ['P', 'D', 'S'],
      history: 'The American Women Quarters Program honored notable American women from 2022 through 2025.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/american_women_quarter_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Flowing Hair Half Dollars',
      denomination: 'Half Dollar',
      years: '1794–1795',
      designer: 'Robert Scot',
      composition: 'Silver',
      mints: ['P'],
      history: 'Flowing Hair half dollars were the first half dollars issued by the United States Mint.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/flowing_hair_half_dollar_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Draped Bust Half Dollars',
      denomination: 'Half Dollar',
      years: '1796–1807',
      designer: 'Robert Scot',
      composition: 'Silver',
      mints: ['P'],
      history: 'Draped Bust half dollars followed the Flowing Hair design and used both Small Eagle and Heraldic Eagle reverses.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/draped_bust_half_dollar_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Capped Bust Half Dollars',
      denomination: 'Half Dollar',
      years: '1807–1836',
      designer: 'John Reich',
      composition: 'Silver',
      mints: ['P'],
      history: 'Lettered-edge Capped Bust half dollars were struck from 1807 through 1836.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/capped_bust_half_dollar_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Capped Bust Half Dollars - Reeded Edge',
      denomination: 'Half Dollar',
      years: '1836–1839',
      designer: 'Christian Gobrecht / John Reich influence',
      composition: 'Silver',
      mints: ['P', 'O'],
      history: 'Reeded-edge Capped Bust half dollars marked the transition to modern steam-powered coinage.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/capped_bust_reeded_half_dollar_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Liberty Seated Half Dollars',
      denomination: 'Half Dollar',
      years: '1839–1891',
      designer: 'Christian Gobrecht',
      composition: 'Silver',
      mints: ['P', 'O', 'S', 'CC'],
      history: 'Liberty Seated half dollars were produced from 1839 through 1891 with several major varieties.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/liberty_seated_half_dollar_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Barber Half Dollars',
      denomination: 'Half Dollar',
      years: '1892–1915',
      designer: 'Charles E. Barber',
      composition: '90% silver, 10% copper',
      mints: ['P', 'D', 'O', 'S'],
      history: 'The Barber half dollar was part of Charles E. Barber’s coordinated redesign of the dime, quarter, and half dollar.',
      imageAsset: 'assets/images/series/barber_half.png',
      thumbnailAsset: 'assets/images/series/barber_half_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Walking Liberty Half Dollars',
      denomination: 'Half Dollar',
      years: '1916–1947',
      designer: 'Adolph A. Weinman',
      composition: '90% silver, 10% copper',
      mints: ['P', 'D', 'S'],
      history: 'The Walking Liberty half dollar is celebrated for its depiction of Liberty striding toward the rising sun.',
      imageAsset: 'assets/images/series/walking_liberty_half.png',
      thumbnailAsset: 'assets/images/series/walking_liberty_half_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Franklin Half Dollars',
      denomination: 'Half Dollar',
      years: '1948–1963',
      designer: 'John R. Sinnock',
      composition: '90% silver, 10% copper',
      mints: ['P', 'D', 'S'],
      history: 'The Franklin half dollar features Benjamin Franklin on the obverse and the Liberty Bell on the reverse.',
      imageAsset: 'assets/images/series/franklin_half.png',
      thumbnailAsset: 'assets/images/series/franklin_half_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Kennedy Half Dollars',
      denomination: 'Half Dollar',
      years: '1964–Present',
      designer: 'Gilroy Roberts / Frank Gasparro',
      composition: 'Composition has varied since 1964',
      mints: ['P', 'D', 'S'],
      history: 'The Kennedy half dollar was introduced in 1964 as a memorial to President John F. Kennedy.',
      imageAsset: 'assets/images/series/kennedy_half.png',
      thumbnailAsset: 'assets/images/series/kennedy_half_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Flowing Hair Dollars',
      denomination: 'Dollar',
      years: '1794–1795',
      designer: 'Robert Scot',
      composition: 'Silver',
      mints: ['P'],
      history: 'Flowing Hair dollars were the first silver dollars issued by the United States Mint.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/flowing_hair_dollar_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Draped Bust Dollars - Small Eagle',
      denomination: 'Dollar',
      years: '1795–1798',
      designer: 'Robert Scot',
      composition: 'Silver',
      mints: ['P'],
      history: 'Early Draped Bust dollars used the Small Eagle reverse.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/draped_bust_small_eagle_dollar_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Draped Bust Dollars - Heraldic Eagle',
      denomination: 'Dollar',
      years: '1798–1804',
      designer: 'Robert Scot',
      composition: 'Silver',
      mints: ['P'],
      history: 'Later Draped Bust dollars used the Heraldic Eagle reverse.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/draped_bust_heraldic_eagle_dollar_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Gobrecht Dollars',
      denomination: 'Dollar',
      years: '1836–1839',
      designer: 'Christian Gobrecht',
      composition: 'Silver',
      mints: ['P'],
      history: 'Gobrecht dollars were experimental and transitional silver dollars preceding the Liberty Seated series.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/gobrecht_dollar_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Liberty Seated Dollars',
      denomination: 'Dollar',
      years: '1840–1873',
      designer: 'Christian Gobrecht',
      composition: 'Silver',
      mints: ['P', 'O', 'S', 'CC'],
      history: 'Liberty Seated dollars brought Christian Gobrecht’s seated Liberty motif to the silver dollar.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/liberty_seated_dollar_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Trade Dollars',
      denomination: 'Dollar',
      years: '1873–1885',
      designer: 'William Barber',
      composition: '90% silver, 10% copper',
      mints: ['P', 'S', 'CC'],
      history: 'Trade dollars were created primarily for commerce with Asia and were struck from 1873 through 1885.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/trade_dollar_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Morgan Dollars',
      denomination: 'Dollar',
      years: '1878–1921',
      designer: 'George T. Morgan',
      composition: '90% silver, 10% copper',
      mints: ['P', 'CC', 'O', 'S', 'D'],
      history: 'The Morgan dollar is one of the most widely collected United States silver dollar series.',
      imageAsset: 'assets/images/series/morgan_dollar.png',
      thumbnailAsset: 'assets/images/series/morgan_dollar_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Peace Dollars',
      denomination: 'Dollar',
      years: '1921–1935',
      designer: 'Anthony de Francisci',
      composition: '90% silver, 10% copper',
      mints: ['P', 'D', 'S'],
      history: 'The Peace dollar was created to commemorate peace following World War I.',
      imageAsset: 'assets/images/series/peace_dollar.png',
      thumbnailAsset: 'assets/images/series/peace_dollar_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Eisenhower Dollars',
      denomination: 'Dollar',
      years: '1971–1978',
      designer: 'Frank Gasparro',
      composition: 'Copper-nickel clad; silver-clad collector issues',
      mints: ['P', 'D', 'S'],
      history: 'The Eisenhower dollar honored President Dwight D. Eisenhower and celebrated the Apollo 11 moon landing.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/eisenhower_dollar_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Susan B. Anthony Dollars',
      denomination: 'Dollar',
      years: '1979–1981, 1999',
      designer: 'Frank Gasparro',
      composition: 'Copper-nickel clad',
      mints: ['P', 'D', 'S'],
      history: 'The Susan B. Anthony dollar was the first U.S. circulating coin to depict a real historical woman.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/susan_b_anthony_dollar_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Sacagawea Dollars',
      denomination: 'Dollar',
      years: '2000–Present',
      designer: 'Glenna Goodacre and later reverse artists',
      composition: 'Manganese-brass clad',
      mints: ['P', 'D', 'S'],
      history: 'The golden-colored Sacagawea dollar debuted in 2000; rotating Native American reverse designs began in 2009.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/sacagawea_dollar_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Presidential Dollars',
      denomination: 'Dollar',
      years: '2007–2016, 2020',
      designer: 'Various',
      composition: 'Manganese-brass clad',
      mints: ['P', 'D', 'S'],
      history: 'The Presidential \$1 Coin Program honored deceased U.S. presidents in the order they served.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/presidential_dollar_thumb.png',
    ),
    CoinSeriesReference(
      series: 'American Innovation Dollars',
      denomination: 'Dollar',
      years: '2018–2032',
      designer: 'Various',
      composition: 'Manganese-brass clad',
      mints: ['P', 'D', 'S'],
      history: 'The American Innovation \$1 Coin Program honors innovation and innovators from each state, territory, and the District of Columbia.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/innovation_dollar_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Proof Sets',
      denomination: 'Set',
      years: '1936–Present',
      designer: 'Various',
      composition: 'Varies by year',
      mints: ['P', 'S', 'W'],
      history: 'Annual proof sets contain specially struck collector versions of U.S. coinage; production has had historical interruptions.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/proof_set_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Silver Proof Sets',
      denomination: 'Set',
      years: '1992–Present',
      designer: 'Various',
      composition: 'Includes silver versions of selected denominations',
      mints: ['S'],
      history: 'Silver proof sets pair proof-quality coinage with silver versions of selected denominations.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/silver_proof_set_thumb.png',
    ),
    CoinSeriesReference(
      series: 'Mint Sets (Uncirculated)',
      denomination: 'Set',
      years: '1947–Present',
      designer: 'Various',
      composition: 'Varies by year',
      mints: ['P', 'D', 'S', 'W'],
      history: 'Uncirculated Mint Sets package examples of circulating coinage produced for collectors; production has had historical interruptions.',
      imageAsset: '',
      thumbnailAsset: 'assets/images/series/mint_set_thumb.png',
    ),
  ];

  static CoinSeriesReference? find(String seriesName) {
    final normalized = _normalize(seriesName);

    // More specific aliases first.
    if (normalized.contains('classic head') && normalized.contains('1809')) {
      return _byName('Liberty Head Half Cents');
    }
    if (normalized.contains('half cent')) {
      return _byName('Liberty Head Half Cents');
    }

    if (normalized.contains('wreath')) return _byName('Wreath Cents');
    if (normalized.contains('chain')) return _byName('Chain Cents');
    if (normalized.contains('liberty cap') && !normalized.contains('half')) return _byName('Liberty Cap Cents');
    if (normalized.contains('draped bust') && normalized.contains('cent')) return _byName('Draped Bust Cents');
    if (normalized.contains('classic head') && normalized.contains('cent')) return _byName('Classic Head Cents');
    if (normalized.contains('coronet')) return _byName('Coronet Cents');
    if (normalized.contains('flying eagle')) return _byName('Flying Eagle Cents');
    if (normalized.contains('indian') && normalized.contains('cent')) return _byName('Indian Head Cents');
    if ((normalized.contains('lincoln') || normalized.contains('wheat')) && normalized.contains('wheat')) return _byName('Lincoln Wheat Cents');
    if (normalized.contains('lincoln') && normalized.contains('shield')) return _byName('Lincoln Shield Cents');

    if (normalized.contains('two cent') || normalized.contains('2 cent')) return _byName('Two Cent Pieces');
    if ((normalized.contains('three cent') || normalized.contains('3 cent')) && normalized.contains('silver')) return _byName('Three Cent Silver');
    if ((normalized.contains('three cent') || normalized.contains('3 cent')) && normalized.contains('nickel')) return _byName('Three Cent Nickel');

    if (normalized.contains('shield') && (normalized.contains('nickel') || normalized.contains('5 cent'))) return _byName('Shield Nickels');
    if ((normalized.contains('liberty') || normalized.contains('v nickel')) && (normalized.contains('nickel') || normalized.contains('5 cent'))) return _byName('Liberty Head Nickels');
    if (normalized.contains('buffalo')) return _byName('Buffalo Nickels');
    if (normalized.contains('jefferson')) return _byName('Jefferson Nickels');

    if (normalized.contains('half dime')) {
      if (normalized.contains('flowing hair')) return _byName('Flowing Hair Half Dimes');
      if (normalized.contains('small eagle')) return _byName('Draped Bust Half Dimes');
      if (normalized.contains('heraldic')) return _byName('Draped Bust Half Dimes - Heraldic Eagle');
      if (normalized.contains('capped bust')) return _byName('Capped Bust Half Dimes');
      if (normalized.contains('liberty seated')) return _byName('Liberty Seated Half Dimes');
    }

    if (normalized.contains('dime') || normalized.contains('10 cent')) {
      if (normalized.contains('draped bust')) return _byName('Draped Bust Dimes');
      if (normalized.contains('capped bust')) return _byName('Capped Bust Dimes');
      if (normalized.contains('liberty seated')) return _byName('Liberty Seated Dimes');
      if (normalized.contains('barber')) return _byName('Barber Dimes');
      if (normalized.contains('mercury') || normalized.contains('winged liberty')) return _byName('Mercury Dimes');
      if (normalized.contains('roosevelt')) return _byName('Roosevelt Dimes');
    }

    if (normalized.contains('20 cent') || normalized.contains('twenty cent')) return _byName('Liberty Seated Twenty Cent Pieces');

    if (normalized.contains('quarter') || normalized.contains('25 cent')) {
      if (normalized.contains('draped bust')) return _byName('Draped Bust Quarters');
      if (normalized.contains('capped bust')) return _byName('Capped Bust Quarters');
      if (normalized.contains('liberty seated')) return _byName('Liberty Seated Quarters');
      if (normalized.contains('barber')) return _byName('Barber Quarters');
      if (normalized.contains('standing liberty')) return _byName('Standing Liberty Quarters');
      if (normalized.contains('state') || normalized.contains('territor')) return _byName('State & Territory Quarters');
      if (normalized.contains('national park') || normalized.contains('beautiful')) return _byName('America the Beautiful Quarters');
      if (normalized.contains('women')) return _byName('American Women Quarters');
      if (normalized.contains('washington')) return _byName('Washington Quarters');
    }

    if (normalized.contains('half dollar') || normalized.contains('50 cent')) {
      if (normalized.contains('flowing hair')) return _byName('Flowing Hair Half Dollars');
      if (normalized.contains('draped bust')) return _byName('Draped Bust Half Dollars');
      if (normalized.contains('capped bust') && normalized.contains('reed')) return _byName('Capped Bust Half Dollars - Reeded Edge');
      if (normalized.contains('capped bust')) return _byName('Capped Bust Half Dollars');
      if (normalized.contains('liberty seated')) return _byName('Liberty Seated Half Dollars');
      if (normalized.contains('barber')) return _byName('Barber Half Dollars');
      if (normalized.contains('walking liberty')) return _byName('Walking Liberty Half Dollars');
      if (normalized.contains('franklin')) return _byName('Franklin Half Dollars');
      if (normalized.contains('kennedy')) return _byName('Kennedy Half Dollars');
    }

    if (normalized.contains('dollar')) {
      if (normalized.contains('flowing hair')) return _byName('Flowing Hair Dollars');
      if (normalized.contains('draped bust') && normalized.contains('small eagle')) return _byName('Draped Bust Dollars - Small Eagle');
      if (normalized.contains('draped bust') && normalized.contains('heraldic')) return _byName('Draped Bust Dollars - Heraldic Eagle');
      if (normalized.contains('gobrecht')) return _byName('Gobrecht Dollars');
      if (normalized.contains('liberty seated')) return _byName('Liberty Seated Dollars');
      if (normalized.contains('trade')) return _byName('Trade Dollars');
      if (normalized.contains('morgan')) return _byName('Morgan Dollars');
      if (normalized.contains('peace')) return _byName('Peace Dollars');
      if (normalized.contains('eisenhower')) return _byName('Eisenhower Dollars');
      if (normalized.contains('susan') || normalized.contains('anthony')) return _byName('Susan B. Anthony Dollars');
      if (normalized.contains('sacagawea') || normalized.contains('native american')) return _byName('Sacagawea Dollars');
      if (normalized.contains('presidential')) return _byName('Presidential Dollars');
      if (normalized.contains('innovation')) return _byName('American Innovation Dollars');
    }

    if (normalized.contains('silver proof')) return _byName('Silver Proof Sets');
    if (normalized.contains('proof set')) return _byName('Proof Sets');
    if (normalized.contains('mint set') || normalized.contains('uncirculated set')) return _byName('Mint Sets (Uncirculated)');

    // Exact normalized library-name match.
    for (final reference in series) {
      if (_normalize(reference.series) == normalized) return reference;
    }

    // Fallback: compare names after stripping dates and common denomination words.
    final simplifiedInput = _simplify(normalized);
    for (final reference in series) {
      if (_simplify(_normalize(reference.series)) == simplifiedInput) {
        return reference;
      }
    }

    return null;
  }

  static String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _simplify(String value) {
    return value
        .replaceAll(RegExp(r'\b(17|18|19|20)\d{2}\b'), ' ')
        .replaceAll(RegExp(r'\b(one|two|three|five|ten|twenty|twenty five|fifty|half)\b'), ' ')
        .replaceAll(RegExp(r'\b(1|2|3|5|10|20|25|50)\b'), ' ')
        .replaceAll(RegExp(r'\b(cent|cents|nickel|nickels|dime|dimes|quarter|quarters|dollar|dollars|piece|pieces)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static CoinSeriesReference _byName(String name) {
    return series.firstWhere((reference) => reference.series == name);
  }
}

const List<TimelineEvent> morganTimeline = [
  TimelineEvent(
    year: '1878',
    title: 'Morgan Dollar Introduced',
    description:
        'The Morgan Dollar was first struck following the Bland–Allison Act.',
  ),
  TimelineEvent(
    year: '1893',
    title: 'Lowest Mintage',
    description:
        'The 1893-S Morgan Dollar became one of the key dates in the series.',
  ),
  TimelineEvent(
    year: '1904',
    title: 'Production Ends',
    description:
        'Regular production of Morgan Dollars came to an end.',
  ),
  TimelineEvent(
    year: '1921',
    title: 'Final Morgan Dollar',
    description:
        'The Morgan Dollar returned for one final year before the Peace Dollar replaced it.',
  ),
];
