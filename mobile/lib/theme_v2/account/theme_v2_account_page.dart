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
    final format = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('导出数据'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop('md'),
            child: const ListTile(
              leading: Icon(Icons.description_outlined),
              title: Text('Markdown'),
              subtitle: Text('分组、可读的归档格式'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop('csv'),
            child: const ListTile(
              leading: Icon(Icons.table_chart_outlined),
              title: Text('CSV'),
              subtitle: Text('表格格式,可用电子表格打开'),
            ),
          ),
        ],
      ),
    );
    if (format == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final content = await _repository.exportData(
        types: const [],
        format: format,
      );
      if (!mounted) return;
      final filename = 'ureka_export.${format == 'csv' ? 'csv' : 'md'}';
      final file = await _writeTempFile(filename, content);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导出失败,请稍后重试')),
        );
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
        title: const Text('删除账户'),
        content: const Text(
          '此操作将永久删除你的所有数据,且无法恢复。确定要继续吗?',
        ),
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
        title: const Text('确认删除'),
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
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (password == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await _repository.deleteAccount(password: password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('账户已删除')),
      );
      await AuthController.instance.logout();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除失败,请检查密码')),
        );
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
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('密码至少 8 位')),
                  );
                }
                return;
              }
              if (next != confirm) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('两次输入的密码不一致')),
                  );
                }
                return;
              }
              final err = await AuthController.instance
                  .changePassword(current, next);
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(err ?? '密码已修改'),
                  ),
                );
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
            title: Text('删除账户', style: TextStyle(color: tokens.critical)),
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
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: context.themeV2.muted),
      ),
    );
  }
}
