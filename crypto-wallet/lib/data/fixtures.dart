import 'dart:ui';

import 'models.dart';

const walletProfile = WalletProfile(
  username: 'bogdanzhuk',
  address: '7xKXtg...4EpF',
);

const walletAssets = [
  Asset(
    id: TokenId.sol,
    name: 'Solana',
    symbol: 'SOL',
    quantity: 4.85,
    value: 332.94,
    change: -12.2,
  ),
  Asset(
    id: TokenId.usdc,
    name: 'USDC',
    symbol: 'USDC',
    quantity: 237.81,
    value: 237.81,
    change: 0.01,
  ),
  Asset(
    id: TokenId.eth,
    name: 'Ethereum',
    symbol: 'ETH',
    quantity: 0.305,
    value: 570.75,
    change: 18.4,
  ),
];

const tokens = [
  Token(
    id: TokenId.eth,
    name: 'Ethereum',
    symbol: 'ETH',
    network: 'Ethereum',
    color: Color(0xFF627EEA),
    priceUsd: 2437.52,
    balance: 0.305,
    displayDecimals: 4,
    feeUsd: 1.84,
    eta: '~2 min',
  ),
  Token(
    id: TokenId.usdc,
    name: 'USDC',
    symbol: 'USDC',
    network: 'Base',
    color: Color(0xFF2775CA),
    priceUsd: 1,
    balance: 237.81,
    displayDecimals: 2,
    feeUsd: 0.02,
    eta: '~30 sec',
  ),
  Token(
    id: TokenId.btc,
    name: 'Bitcoin',
    symbol: 'BTC',
    network: 'Bitcoin',
    color: Color(0xFFF7931A),
    priceUsd: 67412.2,
    balance: 0.0125,
    displayDecimals: 6,
    feeUsd: 3.1,
    eta: '~25 min',
  ),
  Token(
    id: TokenId.sol,
    name: 'Solana',
    symbol: 'SOL',
    network: 'Solana',
    color: Color(0xFF9945FF),
    priceUsd: 148.32,
    balance: 4.85,
    displayDecimals: 3,
    feeUsd: 0.01,
    eta: '~5 sec',
  ),
];

const networks = [
  Network(
    id: NetworkId.ethereum,
    name: 'Ethereum',
    color: Color(0xFF627EEA),
    address: '0x7f4E2aC8b1e94dD7f21A6c09E14bD24c5a83f9c41',
  ),
  Network(
    id: NetworkId.base,
    name: 'Base',
    color: Color(0xFF0052FF),
    address: '0x7f4E2aC8b1e94dD7f21A6c09E14bD24c5a83f9c41',
  ),
  Network(
    id: NetworkId.solana,
    name: 'Solana',
    color: Color(0xFF9945FF),
    address: '7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU',
  ),
  Network(
    id: NetworkId.polygon,
    name: 'Polygon',
    color: Color(0xFF8247E5),
    address: '0x7f4E2aC8b1e94dD7f21A6c09E14bD24c5a83f9c41',
  ),
];

const recentRecipients = [
  Recipient(
    id: 'maya',
    name: 'maya.eth',
    address: '0x3F2aC8b1e94dD7f21A6c09E14bD24c5a83f09c41',
    verified: true,
    gradient: (Color(0xFFB9A6F5), Color(0xFF7A5CF0)),
  ),
  Recipient(
    id: 'kofi',
    name: 'kofi.eth',
    address: '0x8C4dE2a91bF07c3341D6b88A5e2f19cD40aB1B2e',
    verified: true,
    gradient: (Color(0xFFF3B8DC), Color(0xFFE86AA6)),
  ),
  Recipient(
    id: 'lena',
    name: 'lena.eth',
    address: '0xA1f49C7d20E85b6634cB90D1f5a8E27b93cD55f8',
    verified: true,
    gradient: (Color(0xFFA6D8F5), Color(0xFF4A90E2)),
  ),
  Recipient(
    id: 'ade',
    name: 'ade.eth',
    address: '0x5E92bD4Fa8C1073Fa2261B09E7cD84a51Bf47A93',
    verified: true,
    gradient: (Color(0xFFF5D6A6), Color(0xFFF0A35C)),
  ),
  Recipient(
    id: 'vault',
    name: 'Vault',
    address: '0xD70b3E6a54F28C91b4A3fE0862dC11a97E64C8d5',
    verified: false,
    gradient: (Color(0xFFC4C9D4), Color(0xFF8A93A6)),
  ),
];

const pastedRecipient = Recipient(
  id: 'pasted',
  name: 'bogdan.eth',
  address: '0x7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU',
  verified: true,
  gradient: (Color(0xFF9BE8C5), Color(0xFF2FB57E)),
);

const incomingTransactions = [
  IncomingTransaction(
    id: 'tx1',
    from: 'maya.eth',
    amount: '+0.42 ETH',
    fiat: '\$1,023.76',
    time: '2h ago',
  ),
  IncomingTransaction(
    id: 'tx2',
    from: 'kofi.eth',
    amount: '+120 USDC',
    fiat: '\$120.00',
    time: 'Yesterday',
  ),
  IncomingTransaction(
    id: 'tx3',
    from: '0x8C4d…1B2e',
    amount: '+0.85 SOL',
    fiat: '\$126.07',
    time: 'Jul 12',
  ),
];

const featuredIpo = Ipo(
  id: 'novagrid',
  company: 'NovaGrid',
  ticker: 'NVGD',
  industry: 'Clean Energy',
  sector: 'Renewable Infrastructure',
  exchange: 'NASDAQ',
  monogram: 'N',
  gradient: (Color(0xFF7B61FF), Color(0xFF4B33D6)),
  status: IpoStatus.open,
  listingDate: 'Jul 28, 2026',
  countdown: Duration(days: 12, hours: 4, minutes: 32),
  priceLow: 28,
  priceHigh: 34,
  demandPercent: 87,
  valuation: '\$12.4B',
  raise: '\$1.8B',
  underwriters: 'Morgan Stanley · Goldman Sachs',
  description:
      'NovaGrid builds distributed battery networks that turn homes and businesses into a single virtual power plant, balancing the grid in real time.',
  marketOpportunity:
      'Grid-scale storage demand is projected to grow 6x by 2032 as renewables pass 40% of generation. NovaGrid operates in 14 states with utility partnerships covering 31M households.',
  financialHighlights:
      'Revenue grew 118% year over year to \$842M with 61% gross margin. The company turned profitable in Q3 2025 and holds \$1.1B in contracted backlog.',
  growthMetrics:
      'Deployed capacity doubled to 4.2 GWh, retention across utility contracts is 98%, and software attach revenue now represents 34% of total sales.',
  details: [
    IpoDetail(
      id: 'valuation',
      label: 'Expected Valuation',
      value: '\$12.4B',
      icon: 'bar-chart-2',
    ),
    IpoDetail(
      id: 'raise',
      label: 'Expected Raise',
      value: '\$1.8B',
      icon: 'download',
    ),
    IpoDetail(
      id: 'underwriters',
      label: 'Lead Underwriters',
      value: 'Morgan Stanley · Goldman Sachs',
      icon: 'briefcase',
    ),
    IpoDetail(
      id: 'sector',
      label: 'Sector',
      value: 'Renewable Infrastructure',
      icon: 'zap',
    ),
    IpoDetail(
      id: 'exchange',
      label: 'Exchange',
      value: 'NASDAQ',
      icon: 'globe',
    ),
  ],
  metrics: [
    IpoMetric(id: 'revenue', label: 'Revenue', value: '\$842M', hint: '+118% YoY'),
    IpoMetric(id: 'profit', label: 'Net Profit', value: '\$118M', hint: '14% margin'),
    IpoMetric(
      id: 'marketcap',
      label: 'Market Cap',
      value: '\$12.4B',
      hint: 'at midpoint',
    ),
    IpoMetric(id: 'employees', label: 'Employees', value: '4,300', hint: '14 states'),
    IpoMetric(id: 'founded', label: 'Founded', value: '2016', hint: 'Austin, TX'),
    IpoMetric(id: 'backlog', label: 'Backlog', value: '\$1.1B', hint: 'contracted'),
  ],
  timeline: [
    IpoTimelineEvent(
      id: 'founded',
      year: '2016',
      title: 'Founded',
      detail: 'Started in Austin by two grid engineers',
    ),
    IpoTimelineEvent(
      id: 'seed',
      year: '2017',
      title: 'Seed',
      detail: '\$4.5M to build the first pilot network',
    ),
    IpoTimelineEvent(
      id: 'series-a',
      year: '2019',
      title: 'Series A',
      detail: '\$38M led by Breakthrough Energy',
    ),
    IpoTimelineEvent(
      id: 'series-b',
      year: '2021',
      title: 'Series B',
      detail: '\$210M as capacity passed 1 GWh',
    ),
    IpoTimelineEvent(
      id: 'series-c',
      year: '2023',
      title: 'Series C',
      detail: '\$480M at a \$6.2B valuation',
    ),
    IpoTimelineEvent(
      id: 'ipo',
      year: '2026',
      title: 'IPO',
      detail: 'Listing on NASDAQ as NVGD',
    ),
  ],
  minInvestment: 100,
  maxInvestment: 25000,
);

const relatedIpos = [
  RelatedIpo(
    id: 'lumenbio',
    company: 'Lumen Bio',
    ticker: 'LMNB',
    industry: 'Biotech',
    monogram: 'L',
    gradient: (Color(0xFFF3B8DC), Color(0xFFD9589F)),
    daysLeft: 19,
    raise: '\$640M',
  ),
  RelatedIpo(
    id: 'arcadia',
    company: 'Arcadia Labs',
    ticker: 'ARCL',
    industry: 'AI Infrastructure',
    monogram: 'A',
    gradient: (Color(0xFF9BE8C5), Color(0xFF1F9D6C)),
    daysLeft: 26,
    raise: '\$2.3B',
  ),
  RelatedIpo(
    id: 'solace',
    company: 'Solace',
    ticker: 'SOLC',
    industry: 'Fintech',
    monogram: 'S',
    gradient: (Color(0xFFA6D8F5), Color(0xFF2E7CC7)),
    daysLeft: 34,
    raise: '\$920M',
  ),
  RelatedIpo(
    id: 'helio',
    company: 'Helio Dynamics',
    ticker: 'HELD',
    industry: 'Aerospace',
    monogram: 'H',
    gradient: (Color(0xFFF5D6A6), Color(0xFFDE8A2E)),
    daysLeft: 41,
    raise: '\$1.2B',
  ),
];
