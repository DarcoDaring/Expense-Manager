import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One pickable icon: a coloured Material icon, or a brand-style badge (a
/// solid coloured tile holding a glyph or a few letters).
class AppIconSpec {
  final String name;
  final String group;
  final Color color;
  final IconData? icon;
  final String? label;

  /// Brands are drawn as a solid badge; plain icons take a tinted background.
  final bool badge;
  final Color fg;

  /// The brand's real logo, from [asset] (an SVG when [svg], else a PNG).
  /// [color] is the tile behind an SVG; PNG logos fill the tile themselves.
  final String? asset;
  final bool svg;

  const AppIconSpec.plain(this.name, this.group, IconData this.icon, this.color)
      : label = null,
        badge = false,
        asset = null,
        svg = false,
        fg = const Color(0xFFFFFFFF);

  const AppIconSpec.glyph(this.name, this.group, IconData this.icon, this.color,
      {this.fg = const Color(0xFFFFFFFF)})
      : label = null,
        badge = true,
        asset = null,
        svg = false;

  const AppIconSpec.text(this.name, this.group, String this.label, this.color,
      {this.fg = const Color(0xFFFFFFFF)})
      : icon = null,
        badge = true,
        asset = null,
        svg = false;

  const AppIconSpec.logo(this.name, this.group, String this.asset,
      {this.svg = false, Color bg = const Color(0xFFFFFFFF)})
      : color = bg,
        icon = null,
        label = null,
        badge = true,
        fg = const Color(0xFFFFFFFF);
}

const _gEveryday = 'Everyday';
const _gFood = 'Food & shopping';
const _gTransport = 'Transport';
const _gHome = 'Home & bills';
const _gHealth = 'Health & care';
const _gFun = 'Fun & travel';
const _gMoney = 'Money & loans';
const _gStream = 'Streaming & music';
const _gSocial = 'Social & tech';
const _gTelecom = 'Telecom';
const _gApps = 'Apps & delivery';
const _gBanks = 'Banks & cards';

/// Group order in the icon picker.
const List<String> kIconGroups = [
  _gEveryday,
  _gFood,
  _gTransport,
  _gHome,
  _gHealth,
  _gFun,
  _gMoney,
  _gStream,
  _gSocial,
  _gTelecom,
  _gApps,
  _gBanks,
];

/// Icons users can pick for categories, subscriptions, EMIs and payment modes.
/// Only the index is persisted, so the list must stay append-only.
const List<AppIconSpec> kIcons = [
  AppIconSpec.plain('Restaurant', _gFood, Icons.restaurant_rounded, Color(0xFFF97316)), // 0
  AppIconSpec.plain('Car', _gTransport, Icons.directions_car_rounded, Color(0xFF0EA5E9)),
  AppIconSpec.plain('Shopping', _gFood, Icons.shopping_bag_rounded, Color(0xFFEC4899)),
  AppIconSpec.plain('Bills', _gHome, Icons.receipt_long_rounded, Color(0xFF6366F1)),
  AppIconSpec.plain('Favourite', _gEveryday, Icons.favorite_rounded, Color(0xFFEF4444)),
  AppIconSpec.plain('Movies', _gFun, Icons.movie_rounded, Color(0xFF8B5CF6)),
  AppIconSpec.plain('Home', _gHome, Icons.home_rounded, Color(0xFF14B8A6)),
  AppIconSpec.plain('Education', _gEveryday, Icons.school_rounded, Color(0xFFF59E0B)),
  AppIconSpec.plain('Flight', _gFun, Icons.flight_rounded, Color(0xFF38BDF8)),
  AppIconSpec.plain('Fuel', _gTransport, Icons.local_gas_station_rounded, Color(0xFFEA580C)),
  AppIconSpec.plain('Pets', _gEveryday, Icons.pets_rounded, Color(0xFFA16207)),
  AppIconSpec.plain('Gifts', _gEveryday, Icons.card_giftcard_rounded, Color(0xFFF472B6)),
  AppIconSpec.plain('Fitness', _gHealth, Icons.fitness_center_rounded, Color(0xFF22C55E)),
  AppIconSpec.plain('Phone', _gTelecom, Icons.phone_android_rounded, Color(0xFF3B82F6)),
  AppIconSpec.plain('Coffee', _gFood, Icons.coffee_rounded, Color(0xFF92400E)),
  AppIconSpec.plain('Other', _gEveryday, Icons.category_rounded, Color(0xFF64748B)),
  AppIconSpec.plain('Cash', _gMoney, Icons.payments_rounded, Color(0xFF22C55E)), // 16
  AppIconSpec.plain('Credit card', _gBanks, Icons.credit_card_rounded, Color(0xFFA855F7)),
  AppIconSpec.plain('Bank', _gBanks, Icons.account_balance_rounded, Color(0xFF3B82F6)),
  AppIconSpec.plain('UPI / QR', _gBanks, Icons.qr_code_2_rounded, Color(0xFF14B8A6)),
  AppIconSpec.plain('Wallet', _gBanks, Icons.account_balance_wallet_rounded, Color(0xFFF59E0B)),
  AppIconSpec.plain('Tap to pay', _gBanks, Icons.contactless_rounded, Color(0xFF0EA5E9)),
  // Subscriptions.
  AppIconSpec.plain('Subscription', _gStream, Icons.subscriptions_rounded, Color(0xFF6366F1)), // 22
  AppIconSpec.plain('TV', _gStream, Icons.tv_rounded, Color(0xFFEF4444)),
  AppIconSpec.plain('Music', _gStream, Icons.music_note_rounded, Color(0xFFEC4899)),
  AppIconSpec.plain('Cloud', _gSocial, Icons.cloud_rounded, Color(0xFF0EA5E9)),
  AppIconSpec.plain('Wi-Fi', _gHome, Icons.wifi_rounded, Color(0xFF3B82F6)),
  AppIconSpec.plain('Electricity', _gHome, Icons.bolt_rounded, Color(0xFFFACC15)),
  AppIconSpec.plain('Water', _gHome, Icons.water_drop_rounded, Color(0xFF06B6D4)),
  AppIconSpec.plain('Security', _gSocial, Icons.security_rounded, Color(0xFF22C55E)),
  AppIconSpec.plain('Gaming', _gFun, Icons.sports_esports_rounded, Color(0xFF8B5CF6)),
  AppIconSpec.plain('News', _gSocial, Icons.newspaper_rounded, Color(0xFF475569)),
  AppIconSpec.plain('Rent', _gHome, Icons.apartment_rounded, Color(0xFF0D9488)),
  AppIconSpec.plain('Car service', _gTransport, Icons.car_repair_rounded, Color(0xFFF97316)),
  AppIconSpec.plain('Medicine', _gHealth, Icons.medication_rounded, Color(0xFFEF4444)),
  AppIconSpec.plain('Kids', _gEveryday, Icons.child_care_rounded, Color(0xFFF472B6)),
  AppIconSpec.plain('Savings', _gMoney, Icons.savings_rounded, Color(0xFF16A34A)), // 36
  // ---- Added later (append only) ----
  // Food & shopping
  AppIconSpec.plain('Groceries', _gFood, Icons.shopping_cart_rounded, Color(0xFF16A34A)), // 37
  AppIconSpec.plain('Fast food', _gFood, Icons.fastfood_rounded, Color(0xFFF97316)),
  AppIconSpec.plain('Snacks', _gFood, Icons.bakery_dining_rounded, Color(0xFFD97706)),
  AppIconSpec.plain('Drinks', _gFood, Icons.local_bar_rounded, Color(0xFF9333EA)),
  AppIconSpec.plain('Clothes', _gFood, Icons.checkroom_rounded, Color(0xFFA855F7)),
  AppIconSpec.plain('Electronics', _gFood, Icons.devices_rounded, Color(0xFF3B82F6)),
  AppIconSpec.plain('Headphones', _gFood, Icons.headphones_rounded, Color(0xFFEC4899)),
  AppIconSpec.plain('Furniture', _gFood, Icons.chair_rounded, Color(0xFFB45309)),
  // Transport
  AppIconSpec.plain('Taxi', _gTransport, Icons.local_taxi_rounded, Color(0xFFEAB308)),
  AppIconSpec.plain('Bus', _gTransport, Icons.directions_bus_rounded, Color(0xFF2563EB)),
  AppIconSpec.plain('Train', _gTransport, Icons.train_rounded, Color(0xFF0891B2)),
  AppIconSpec.plain('Bike', _gTransport, Icons.two_wheeler_rounded, Color(0xFFEF4444)),
  AppIconSpec.plain('EV charging', _gTransport, Icons.ev_station_rounded, Color(0xFF16A34A)),
  AppIconSpec.plain('Parking', _gTransport, Icons.local_parking_rounded, Color(0xFF3B82F6)),
  AppIconSpec.plain('Toll', _gTransport, Icons.toll_rounded, Color(0xFF64748B)),
  // Home & bills
  AppIconSpec.plain('Gas cylinder', _gHome, Icons.propane_tank_rounded, Color(0xFFEA580C)),
  AppIconSpec.plain('Electrical', _gHome, Icons.electrical_services_rounded, Color(0xFFF59E0B)),
  AppIconSpec.plain('Repairs', _gHome, Icons.home_repair_service_rounded, Color(0xFF78716C)),
  AppIconSpec.plain('Cleaning', _gHome, Icons.cleaning_services_rounded, Color(0xFF06B6D4)),
  AppIconSpec.plain('Laundry', _gHome, Icons.local_laundry_service_rounded, Color(0xFF0EA5E9)),
  AppIconSpec.plain('Maid / help', _gHome, Icons.cleaning_services_outlined, Color(0xFF14B8A6)),
  AppIconSpec.plain('Maintenance', _gHome, Icons.handyman_rounded, Color(0xFFF97316)),
  // Health & care
  AppIconSpec.plain('Hospital', _gHealth, Icons.local_hospital_rounded, Color(0xFFEF4444)),
  AppIconSpec.plain('Insurance', _gHealth, Icons.health_and_safety_rounded, Color(0xFF0EA5E9)),
  AppIconSpec.plain('Salon / spa', _gHealth, Icons.spa_rounded, Color(0xFFEC4899)),
  AppIconSpec.plain('Haircut', _gHealth, Icons.content_cut_rounded, Color(0xFF8B5CF6)),
  AppIconSpec.plain('Yoga', _gHealth, Icons.self_improvement_rounded, Color(0xFF14B8A6)),
  // Fun & travel
  AppIconSpec.plain('Hotel', _gFun, Icons.hotel_rounded, Color(0xFF6366F1)),
  AppIconSpec.plain('Holiday', _gFun, Icons.beach_access_rounded, Color(0xFFF59E0B)),
  AppIconSpec.plain('Luggage', _gFun, Icons.luggage_rounded, Color(0xFF92400E)),
  AppIconSpec.plain('Party', _gFun, Icons.celebration_rounded, Color(0xFFEC4899)),
  AppIconSpec.plain('Sports', _gFun, Icons.sports_cricket_rounded, Color(0xFF22C55E)),
  AppIconSpec.plain('Books', _gFun, Icons.menu_book_rounded, Color(0xFF2563EB)),
  AppIconSpec.plain('Events', _gFun, Icons.event_rounded, Color(0xFFEF4444)),
  AppIconSpec.plain('Flowers', _gFun, Icons.local_florist_rounded, Color(0xFFF43F5E)),
  AppIconSpec.plain('Toys', _gFun, Icons.toys_rounded, Color(0xFFF59E0B)),
  // Money & loans
  AppIconSpec.plain('Loan', _gMoney, Icons.request_quote_rounded, Color(0xFF6366F1)),
  AppIconSpec.plain('Home loan', _gMoney, Icons.house_rounded, Color(0xFF0D9488)),
  AppIconSpec.plain('Credit score', _gMoney, Icons.credit_score_rounded, Color(0xFF22C55E)),
  AppIconSpec.plain('Interest', _gMoney, Icons.percent_rounded, Color(0xFFF59E0B)),
  AppIconSpec.plain('Investments', _gMoney, Icons.trending_up_rounded, Color(0xFF16A34A)),
  AppIconSpec.plain('Stocks', _gMoney, Icons.show_chart_rounded, Color(0xFF2563EB)),
  AppIconSpec.plain('Crypto', _gMoney, Icons.currency_bitcoin_rounded, Color(0xFFF7931A)),
  AppIconSpec.plain('Rupee', _gMoney, Icons.currency_rupee_rounded, Color(0xFF22C55E)),
  AppIconSpec.plain('Business', _gMoney, Icons.business_center_rounded, Color(0xFF475569)),
  AppIconSpec.plain('Salary', _gMoney, Icons.work_rounded, Color(0xFF3B82F6)),
  AppIconSpec.plain('Donation', _gMoney, Icons.volunteer_activism_rounded, Color(0xFFEF4444)),
  AppIconSpec.plain('Membership', _gMoney, Icons.card_membership_rounded, Color(0xFF8B5CF6)),
  AppIconSpec.plain('Tax', _gMoney, Icons.account_balance_outlined, Color(0xFF64748B)),
  // Streaming & music (brands)
  AppIconSpec.logo('Netflix', _gStream, 'assets/brands/netflix.svg', svg: true),
  AppIconSpec.logo('YouTube', _gStream, 'assets/brands/youtube.svg', svg: true),
  AppIconSpec.logo('Prime Video', _gStream, 'assets/brands/primevideo.svg', svg: true),
  AppIconSpec.logo('Disney+', _gStream, 'assets/brands/disney.png'),
  AppIconSpec.logo('Hotstar', _gStream, 'assets/brands/hotstar.png'),
  AppIconSpec.logo('JioCinema', _gStream, 'assets/brands/jiocinema.png'),
  AppIconSpec.logo('Zee5', _gStream, 'assets/brands/zee5.png'),
  AppIconSpec.logo('SonyLIV', _gStream, 'assets/brands/sonyliv.png'),
  AppIconSpec.logo('Spotify', _gStream, 'assets/brands/spotify.svg', svg: true),
  AppIconSpec.logo('Apple Music', _gStream, 'assets/brands/applemusic.svg', svg: true),
  AppIconSpec.logo('YouTube Music', _gStream, 'assets/brands/youtubemusic.svg', svg: true),
  AppIconSpec.logo('Gaana', _gStream, 'assets/brands/gaana.png'),
  AppIconSpec.logo('JioSaavn', _gStream, 'assets/brands/jiosaavn.png'),
  AppIconSpec.logo('Twitch', _gStream, 'assets/brands/twitch.svg', svg: true),
  // Social & tech (brands)
  AppIconSpec.logo('Instagram', _gSocial, 'assets/brands/instagram.svg', svg: true),
  AppIconSpec.logo('Facebook', _gSocial, 'assets/brands/facebook.svg', svg: true),
  AppIconSpec.logo('WhatsApp', _gSocial, 'assets/brands/whatsapp.svg', svg: true),
  AppIconSpec.logo('X (Twitter)', _gSocial, 'assets/brands/x.svg', svg: true),
  AppIconSpec.logo('LinkedIn', _gSocial, 'assets/brands/linkedin.svg', svg: true),
  AppIconSpec.logo('Snapchat', _gSocial, 'assets/brands/snapchat.svg', svg: true, bg: Color(0xFFFFFC00)),
  AppIconSpec.logo('Telegram', _gSocial, 'assets/brands/telegram.svg', svg: true),
  AppIconSpec.logo('Discord', _gSocial, 'assets/brands/discord.svg', svg: true),
  AppIconSpec.logo('Reddit', _gSocial, 'assets/brands/reddit.svg', svg: true),
  AppIconSpec.logo('Pinterest', _gSocial, 'assets/brands/pinterest.svg', svg: true),
  AppIconSpec.logo('Google', _gSocial, 'assets/brands/google.svg', svg: true),
  AppIconSpec.logo('Google One', _gSocial, 'assets/brands/google_one.png'),
  AppIconSpec.logo('iCloud', _gSocial, 'assets/brands/icloud.svg', svg: true),
  AppIconSpec.logo('Microsoft 365', _gSocial, 'assets/brands/microsoftoffice.svg', svg: true),
  AppIconSpec.logo('Apple', _gSocial, 'assets/brands/apple.svg', svg: true),
  AppIconSpec.logo('Amazon', _gSocial, 'assets/brands/amazon.svg', svg: true),
  AppIconSpec.logo('Dropbox', _gSocial, 'assets/brands/dropbox.svg', svg: true),
  AppIconSpec.logo('ChatGPT', _gSocial, 'assets/brands/openai.svg', svg: true),
  AppIconSpec.logo('Claude', _gSocial, 'assets/brands/claude.svg', svg: true),
  AppIconSpec.logo('Adobe', _gSocial, 'assets/brands/adobe.svg', svg: true),
  AppIconSpec.logo('Canva', _gSocial, 'assets/brands/canva.svg', svg: true),
  AppIconSpec.logo('Notion', _gSocial, 'assets/brands/notion.svg', svg: true),
  AppIconSpec.logo('GitHub', _gSocial, 'assets/brands/github.svg', svg: true),
  AppIconSpec.logo('PlayStation', _gSocial, 'assets/brands/playstation.svg', svg: true),
  AppIconSpec.logo('Xbox', _gSocial, 'assets/brands/xbox.svg', svg: true),
  AppIconSpec.logo('Google Play', _gSocial, 'assets/brands/googleplay.svg', svg: true),
  // Telecom (brands)
  AppIconSpec.logo('Jio', _gTelecom, 'assets/brands/jio.svg', svg: true),
  AppIconSpec.logo('Airtel', _gTelecom, 'assets/brands/airtel.svg', svg: true),
  AppIconSpec.logo('Vi', _gTelecom, 'assets/brands/vi.png'),
  AppIconSpec.text('BSNL', _gTelecom, 'B', Color(0xFF1E40AF)),
  AppIconSpec.logo('Tata Play', _gTelecom, 'assets/brands/tata_play.png'),
  AppIconSpec.plain('Recharge', _gTelecom, Icons.mobile_friendly_rounded, Color(0xFF22C55E)),
  AppIconSpec.plain('Broadband', _gTelecom, Icons.router_rounded, Color(0xFF3B82F6)),
  AppIconSpec.plain('DTH', _gTelecom, Icons.settings_input_antenna_rounded, Color(0xFFF97316)),
  // Apps & delivery (brands)
  AppIconSpec.logo('Swiggy', _gApps, 'assets/brands/swiggy.svg', svg: true),
  AppIconSpec.logo('Zomato', _gApps, 'assets/brands/zomato.svg', svg: true),
  AppIconSpec.logo('Blinkit', _gApps, 'assets/brands/blinkit.png'),
  AppIconSpec.logo('Zepto', _gApps, 'assets/brands/zepto.png'),
  AppIconSpec.logo('BigBasket', _gApps, 'assets/brands/bigbasket.svg', svg: true),
  AppIconSpec.logo('Flipkart', _gApps, 'assets/brands/flipkart.svg', svg: true),
  AppIconSpec.logo('Myntra', _gApps, 'assets/brands/myntra.png'),
  AppIconSpec.logo('Uber', _gApps, 'assets/brands/uber.svg', svg: true),
  AppIconSpec.text('Ola', _gApps, 'Ola', Color(0xFF2D2D2D)),
  AppIconSpec.logo('Rapido', _gApps, 'assets/brands/rapido.png'),
  AppIconSpec.text('IRCTC', _gApps, 'IR', Color(0xFF1E3A8A)),
  AppIconSpec.logo('MakeMyTrip', _gApps, 'assets/brands/makemytrip.png'),
  // Banks & cards (brands)
  AppIconSpec.logo('Paytm', _gBanks, 'assets/brands/paytm.svg', svg: true),
  AppIconSpec.logo('PhonePe', _gBanks, 'assets/brands/phonepe.svg', svg: true),
  AppIconSpec.logo('Google Pay', _gBanks, 'assets/brands/googlepay.svg', svg: true),
  AppIconSpec.logo('Amazon Pay', _gBanks, 'assets/brands/amazonpay.svg', svg: true),
  AppIconSpec.logo('CRED', _gBanks, 'assets/brands/cred.png'),
  AppIconSpec.logo('Slice', _gBanks, 'assets/brands/slice.png'),
  AppIconSpec.logo('Visa', _gBanks, 'assets/brands/visa.svg', svg: true),
  AppIconSpec.logo('Mastercard', _gBanks, 'assets/brands/mastercard.svg', svg: true),
  AppIconSpec.logo('RuPay', _gBanks, 'assets/brands/rupay.png'),
  AppIconSpec.logo('HDFC', _gBanks, 'assets/brands/hdfcbank.svg', svg: true),
  AppIconSpec.logo('ICICI', _gBanks, 'assets/brands/icicibank.svg', svg: true),
  AppIconSpec.text('SBI', _gBanks, 'SBI', Color(0xFF1D4F9F)),
  AppIconSpec.logo('Axis', _gBanks, 'assets/brands/axisbank.svg', svg: true),
  AppIconSpec.logo('Kotak', _gBanks, 'assets/brands/kotak.png'),
  AppIconSpec.text('Federal', _gBanks, 'F', Color(0xFFFDB913), fg: Color(0xFF111111)),
  AppIconSpec.text('PNB', _gBanks, 'PNB', Color(0xFFA6192E)),
  AppIconSpec.logo('Bank of Baroda', _gBanks, 'assets/brands/bank_of_baroda.png'),
  AppIconSpec.text('Yes Bank', _gBanks, 'Y', Color(0xFF0066B3)),
  AppIconSpec.logo('IDFC First', _gBanks, 'assets/brands/idfc_first.png'),
  AppIconSpec.logo('IndusInd', _gBanks, 'assets/brands/indusind.png'),
  AppIconSpec.logo('Canara', _gBanks, 'assets/brands/canara.png'),
  AppIconSpec.text('Union Bank', _gBanks, 'U', Color(0xFFD71920)),
];

AppIconSpec iconSpec(int i) => kIcons[i.clamp(0, kIcons.length - 1)];

/// Default icon for a new subscription (Icons.subscriptions_rounded).
const int kSubscriptionIcon = 22;

const List<Color> kPalette = [
  Color(0xFF6366F1),
  Color(0xFF14B8A6),
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
  Color(0xFFEC4899),
  Color(0xFF8B5CF6),
  Color(0xFF0EA5E9),
  Color(0xFF22C55E),
  Color(0xFFF97316),
  Color(0xFF64748B),
];

class Category {
  final int? id;
  final String name;
  final int icon;
  final int color;

  /// 0 for an expense category, 1 for an income category.
  final int kind;

  const Category(
      {this.id, required this.name, required this.icon, required this.color, this.kind = 0});

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as int,
        name: m['name'] as String,
        icon: m['icon'] as int,
        color: m['color'] as int,
        kind: (m['kind'] as int?) ?? 0,
      );

  Map<String, Object?> toMap() =>
      {'id': id, 'name': name, 'icon': icon, 'color': color, 'kind': kind};
}

class PaymentMode {
  final int? id;
  final String name;
  final int icon;

  /// The account this mode draws from, or null when it is not linked to one.
  final int? accountId;

  const PaymentMode({this.id, required this.name, required this.icon, this.accountId});

  factory PaymentMode.fromMap(Map<String, Object?> m) => PaymentMode(
        id: m['id'] as int,
        name: m['name'] as String,
        icon: m['icon'] as int,
        accountId: m['account_id'] as int?,
      );

  Map<String, Object?> toMap() =>
      {'id': id, 'name': name, 'icon': icon, 'account_id': accountId};
}

enum AccountType {
  cash('Cash', 'Cash'),
  bank('Bank Account', 'Bank Accounts'),
  wallet('Wallet', 'Wallets'),
  credit('Credit Card', 'Credit Cards');

  final String label;
  final String plural;
  const AccountType(this.label, this.plural);
}

/// A place money lives: cash, a bank account, a wallet or a credit card.
/// [balance] is the balance (or, for a credit card, the available limit) as
/// of the moment the account was last set; expenses recorded after that
/// (ids above [baseExpenseId]) are subtracted, and credit card bill payments
/// (ids above [basePaymentId]) added or deducted, to get the current figure.
class Account {
  final int? id;
  final String name;
  final AccountType type;
  final double balance;
  final double totalLimit;
  final int billingDay;
  final int dueDay;
  final int baseExpenseId;
  final int basePaymentId;

  /// Income recorded after this id counts towards the balance.
  final int baseIncomeId;

  /// For a credit card: the part of the outstanding, when the figures were last
  /// set, that was spent after the last bill date and so is not billed yet. It
  /// belongs to the billing cycle that [baseDate] (millis since epoch, 0 when
  /// never set) falls in, and shows on that cycle's statement.
  final double unbilledBase;
  final int baseDate;

  /// For a credit card: the id of the card whose credit limit it shares, or null
  /// when it has a limit of its own.
  final int? sharedWith;

  const Account({
    this.id,
    required this.name,
    required this.type,
    this.balance = 0,
    this.totalLimit = 0,
    this.billingDay = 1,
    this.dueDay = 15,
    this.baseExpenseId = 0,
    this.basePaymentId = 0,
    this.baseIncomeId = 0,
    this.unbilledBase = 0,
    this.baseDate = 0,
    this.sharedWith,
  });

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id'] as int,
        name: m['name'] as String,
        type: AccountType.values[m['type'] as int],
        balance: (m['balance'] as num).toDouble(),
        totalLimit: (m['total_limit'] as num).toDouble(),
        billingDay: m['billing_day'] as int,
        dueDay: m['due_day'] as int,
        baseExpenseId: m['base_expense_id'] as int,
        basePaymentId: m['base_payment_id'] as int,
        baseIncomeId: (m['base_income_id'] as int?) ?? 0,
        unbilledBase: (m['unbilled_base'] as num?)?.toDouble() ?? 0,
        baseDate: (m['base_date'] as int?) ?? 0,
        sharedWith: m['shared_with'] as int?,
      );

  Account copyWith({double? balance, double? totalLimit}) => Account(
        id: id,
        name: name,
        type: type,
        balance: balance ?? this.balance,
        totalLimit: totalLimit ?? this.totalLimit,
        billingDay: billingDay,
        dueDay: dueDay,
        baseExpenseId: baseExpenseId,
        basePaymentId: basePaymentId,
        baseIncomeId: baseIncomeId,
        unbilledBase: unbilledBase,
        baseDate: baseDate,
        sharedWith: sharedWith,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'type': type.index,
        'balance': balance,
        'total_limit': totalLimit,
        'billing_day': billingDay,
        'due_day': dueDay,
        'base_expense_id': baseExpenseId,
        'base_payment_id': basePaymentId,
        'base_income_id': baseIncomeId,
        'unbilled_base': unbilledBase,
        'base_date': baseDate,
        'shared_with': sharedWith,
      };
}

/// A payment towards a credit card bill: money leaves the account behind
/// [modeId] and the card's outstanding amount goes down. It is not spending.
class CardPayment {
  final int? id;
  final int cardId;
  final int modeId;
  final double amount;
  final String note;
  final DateTime date;

  const CardPayment({
    this.id,
    required this.cardId,
    required this.modeId,
    required this.amount,
    required this.note,
    required this.date,
  });

  factory CardPayment.fromMap(Map<String, Object?> m) => CardPayment(
        id: m['id'] as int,
        cardId: m['card_id'] as int,
        modeId: m['mode_id'] as int,
        amount: (m['amount'] as num).toDouble(),
        note: (m['note'] as String?) ?? '',
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'card_id': cardId,
        'mode_id': modeId,
        'amount': amount,
        'note': note,
        'date': date.millisecondsSinceEpoch,
      };
}

/// A payment mode being edited inside the account sheet, not yet saved.
class ModeDraft {
  final int? id;
  final String name;
  final int icon;
  const ModeDraft({this.id, required this.name, required this.icon});
}

/// Money received into a cash or bank account.
class Income {
  final int? id;
  final double amount;
  final String note;
  final int categoryId;

  /// The payment mode of the account that received it.
  final int paymentModeId;
  final DateTime date;

  const Income({
    this.id,
    required this.amount,
    required this.note,
    required this.categoryId,
    required this.paymentModeId,
    required this.date,
  });

  factory Income.fromMap(Map<String, Object?> m) => Income(
        id: m['id'] as int,
        amount: (m['amount'] as num).toDouble(),
        note: (m['note'] as String?) ?? '',
        categoryId: m['category_id'] as int,
        paymentModeId: m['payment_mode_id'] as int,
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'amount': amount,
        'note': note,
        'category_id': categoryId,
        'payment_mode_id': paymentModeId,
        'date': date.millisecondsSinceEpoch,
      };
}

class Expense {
  final int? id;
  final double amount;
  final String note;
  final int categoryId;
  final int paymentModeId;
  final DateTime date;

  /// File name of a receipt photo kept in app storage (see AttachmentService).
  final String? attachment;

  /// Set on the entries a card EMI creates (its purchase, interest and fee).
  /// They feed the reports only: the card's limit and bill are worked out from
  /// the EMI itself, so these are skipped there.
  final int? emiId;

  /// Shared by the legs of one payment that was split across several accounts.
  final int? splitGroup;

  const Expense({
    this.id,
    required this.amount,
    required this.note,
    required this.categoryId,
    required this.paymentModeId,
    required this.date,
    this.attachment,
    this.emiId,
    this.splitGroup,
  });

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: m['id'] as int,
        amount: (m['amount'] as num).toDouble(),
        note: (m['note'] as String?) ?? '',
        categoryId: m['category_id'] as int,
        paymentModeId: m['payment_mode_id'] as int,
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        attachment: m['attachment'] as String?,
        emiId: m['emi_id'] as int?,
        splitGroup: m['split_group'] as int?,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'amount': amount,
        'note': note,
        'category_id': categoryId,
        'payment_mode_id': paymentModeId,
        'date': date.millisecondsSinceEpoch,
        'attachment': attachment,
        'emi_id': emiId,
        'split_group': splitGroup,
      };
}

enum Frequency {
  daily('Daily', 'day'),
  weekly('Weekly', 'week'),
  monthly('Monthly', 'month'),
  yearly('Yearly', 'year');

  final String label;
  final String unit;
  const Frequency(this.label, this.unit);
}

/// Days-before options for the reminder; 0 means "on the due day", -1 is off.
const List<int> kReminderChoices = [-1, 0, 1, 3, 7];

String reminderLabel(int days) => switch (days) {
      -1 => 'No reminder',
      0 => 'On the due day',
      1 => '1 day before',
      _ => '$days days before',
    };

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// [day] of the given month (month may overflow, e.g. 0 or 13), clamped to the
/// month's length.
DateTime monthDay(int year, int month, int day) {
  final first = DateTime(year, month, 1);
  final last = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(first.year, first.month, day > last ? last : day);
}

/// The due date for the statement generated on [statement].
DateTime billDueDate(DateTime statement, int dueDay) {
  final due = monthDay(statement.year, statement.month, dueDay);
  return due.isBefore(statement) ? monthDay(statement.year, statement.month + 1, dueDay) : due;
}

/// Where a credit card stands in its billing cycle.
class CardBill {
  final Account card;

  /// The day the latest statement was generated (the current cycle's start).
  final DateTime statementDate;
  final DateTime dueDate;

  /// Still unpaid on that statement.
  final double due;

  /// Spent in the running cycle; it goes on the next statement.
  final double unbilled;

  /// Spent in the cycle that closed on [statementDate].
  final double statement;
  final DateTime nextStatement;

  /// Card EMI principal held on the limit that is not on any statement yet.
  final double emiBlocked;

  const CardBill({
    required this.card,
    required this.statementDate,
    required this.dueDate,
    required this.due,
    required this.unbilled,
    required this.statement,
    required this.nextStatement,
    this.emiBlocked = 0,
  });

  int daysToDue([DateTime? now]) => dueDate.difference(dayOnly(now ?? DateTime.now())).inDays;
}

/// A bill or subscription that repeats on a schedule. [nextDue] is the next
/// date an expense has not yet been created for.
class Recurring {
  final int? id;
  final String name;
  final int icon;
  final double amount;
  final String note;
  final int categoryId;
  final int paymentModeId;
  final Frequency frequency;
  final DateTime startDate;
  final DateTime nextDue;
  final bool active;
  final int remindDays;

  /// An EMI is a monthly instalment plan: [totalCount] payments, [paidCount] done.
  final bool isEmi;
  final int totalCount;
  final int paidCount;

  /// EMIs: what was financed (the purchase or loan amount), 0 when not given.
  /// [amount] is the monthly EMI exactly as the bank states it, interest included.
  final double principal;

  /// A one-time fee charged with the first instalment.
  final double fee;

  /// When the EMI was added (millis since epoch).
  final int created;

  /// Card EMIs: instalments whose interest / fee has been recorded as an expense.
  final int postedCount;

  /// Card EMIs: the expense that records the purchase (0 or null for none).
  final int? purchaseExpenseId;

  /// GST charged on each month's interest and on the fee, as a percentage (0 for none).
  final double gstRate;

  /// Card EMIs: how many statements the first EMI waits after the first one that
  /// follows the purchase (0 = billed on that statement, 1 = on the one after).
  final int firstDelay;

  /// Card EMIs: interest charged on the first statement, before any instalment
  /// (the part of the bank's "total interest" that the EMIs themselves do not cover).
  final double initialInterest;

  /// Foreclosure: the day the EMI was closed early (millis, 0 when it was not), what
  /// was paid towards the outstanding principal, the charge and its GST, and the
  /// expense that records it.
  final int closedOn;
  final double closePrincipal;
  final double closeCharge;
  final double closeGst;
  final int? closureExpenseId;

  const Recurring({
    this.id,
    required this.name,
    required this.icon,
    required this.amount,
    required this.note,
    required this.categoryId,
    required this.paymentModeId,
    required this.frequency,
    required this.startDate,
    required this.nextDue,
    this.active = true,
    this.remindDays = 1,
    this.isEmi = false,
    this.totalCount = 0,
    this.paidCount = 0,
    this.principal = 0,
    this.fee = 0,
    this.created = 0,
    this.postedCount = 0,
    this.purchaseExpenseId,
    this.gstRate = 0,
    this.firstDelay = 0,
    this.initialInterest = 0,
    this.closedOn = 0,
    this.closePrincipal = 0,
    this.closeCharge = 0,
    this.closeGst = 0,
    this.closureExpenseId,
  });

  factory Recurring.fromMap(Map<String, Object?> m) => Recurring(
        id: m['id'] as int,
        name: (m['name'] as String?) ?? '',
        icon: (m['icon'] as int?) ?? kSubscriptionIcon,
        amount: (m['amount'] as num).toDouble(),
        note: (m['note'] as String?) ?? '',
        categoryId: m['category_id'] as int,
        paymentModeId: m['payment_mode_id'] as int,
        frequency: Frequency.values[m['frequency'] as int],
        startDate: DateTime.fromMillisecondsSinceEpoch(m['start_date'] as int),
        nextDue: DateTime.fromMillisecondsSinceEpoch(m['next_due'] as int),
        active: (m['active'] as int) == 1,
        remindDays: m['remind_days'] as int,
        isEmi: (m['kind'] as int) == 1,
        totalCount: m['total_count'] as int,
        paidCount: m['paid_count'] as int,
        principal: (m['principal'] as num?)?.toDouble() ?? 0,
        fee: (m['fee'] as num?)?.toDouble() ?? 0,
        created: (m['created'] as int?) ?? 0,
        postedCount: (m['posted_count'] as int?) ?? 0,
        purchaseExpenseId: m['purchase_expense_id'] as int?,
        gstRate: (m['gst_rate'] as num?)?.toDouble() ?? 0,
        firstDelay: (m['first_delay'] as int?) ?? 0,
        initialInterest: (m['initial_interest'] as num?)?.toDouble() ?? 0,
        closedOn: (m['closed_on'] as int?) ?? 0,
        closePrincipal: (m['close_principal'] as num?)?.toDouble() ?? 0,
        closeCharge: (m['close_charge'] as num?)?.toDouble() ?? 0,
        closeGst: (m['close_gst'] as num?)?.toDouble() ?? 0,
        closureExpenseId: m['closure_expense_id'] as int?,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'icon': icon,
        'amount': amount,
        'note': note,
        'category_id': categoryId,
        'payment_mode_id': paymentModeId,
        'frequency': frequency.index,
        'start_date': startDate.millisecondsSinceEpoch,
        'next_due': nextDue.millisecondsSinceEpoch,
        'active': active ? 1 : 0,
        'remind_days': remindDays,
        'kind': isEmi ? 1 : 0,
        'total_count': totalCount,
        'paid_count': paidCount,
        'principal': principal,
        'fee': fee,
        'created': created,
        'posted_count': postedCount,
        'purchase_expense_id': purchaseExpenseId,
        'gst_rate': gstRate,
        'first_delay': firstDelay,
        'initial_interest': initialInterest,
        'closed_on': closedOn,
        'close_principal': closePrincipal,
        'close_charge': closeCharge,
        'close_gst': closeGst,
        'closure_expense_id': closureExpenseId,
      };

  /// Closed early (foreclosed).
  bool get foreclosed => closedOn > 0;

  DateTime get closedDate => DateTime.fromMillisecondsSinceEpoch(closedOn);

  /// An EMI whose last instalment has been paid, or that was foreclosed.
  bool get completed => foreclosed || (isEmi && totalCount > 0 && paidCount >= totalCount);

  Recurring copyWith({
    int? id,
    DateTime? nextDue,
    bool? active,
    int? paymentModeId,
    int? paidCount,
    int? postedCount,
    int? purchaseExpenseId,
    int? closedOn,
    double? closePrincipal,
    double? closeCharge,
    double? closeGst,
    int? closureExpenseId,
  }) =>
      Recurring(
        id: id ?? this.id,
        name: name,
        icon: icon,
        amount: amount,
        note: note,
        categoryId: categoryId,
        paymentModeId: paymentModeId ?? this.paymentModeId,
        frequency: frequency,
        startDate: startDate,
        nextDue: nextDue ?? this.nextDue,
        active: active ?? this.active,
        remindDays: remindDays,
        isEmi: isEmi,
        totalCount: totalCount,
        paidCount: paidCount ?? this.paidCount,
        principal: principal,
        fee: fee,
        gstRate: gstRate,
        firstDelay: firstDelay,
        initialInterest: initialInterest,
        closedOn: closedOn ?? this.closedOn,
        closePrincipal: closePrincipal ?? this.closePrincipal,
        closeCharge: closeCharge ?? this.closeCharge,
        closeGst: closeGst ?? this.closeGst,
        closureExpenseId: closureExpenseId ?? this.closureExpenseId,
        created: created,
        postedCount: postedCount ?? this.postedCount,
        purchaseExpenseId: purchaseExpenseId ?? this.purchaseExpenseId,
      );

  /// An EMI whose financed amount is known, so its interest can be worked out.
  bool get hasPrincipal => isEmi && principal > 0 && totalCount > 0;

  /// The monthly interest rate hidden in the EMI: the rate that turns [principal]
  /// into [amount] over [totalCount] months on a reducing balance, as banks charge it.
  double get monthlyRate {
    if (!hasPrincipal || amount * totalCount <= principal + 1e-9) return 0;
    var lo = 0.0;
    var hi = 1.0;
    for (var i = 0; i < 80; i++) {
      final mid = (lo + hi) / 2;
      final f = math.pow(1 + mid, totalCount).toDouble();
      if (principal * mid * f / (f - 1) > amount) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return (lo + hi) / 2;
  }

  /// The principal still owed once [m] instalments have been paid.
  double remainingPrincipalAfter(int m) {
    if (!hasPrincipal) return 0;
    if (m <= 0) return principal;
    if (m >= totalCount) return 0;
    final r = monthlyRate;
    if (r <= 0) return principal * (1 - m / totalCount);
    final f = math.pow(1 + r, m).toDouble();
    final bal = principal * f - amount * (f - 1) / r;
    return bal < 0 ? 0 : bal;
  }

  /// The part of instalment [j] (counting from 1) that repays the principal.
  double principalOf(int j) => remainingPrincipalAfter(j - 1) - remainingPrincipalAfter(j);

  /// The part of instalment [j] that is interest.
  double interestOf(int j) {
    final p = principalOf(j);
    return amount > p ? amount - p : 0;
  }

  double get _gst => gstRate / 100;

  /// The GST on instalment [j]'s interest.
  double gstOn(int j) => interestOf(j) * _gst;

  /// What instalment [j] adds to a statement: the EMI plus the GST on its interest.
  /// The one-time fee (see [pendingFeeGross]) comes on top of the first one.
  double billedAmount(int j) => amount + gstOn(j);

  /// The initial interest with its GST; only a new EMI has one.
  double get initialGross => paidCount == 0 ? initialInterest * (1 + _gst) : 0;

  /// The fee still to come, with its GST.
  double get pendingFeeGross => pendingFee * (1 + _gst);

  /// The fee still to come: it is charged with the first instalment, so an EMI
  /// that is already under way has paid it.
  double get pendingFee => paidCount == 0 ? fee : 0;

  /// The occurrence after [from]. Monthly/yearly keep the start day, clamped
  /// to short months (31 Jan -> 28 Feb -> 31 Mar).
  DateTime advance(DateTime from) {
    switch (frequency) {
      case Frequency.daily:
        return DateTime(from.year, from.month, from.day + 1);
      case Frequency.weekly:
        return DateTime(from.year, from.month, from.day + 7);
      case Frequency.monthly:
        final y = from.year + (from.month == 12 ? 1 : 0);
        final mo = from.month == 12 ? 1 : from.month + 1;
        return DateTime(y, mo, _clamp(y, mo, startDate.day));
      case Frequency.yearly:
        final y = from.year + 1;
        return DateTime(y, startDate.month, _clamp(y, startDate.month, startDate.day));
    }
  }

  static int _clamp(int y, int m, int day) {
    final last = DateTime(y, m + 1, 0).day;
    return day > last ? last : day;
  }

  /// Rough monthly cost, used for the summary card.
  double get monthlyEquivalent => switch (frequency) {
        Frequency.daily => amount * 30.4375,
        Frequency.weekly => amount * 52 / 12,
        Frequency.monthly => amount,
        Frequency.yearly => amount / 12,
      };
}

/// A free-form note kept in the Notes tab.
class Note {
  final int? id;
  final String title;
  final String body;
  final bool pinned;
  final DateTime updated;

  const Note({
    this.id,
    required this.title,
    required this.body,
    this.pinned = false,
    required this.updated,
  });

  factory Note.fromMap(Map<String, Object?> m) => Note(
        id: m['id'] as int,
        title: (m['title'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
        pinned: (m['pinned'] as int) == 1,
        updated: DateTime.fromMillisecondsSinceEpoch(m['updated'] as int),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'body': body,
        'pinned': pinned ? 1 : 0,
        'updated': updated.millisecondsSinceEpoch,
      };
}
