import 'package:flutter/material.dart';

import 'categories_screen.dart';
import 'expenses_screen.dart';
import 'help_screen.dart';
import 'inventory_screen.dart';
import 'proposal_letters_screen.dart';
import 'reports_screen.dart';
import 'risk_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';

/// A place the search box can send you, as opposed to a record it can
/// find.
///
/// Someone who types "reports" wants the reports screen, and someone who
/// types "where do I scan a receipt" wants the scanner. People ask a
/// search box for help whether or not it was built to answer, and the
/// box knew only about events and expenses — so a word for a screen
/// found nothing at all.
class SearchDestination {
  const SearchDestination({
    required this.title,
    required this.about,
    required this.words,
    required this.open,
  });

  final String title;
  final String about;

  /// Words that should find it but are not worth showing. The screen is
  /// called "Financial reports"; people look for "csv".
  final List<String> words;

  final Widget Function() open;

  static const List<SearchDestination> all = [
    SearchDestination(
      title: 'Financial reports',
      about: 'Income and spending over a period',
      words: ['report', 'pdf', 'csv', 'export', 'download', 'chart',
          'analytics', 'summary'],
      open: ReportsScreen.new,
    ),
    SearchDestination(
      title: 'Budget categories',
      about: 'Allocation and remaining balance',
      words: ['budget', 'category', 'categories', 'allocate', 'allocation'],
      open: CategoriesScreen.new,
    ),
    SearchDestination(
      title: 'Expenses',
      about: 'What has been spent, and what is waiting',
      words: ['expense', 'spending', 'spent', 'pending', 'approve'],
      open: ExpensesScreen.new,
    ),
    SearchDestination(
      title: 'Inventory',
      about: 'What the organization holds',
      words: ['inventory', 'item', 'stock', 'equipment', 'supplies'],
      open: InventoryScreen.new,
    ),
    SearchDestination(
      title: 'Flagged for review',
      about: 'Expenses the system noticed something about',
      words: ['flag', 'flagged', 'risk', 'duplicate', 'suspicious'],
      open: RiskScreen.new,
    ),
    SearchDestination(
      title: 'Proposal letters',
      about: 'Letters submitted for events',
      words: ['letter', 'letters', 'upload'],
      open: ProposalLettersScreen.new,
    ),
    SearchDestination(
      title: 'Record an expense',
      about: 'Photograph a receipt and file it',
      words: ['scan', 'receipt', 'camera', 'ocr', 'photo', 'record'],
      open: ScannerScreen.new,
    ),
    SearchDestination(
      title: 'Help and support',
      about: 'How the app actually works',
      words: ['help', 'support', 'how', 'guide', 'what'],
      open: HelpScreen.new,
    ),
    SearchDestination(
      title: 'Settings',
      about: 'Theme, motion and this device',
      words: ['setting', 'settings', 'theme', 'dark', 'light', 'demo', 'role'],
      open: SettingsScreen.new,
    ),
  ];

  /// Whether [query] should find this.
  ///
  /// Matches a word that starts the query, or a query that starts a word,
  /// so "report" and "reports" both land and "rep" does too — without
  /// "or" matching every screen with the letters in its name.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return false;
    if (title.toLowerCase().contains(q)) return true;
    return words.any((w) => w.startsWith(q) || q.startsWith(w));
  }

  static List<SearchDestination> matching(String query) =>
      [for (final d in all) if (d.matches(query)) d];
}
