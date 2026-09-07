import 'dart:ui';

enum TokenId { eth, usdc, btc, sol }

enum NetworkId { ethereum, base, solana, polygon }

enum IpoStatus { open, upcoming, closed }

enum AllocationTier {
  high('High'),
  medium('Medium'),
  low('Low');

  const AllocationTier(this.label);
  final String label;
}

enum SwapVenue {
  jupiter('Jupiter'),
  uniswap('Uniswap');

  const SwapVenue(this.label);
  final String label;
}

enum SwapSlot { a, b }

/// Two gradient stops.
typedef GradientPair = (Color, Color);

class Gain {
  const Gain({required this.amount, required this.percent});
  final double amount;
  final double percent;
}

class Asset {
  const Asset({
    required this.id,
    required this.name,
    required this.symbol,
    required this.quantity,
    required this.value,
    required this.change,
  });
  final TokenId id;
  final String name;
  final String symbol;
  final double quantity;
  final double value;
  final double change;
}

class WalletProfile {
  const WalletProfile({required this.username, required this.address});
  final String username;
  final String address;
}

class Token {
  const Token({
    required this.id,
    required this.name,
    required this.symbol,
    required this.network,
    required this.color,
    required this.priceUsd,
    required this.balance,
    required this.displayDecimals,
    required this.feeUsd,
    required this.eta,
  });
  final TokenId id;
  final String name;
  final String symbol;
  final String network;
  final Color color;
  final double priceUsd;
  final double balance;
  final int displayDecimals;
  final double feeUsd;
  final String eta;
}

class Network {
  const Network({
    required this.id,
    required this.name,
    required this.color,
    required this.address,
  });
  final NetworkId id;
  final String name;
  final Color color;
  final String address;
}

class Recipient {
  const Recipient({
    required this.id,
    required this.name,
    required this.address,
    required this.verified,
    required this.gradient,
  });
  final String id;
  final String name;
  final String address;
  final bool verified;
  final GradientPair gradient;
}

class IncomingTransaction {
  const IncomingTransaction({
    required this.id,
    required this.from,
    required this.amount,
    required this.fiat,
    required this.time,
  });
  final String id;
  final String from;
  final String amount;
  final String fiat;
  final String time;
}

class IpoTimelineEvent {
  const IpoTimelineEvent({
    required this.id,
    required this.year,
    required this.title,
    required this.detail,
  });
  final String id;
  final String year;
  final String title;
  final String detail;
}

class IpoMetric {
  const IpoMetric({
    required this.id,
    required this.label,
    required this.value,
    required this.hint,
  });
  final String id;
  final String label;
  final String value;
  final String hint;
}

class IpoDetail {
  const IpoDetail({
    required this.id,
    required this.label,
    required this.value,
    required this.icon,
  });
  final String id;
  final String label;
  final String value;
  final String icon;
}

class Ipo {
  const Ipo({
    required this.id,
    required this.company,
    required this.ticker,
    required this.industry,
    required this.sector,
    required this.exchange,
    required this.monogram,
    required this.gradient,
    required this.status,
    required this.listingDate,
    required this.countdown,
    required this.priceLow,
    required this.priceHigh,
    required this.demandPercent,
    required this.valuation,
    required this.raise,
    required this.underwriters,
    required this.description,
    required this.marketOpportunity,
    required this.financialHighlights,
    required this.growthMetrics,
    required this.details,
    required this.metrics,
    required this.timeline,
    required this.minInvestment,
    required this.maxInvestment,
  });
  final String id;
  final String company;
  final String ticker;
  final String industry;
  final String sector;
  final String exchange;
  final String monogram;
  final GradientPair gradient;
  final IpoStatus status;
  final String listingDate;
  final Duration countdown;
  final int priceLow;
  final int priceHigh;
  final double demandPercent;
  final String valuation;
  final String raise;
  final String underwriters;
  final String description;
  final String marketOpportunity;
  final String financialHighlights;
  final String growthMetrics;
  final List<IpoDetail> details;
  final List<IpoMetric> metrics;
  final List<IpoTimelineEvent> timeline;
  final int minInvestment;
  final int maxInvestment;
}

class RelatedIpo {
  const RelatedIpo({
    required this.id,
    required this.company,
    required this.ticker,
    required this.industry,
    required this.monogram,
    required this.gradient,
    required this.daysLeft,
    required this.raise,
  });
  final String id;
  final String company;
  final String ticker;
  final String industry;
  final String monogram;
  final GradientPair gradient;
  final int daysLeft;
  final String raise;
}

class SwapQuote {
  const SwapQuote({
    required this.toAmount,
    required this.rate,
    required this.feeUsd,
    required this.priceImpact,
    required this.networkFeeUsd,
    required this.minReceived,
  });
  final double toAmount;
  final double rate;
  final double feeUsd;
  final double priceImpact;
  final double networkFeeUsd;
  final double minReceived;
}

class AllocationEstimate {
  const AllocationEstimate({
    required this.shares,
    required this.allocationPercent,
    required this.totalUsd,
    required this.tier,
    required this.tierScore,
  });
  final int shares;
  final int allocationPercent;
  final double totalUsd;
  final AllocationTier tier;
  final double tierScore;
}

class CountdownParts {
  const CountdownParts({
    required this.days,
    required this.hours,
    required this.minutes,
  });
  final String days;
  final String hours;
  final String minutes;
}
