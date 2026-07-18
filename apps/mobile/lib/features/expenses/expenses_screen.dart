import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../providers/auth_provider.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  List<dynamic> _balances = [];
  List<dynamic> _expenses = [];
  String? _error;
  bool _loading = true;
  final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final balances = await api.get('/expenses/balances') as List<dynamic>;
      final expenses = await api.get('/expenses') as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _balances = balances;
        _expenses = expenses;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load expenses. Pull to refresh.';
        _loading = false;
      });
    }
  }

  Future<void> _addExpense() async {
    final controller = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add expense'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount (₹)'),
            ),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Note'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) {
      controller.dispose();
      note.dispose();
      return;
    }
    final amount = double.tryParse(controller.text.trim());
    final noteText = note.text.trim();
    controller.dispose();
    note.dispose();
    if (amount == null) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/expenses', body: {
        'amount_rupees': amount,
        'note': noteText,
      });
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not save expense. Try again.');
    }
  }

  String _fmtPaise(int paise) => _money.format(paise / 100);

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final c = context.sharanam;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: auth.isLeaderOrVolunteer
          ? FloatingActionButton.extended(
              onPressed: _addExpense,
              label: const Text('Add expense'),
              icon: const Icon(Icons.add),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 88),
          children: [
            const ScreenHeader(
              title: 'Group ledger',
              subtitle: 'Who paid and who owes',
            ),
            if (_error != null) ...[
              StatusBanner(kind: StatusBannerKind.danger, message: _error!),
              const SizedBox(height: 12),
            ],
            if (_loading)
              const SkeletonList(itemCount: 4)
            else ...[
              Text('Balances', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              if (_balances.isEmpty)
                const EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  message: 'No balances yet',
                  detail: 'Add an expense to start the ledger.',
                )
              else
                ..._balances.map((raw) {
                  final b = Map<String, dynamic>.from(raw as Map);
                  final paise = b['net_paise'] as int? ?? 0;
                  final name = b['display_name']?.toString() ?? '';
                  final positive = paise >= 0;
                  return ListRowCard(
                    title: name,
                    leading: CircleAvatar(
                      backgroundColor: (positive ? c.success : c.danger)
                          .withValues(alpha: .14),
                      child: Text(
                        name.isEmpty ? '?' : name[0].toUpperCase(),
                        style: TextStyle(
                          color: positive ? c.success : c.danger,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    trailing: Text(
                      positive
                          ? '+${_fmtPaise(paise)}'
                          : '-${_fmtPaise(-paise)}',
                      style: TextStyle(
                        color: positive ? c.success : c.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 16),
              Text('Recent expenses', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              if (_expenses.isEmpty)
                const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  message: 'No expenses yet',
                )
              else
                ..._expenses.map((raw) {
                  final e = Map<String, dynamic>.from(raw as Map);
                  final paise = e['amount_paise'] as int? ?? 0;
                  final title = e['note']?.toString().isNotEmpty == true
                      ? e['note'].toString()
                      : (e['category']?.toString() ?? 'Expense');
                  return ListRowCard(
                    title: title,
                    subtitle: e['payer_name']?.toString() ?? '',
                    trailing: Text(
                      _fmtPaise(paise),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }
}
