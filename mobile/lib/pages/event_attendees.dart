import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';

String _text(dynamic value) => value == null ? '' : '$value'.trim();

/// The best available attendee label from enriched and legacy event payloads.
String eventAttendeeSummaryName(Map<dynamic, dynamic> attendee) {
  for (final key in const ['display_name', 'name_raw', 'name']) {
    final value = _text(attendee[key]);
    if (value.isNotEmpty) return value;
  }
  return '';
}

/// Compact contact metadata. Phone is used as the fallback when no workplace
/// metadata is available; the selector can still show it separately when both
/// are present.
String contactSummary(Map<dynamic, dynamic> contact) {
  final workplace = [
    _text(contact['company']),
    _text(contact['title']),
  ].where((value) => value.isNotEmpty).join(' · ');
  return workplace.isNotEmpty ? workplace : _text(contact['phone']);
}

class ContactChoice {
  const ContactChoice({
    required this.id,
    required this.name,
    this.company = '',
    this.title = '',
    this.phone = '',
    this.email = '',
  });

  factory ContactChoice.fromJson(Map<dynamic, dynamic> json) {
    return ContactChoice(
      id: _text(json['id']).isNotEmpty
          ? _text(json['id'])
          : _text(json['contact_id']),
      name: _text(json['name']).isNotEmpty
          ? _text(json['name'])
          : eventAttendeeSummaryName(json),
      company: _text(json['company']),
      title: _text(json['title']),
      phone: _text(json['phone']),
      email: _text(json['email']),
    );
  }

  final String id;
  final String name;
  final String company;
  final String title;
  final String phone;
  final String email;

  String get summary => contactSummary(toJson());

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'company': company,
    'title': title,
    'phone': phone,
    'email': email,
  };

  @override
  bool operator ==(Object other) => other is ContactChoice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class EventAttendeeDraft {
  const EventAttendeeDraft({
    this.id,
    this.contactId,
    this.nameRaw,
    required this.displayName,
    this.role = 'attendee',
    required this.isResolved,
    this.contactSummary = '',
    this.contact,
  });

  factory EventAttendeeDraft.fromJson(Map<dynamic, dynamic> json) {
    final rawContact = json['contact'];
    final contact = rawContact is Map
        ? ContactChoice.fromJson(rawContact)
        : null;
    final contactId = _text(json['contact_id']);
    final resolvedValue = json['is_resolved'];
    return EventAttendeeDraft(
      id: _text(json['id']).isEmpty ? null : _text(json['id']),
      contactId: contactId.isEmpty ? contact?.id : contactId,
      nameRaw: _text(json['name_raw']).isEmpty ? null : _text(json['name_raw']),
      displayName: eventAttendeeSummaryName(json),
      role: _text(json['role']).isEmpty ? 'attendee' : _text(json['role']),
      isResolved: resolvedValue is bool
          ? resolvedValue
          : (contactId.isNotEmpty || contact != null),
      contactSummary: _text(json['contact_summary']).isNotEmpty
          ? _text(json['contact_summary'])
          : (contact?.summary ?? ''),
      contact: contact,
    );
  }

  factory EventAttendeeDraft.fromContact(
    ContactChoice contact, {
    String role = 'attendee',
  }) {
    return EventAttendeeDraft(
      contactId: contact.id,
      displayName: contact.name,
      role: role,
      isResolved: true,
      contactSummary: contact.summary,
      contact: contact,
    );
  }

  final String? id;
  final String? contactId;
  final String? nameRaw;
  final String displayName;
  final String role;
  final bool isResolved;
  final String contactSummary;
  final ContactChoice? contact;

  EventAttendeeDraft copyWith({ContactChoice? contact, String? role}) {
    return EventAttendeeDraft(
      id: id,
      contactId: contact?.id ?? contactId,
      nameRaw: nameRaw,
      displayName: contact?.name ?? displayName,
      role: role ?? this.role,
      isResolved: contact != null || isResolved,
      contactSummary: contact?.summary ?? contactSummary,
      contact: contact ?? this.contact,
    );
  }
}

/// Applies the attendee diff only after its parent event has been saved.
Future<void> syncEventAttendees(
  ApiClient api, {
  required String eventId,
  required List<EventAttendeeDraft> original,
  required List<EventAttendeeDraft> current,
}) async {
  final currentById = {
    for (final attendee in current)
      if (attendee.id != null) attendee.id!: attendee,
  };

  for (final attendee in original) {
    final id = attendee.id;
    if (id != null && !currentById.containsKey(id)) {
      await api.deleteJson('/api/events/$eventId/attendees/$id');
    }
  }

  final originalById = {
    for (final attendee in original)
      if (attendee.id != null) attendee.id!: attendee,
  };
  for (final attendee in current) {
    final id = attendee.id;
    if (id == null) continue;
    final before = originalById[id];
    if (before == null) continue;
    final patch = <String, dynamic>{};
    if (before.contactId != attendee.contactId) {
      patch['contact_id'] = attendee.contactId;
    }
    if (before.nameRaw != attendee.nameRaw) patch['name'] = attendee.nameRaw;
    if (before.role != attendee.role) patch['role'] = attendee.role;
    if (patch.isNotEmpty) {
      await api.patchJson('/api/events/$eventId/attendees/$id', patch);
    }
  }

  for (final attendee in current.where((item) => item.id == null)) {
    final body = <String, dynamic>{
      if (attendee.contactId != null) 'contact_id': attendee.contactId,
      if (attendee.contactId == null && attendee.nameRaw != null)
        'name': attendee.nameRaw,
      'role': attendee.role,
    };
    await api.postJson('/api/events/$eventId/attendees', body);
  }
}

typedef CreateContactCallback =
    Future<Map<String, dynamic>?> Function(BuildContext context);

/// Contact picker shared by event attendee creation and unresolved-attendee
/// binding. Single-select mode still returns a list, with at most one item, so
/// callers can share one result path.
Future<List<ContactChoice>?> showEventAttendeeSelector(
  BuildContext context, {
  ApiClient? api,
  List<ContactChoice> initialSelection = const [],
  Set<String> excludedContactIds = const {},
  bool singleSelect = false,
  required CreateContactCallback onCreateContact,
}) {
  return showModalBottomSheet<List<ContactChoice>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.eu.surfaceRaised,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.82,
      child: _EventAttendeeSelector(
        api: api,
        initialSelection: initialSelection,
        excludedContactIds: excludedContactIds,
        singleSelect: singleSelect,
        onCreateContact: onCreateContact,
      ),
    ),
  );
}

class _EventAttendeeSelector extends StatefulWidget {
  const _EventAttendeeSelector({
    required this.api,
    required this.initialSelection,
    required this.excludedContactIds,
    required this.singleSelect,
    required this.onCreateContact,
  });

  final ApiClient? api;
  final List<ContactChoice> initialSelection;
  final Set<String> excludedContactIds;
  final bool singleSelect;
  final CreateContactCallback onCreateContact;

  @override
  State<_EventAttendeeSelector> createState() => _EventAttendeeSelectorState();
}

class _EventAttendeeSelectorState extends State<_EventAttendeeSelector> {
  late final ApiClient _api = widget.api ?? ApiClient();
  late final Map<String, ContactChoice> _selected = {
    for (final contact in widget.initialSelection) contact.id: contact,
  };
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<ContactChoice> _contacts = const [];
  bool _loading = true;
  bool _creating = false;
  String? _error;
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_searchChanged);
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  void _searchChanged() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _load(_searchController.text.trim()),
    );
  }

  Future<void> _load(String query) async {
    final serial = ++_requestSerial;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await _api.getJson(
        '/api/contacts',
        query: {'q': query, 'limit': 20},
      );
      final rawContacts = response is Map ? response['contacts'] : null;
      final contacts = rawContacts is List
          ? rawContacts
                .whereType<Map>()
                .map(ContactChoice.fromJson)
                .where(
                  (contact) =>
                      contact.id.isNotEmpty &&
                      !widget.excludedContactIds.contains(contact.id),
                )
                .toList()
          : <ContactChoice>[];
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _contacts = contacts;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _loading = false;
        _error = '加载联系人失败：$error';
      });
    }
  }

  void _toggle(ContactChoice contact) {
    setState(() {
      if (_selected.containsKey(contact.id)) {
        _selected.remove(contact.id);
      } else {
        if (widget.singleSelect) _selected.clear();
        _selected[contact.id] = contact;
      }
    });
  }

  Future<void> _createContact() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final receipt = await widget.onCreateContact(context);
      if (!mounted || receipt == null) return;
      final raw = receipt['contact'];
      if (raw is! Map) return;
      final json = Map<dynamic, dynamic>.from(raw);
      final receiptId = _text(receipt['contact_id']);
      if (_text(json['id']).isEmpty && receiptId.isNotEmpty) {
        json['id'] = receiptId;
      }
      final contact = ContactChoice.fromJson(json);
      if (contact.id.isEmpty) return;
      setState(() {
        _contacts = [
          contact,
          ..._contacts.where((item) => item.id != contact.id),
        ];
        if (widget.singleSelect) _selected.clear();
        _selected[contact.id] = contact;
      });
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.singleSelect ? '绑定名片' : '添加参会人',
                      style: TextStyle(
                        color: eu.textHi,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: eu.textMid),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchController,
                autofocus: false,
                style: TextStyle(color: eu.textHi),
                decoration: InputDecoration(
                  hintText: '搜索姓名、公司、职位或电话',
                  hintStyle: TextStyle(color: eu.textLo),
                  prefixIcon: Icon(Icons.search, color: eu.textLo),
                  filled: true,
                  fillColor: eu.surface,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: eu.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: eu.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: eu.brand),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(height: 1, color: eu.rule),
        Expanded(child: _buildResults(eu)),
        Container(height: 1, color: eu.rule),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '已选',
                    style: TextStyle(
                      color: eu.textMid,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_selected.values.toList()),
                  style: FilledButton.styleFrom(
                    backgroundColor: eu.brand,
                    foregroundColor: eu.bg,
                    minimumSize: const Size(112, 44),
                  ),
                  child: Text(
                    '保存(${_selected.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResults(EurekaColors eu) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: eu.brand));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: eu.accentRed),
          ),
        ),
      );
    }
    if (_contacts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('没有找到联系人', style: TextStyle(color: eu.textLo)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _creating ? null : _createContact,
              icon: _creating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('新增联系人'),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _contacts.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: eu.rule),
      itemBuilder: (context, index) {
        final contact = _contacts[index];
        final selected = _selected.containsKey(contact.id);
        final summary = contact.summary;
        final showPhone = contact.phone.isNotEmpty && contact.phone != summary;
        return ListTile(
          key: ValueKey(contact.id),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 4,
          ),
          onTap: () => _toggle(contact),
          leading: Icon(
            widget.singleSelect
                ? (selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked)
                : (selected ? Icons.check_circle : Icons.circle_outlined),
            color: selected ? eu.brand : eu.textLo,
          ),
          title: Text(
            contact.name,
            style: TextStyle(color: eu.textHi, fontWeight: FontWeight.w700),
          ),
          subtitle: summary.isEmpty && !showPhone
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (summary.isNotEmpty)
                      Text(summary, style: TextStyle(color: eu.textMid)),
                    if (showPhone)
                      Text(
                        contact.phone,
                        style: TextStyle(color: eu.textLo, fontSize: 12),
                      ),
                  ],
                ),
        );
      },
    );
  }
}
