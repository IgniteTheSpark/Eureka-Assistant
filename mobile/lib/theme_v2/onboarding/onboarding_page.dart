import 'package:flutter/material.dart';

import '../../auth/auth_controller.dart';
import '../foundation/theme_v2_theme.dart';
import 'onboarding_controller.dart';

/// Theme V2 onboarding flow (§4.4 / §6). Fully skippable; teaches the
/// capture-to-structure workflow without a pet/avatar.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, this.controller});

  final OnboardingController? controller;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

enum _Step { value, category, fields, input, preview }

class _OnboardingPageState extends State<OnboardingPage> {
  late final OnboardingController _controller;
  _Step _step = _Step.value;
  final _sourceText = TextEditingController();
  String _idempotencyKey = '';

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? OnboardingController();
    _controller.addListener(_onControllerChanged);
    _controller.loadCatalog();
    _idempotencyKey = 'onb-conf-${DateTime.now().microsecondsSinceEpoch}';
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _sourceText.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _go(_Step step) => setState(() => _step = step);

  Future<void> _handleSkip() async {
    final ok = await _controller.skip();
    if (ok && mounted) {
      await AuthController.instance.updateOnboardingStatus('skipped');
      _controller.clear();
    }
  }

  Future<void> _createSkill() async {
    final ok = await _controller.createSkill();
    if (ok && mounted) _go(_Step.input);
  }

  Future<void> _runPreview() async {
    final ok = await _controller.runPreview(_sourceText.text.trim());
    if (ok && mounted) _go(_Step.preview);
  }

  Future<void> _confirm() async {
    final payload = _controller.previewPayload ?? {};
    final ok = await _controller.confirm(
      payload: payload,
      idempotencyKey: _idempotencyKey,
    );
    if (ok && mounted) {
      // Durable completion: gate rebuilds into the app shell.
      await AuthController.instance.updateOnboardingStatus('completed');
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.themeV2.background,
      body: SafeArea(
        child: switch (_step) {
          _Step.value => _valueScreen(),
          _Step.category => _categoryScreen(),
          _Step.fields => _fieldsScreen(),
          _Step.input => _inputScreen(),
          _Step.preview => _previewScreen(),
        },
      ),
    );
  }

  Widget _valueScreen() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '把想记录的事,说或写下来',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            '选择一种想跟踪的记录,说或写一条真实的内容,\nUReka 会帮你整理保存。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => _go(_Step.category),
            child: const Text('开始'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _handleSkip, child: const Text('跳过')),
        ],
      ),
    );
  }

  Widget _categoryScreen() {
    final categories = _controller.categories;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('想记录什么?', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Expanded(
            child: _controller.loadingCatalog
                ? const Center(child: CircularProgressIndicator())
                : GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    children: [
                      for (final category in categories)
                        _categoryCard(category),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              if (_controller.selectedCategory == null) return;
              _go(_Step.fields);
            },
            child: const Text('下一步'),
          ),
        ],
      ),
    );
  }

  Widget _categoryCard(Map<String, dynamic> category) {
    final id = category['id'] as String?;
    final selected = _controller.selectedCategory == id;
    return InkWell(
      onTap: () => _controller.selectCategory(id),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? context.themeV2.accent.withValues(alpha: 0.15)
              : context.themeV2.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? context.themeV2.accent : context.themeV2.border,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              category['label'] as String? ?? '',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              category['description'] as String? ?? '',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldsScreen() {
    final categoryId = _controller.selectedCategory;
    final fields = categoryId == null
        ? const <Map<String, dynamic>>[]
        : _controller.categoryFields(categoryId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('选择要记录的字段', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('可多选,后续可自行增删', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [for (final field in fields) _fieldTile(field)],
            ),
          ),
          if (_controller.error != null) ...[
            const SizedBox(height: 8),
            Text(
              _controller.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(onPressed: _createSkill, child: const Text('创建记录类型')),
          TextButton(onPressed: _handleSkip, child: const Text('跳过')),
        ],
      ),
    );
  }

  Widget _fieldTile(Map<String, dynamic> field) {
    final key = field['key'];
    final selected = _controller.selectedFields.any((f) => f['key'] == key);
    return CheckboxListTile(
      value: selected,
      onChanged: (_) => _controller.toggleField(field),
      title: Text(field['label'] as String? ?? ''),
      subtitle: Text(field['type'] as String? ?? 'text'),
    );
  }

  Widget _inputScreen() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('记下第一条', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            '用一句话描述,例如:「我沿着河边跑了5公里,用了32分钟」',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _sourceText,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: '输入内容…',
              filled: true,
              fillColor: context.themeV2.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          if (_controller.error != null) ...[
            const SizedBox(height: 8),
            Text(
              _controller.error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(onPressed: _runPreview, child: const Text('识别并整理')),
          TextButton(onPressed: _handleSkip, child: const Text('跳过')),
        ],
      ),
    );
  }

  Widget _previewScreen() {
    final payload = _controller.previewPayload;
    final warnings = _controller.fieldWarnings;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('确认内容', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                if (payload == null) ...[
                  Text(
                    '未能自动识别,请手动填写:',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  for (final field in _controller.manualFields)
                    ListTile(
                      title: Text(field['label'] as String? ?? ''),
                      subtitle: Text(field['key'] as String? ?? ''),
                    ),
                ] else ...[
                  for (final entry in payload.entries)
                    ListTile(
                      title: Text(entry.key),
                      subtitle: Text('${entry.value}'),
                    ),
                ],
                if (warnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final warning in warnings)
                    Text(
                      '⚠ $warning',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
                if (_controller.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _controller.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _confirm, child: const Text('保存到首页')),
          TextButton(
            onPressed: () => _go(_Step.input),
            child: const Text('重新输入'),
          ),
          TextButton(onPressed: _handleSkip, child: const Text('跳过')),
        ],
      ),
    );
  }
}
