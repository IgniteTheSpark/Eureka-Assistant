import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth/auth_controller.dart';
import '../foundation/theme_v2_theme.dart';
import 'account_repository.dart';

/// Full-screen Account settings (§8). Entered from the top-left UReka logo.
class ThemeV2AccountPage extends StatefulWidget {
  const ThemeV2AccountPage({super.key});

  @override
  State<ThemeV2AccountPage> createState() => _ThemeV2AccountPageState();
}

class _ThemeV2AccountPageState extends State<ThemeV2AccountPage> {
  final _repository = AccountRepository();
  bool _busy = false;

  @override
  void dispose() {
    _repository.close();
    super.dispose();
  }

  Future<void> _logout() async {
    await AuthController.instance.logout();
    if (mounted) {
      // Pop back to the root so the auth gate (which rebuilds on logout)
      // becomes visible — the pushed Account page would otherwise stay on top.
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _exportData() async {
    if (_busy) return;
    final options = await _repository.fetchExportOptions();
    if (!mounted) return;
    if (options.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无可导出的数据')));
      return;
    }
    final selection = await showDialog<(List<String>, String)?>(
      context: context,
      builder: (dialogContext) {
        final selected = <String>{};
        var format = 'md';
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('选择导出内容'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in options)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: selected.contains(option['type']),
                      title: Text('${option['name']} (${option['count']})'),
                      onChanged: (value) => setDialogState(() {
                        if (value == true) {
                          selected.add(option['type'] as String);
                        } else {
                          selected.remove(option['type']);
                        }
                      }),
                    ),
                  const Divider(),
                  DropdownButtonFormField<String>(
                    initialValue: format,
                    decoration: const InputDecoration(labelText: '格式'),
                    items: const [
                      DropdownMenuItem(value: 'md', child: Text('Markdown')),
                      DropdownMenuItem(value: 'csv', child: Text('CSV')),
                    ],
                    onChanged: (value) => setDialogState(() {
                      if (value != null) format = value;
                    }),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.of(
                        dialogContext,
                      ).pop((selected.toList(), format)),
                child: const Text('导出'),
              ),
            ],
          ),
        );
      },
    );
    if (selection == null || !mounted) return;
    final (types, format) = selection;
    setState(() => _busy = true);
    try {
      final content = await _repository.exportData(
        types: types,
        format: format,
      );
      if (!mounted) return;
      final filename = 'ureka_export.${format == 'csv' ? 'csv' : 'md'}';
      final file = await _writeTempFile(filename, content);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('导出失败,请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<File> _writeTempFile(String name, String content) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsString(content);
    return file;
  }

  Future<void> _deleteAccount() async {
    if (_busy) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('停用账户'),
        content: const Text('账户将被停用，登录权限会立即撤销，业务数据会保留。当前不提供自助恢复。确定继续吗?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final passwordController = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认停用账户'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '输入密码确认',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () =>
                Navigator.of(dialogContext).pop(passwordController.text),
            child: const Text('停用账户'),
          ),
        ],
      ),
    );
    if (password == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await _repository.deleteAccount(password: password);
      if (!mounted) return;
      await AuthController.instance.logout();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('停用失败,请检查密码')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('修改密码'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '当前密码',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: newController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '新密码（至少 8 位）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '确认新密码',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final current = currentController.text;
              final next = newController.text;
              final confirm = confirmController.text;
              if (next.length < 8) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(const SnackBar(content: Text('密码至少 8 位')));
                }
                return;
              }
              if (next != confirm) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(const SnackBar(content: Text('两次输入的密码不一致')));
                }
                return;
              }
              final err = await AuthController.instance.changePassword(
                current,
                next,
              );
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
                if (err != null) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(SnackBar(content: Text(err)));
                } else {
                  Navigator.of(dialogContext).popUntil(
                    (route) => route.isFirst,
                  );
                }
              }
            },
            child: const Text('确认修改'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final auth = AuthController.instance;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        title: const Text('账户'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: Text(auth.email ?? ''),
            subtitle: const Text('已验证邮箱'),
          ),
          const Divider(height: 1),
          const _SectionHeader('账户'),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('修改密码'),
            onTap: _changePassword,
          ),
          const _SectionHeader('数据'),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('导出数据'),
            subtitle: const Text('Markdown / CSV'),
            onTap: _busy ? null : _exportData,
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: tokens.critical),
            title: Text('停用账户', style: TextStyle(color: tokens.critical)),
            onTap: _busy ? null : _deleteAccount,
          ),
          const _SectionHeader('会话'),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('退出登录'),
            onTap: _logout,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: context.themeV2.muted),
      ),
    );
  }
}
