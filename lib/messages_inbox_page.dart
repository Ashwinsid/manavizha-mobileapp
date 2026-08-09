import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'e2e.dart';
import 'profile_social_actions.dart';
import 'subscription_dialog.dart';
import 'user_activity_tracker.dart';
import 'user_profile_completion.dart';
import 'widgets/adaptive_network_photo.dart';

/// Inbox + thread UI — Flutter port of `manavizha/app/dashboard/messages/page.tsx`.
///
/// Reads/writes `messages` via Supabase (same paths as web `/api/messages`).
/// Premium gating for sending mirrors [showMessageDialog]. Mutual interest
/// (a like row in each direction, neither `declined`) is required to compose.
class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

/// A key that the shell can use to call [_MessagesPageState.refreshPremium]
/// when the Chat tab is tapped without rebuilding the whole widget tree.
final messagesPageKey = GlobalKey<_MessagesPageState>();

class _MessagesPageState extends State<MessagesPage> with WidgetsBindingObserver {
  static const Color _brand = AdminHomeScreen.brandPurple;

  final TextEditingController _composer = TextEditingController();
  final ScrollController _threadScroll = ScrollController();

  String? _userId;
  bool _loading = true;
  String? _error;
  bool _isPremium = false;

  List<_Conversation> _conversations = [];
  List<_Msg> _thread = [];
  _Conversation? _selected;
  bool _threadLoading = false;
  bool _sending = false;
  bool _mutualWithSelected = false;
  bool _otherPersonHasMessaged = false; // true when the other party already sent a message to us
  String _search = '';
  bool _mobileShowList = true;

  RealtimeChannel? _rt;
  Timer? _rtDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _composer.addListener(() => setState(() {}));
    _bootstrap();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _userId != null) {
      refreshPremium();
    }
  }

  /// Re-fetches premium status from DB. Called by the shell when the Chat tab
  /// is tapped so a freshly-subscribed user sees the composer immediately.
  void refreshPremium() {
    final client = Supabase.instance.client;
    final uid = _userId ?? client.auth.currentUser?.id;
    if (uid != null) _loadPremium(client, uid);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rtDebounce?.cancel();
    _rt?.unsubscribe();
    _composer.dispose();
    _threadScroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in to view messages.';
      });
      return;
    }
    setState(() {
      _userId = uid;
      _loading = true;
      _error = null;
    });
    await _loadPremium(client, uid);
    await _loadConversations(client, uid);
    _subscribeRealtime(client, uid);
    if (!mounted) return;
    setState(() => _loading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final wide = MediaQuery.sizeOf(context).width >= 720;
      if (_conversations.isNotEmpty && _selected == null) {
        final first = _conversations.firstWhere(
          (c) => c.unreadCount > 0,
          orElse: () => _conversations.first,
        );
        await _openConversation(client, first, wideLayout: wide);
      }
    });
  }

  Future<void> _loadPremium(SupabaseClient client, String uid) async {
    try {
      final row = await client.from('user_settings').select('is_premium').eq('user_id', uid).maybeSingle();
      final p = row != null && row['is_premium'] == true;
      if (mounted) setState(() => _isPremium = p);
    } catch (_) {
      if (mounted) setState(() => _isPremium = false);
    }
  }

  void _subscribeRealtime(SupabaseClient client, String uid) {
    _rt?.unsubscribe();
    _rt = client
        .channel('messages-inbox-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (_) => _onMessagesTableChanged(client, uid),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (_) => _onMessagesTableChanged(client, uid),
        )
        .subscribe();
  }

  void _onMessagesTableChanged(SupabaseClient client, String uid) {
    _rtDebounce?.cancel();
    _rtDebounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      await _loadConversations(client, uid, silent: true);
      final sel = _selected;
      if (sel != null) {
        await _loadThread(client, uid, sel.otherUserId, silent: true, skipMarkRead: true);
      }
    });
  }

  Future<void> _loadConversations(
    SupabaseClient client,
    String uid, {
    bool silent = false,
  }) async {
    if (!silent && mounted) setState(() => _error = null);
    try {
      final res = await client
          .from('messages')
          .select('id, sender_id, receiver_id, content, is_read, created_at, is_encrypted, iv')
          .or('sender_id.eq.$uid,receiver_id.eq.$uid')
          .order('created_at', ascending: false);

      final raw = res as List<dynamic>? ?? [];
      final msgs = raw.map((e) => _Msg.fromMap(Map<String, dynamic>.from(e as Map))).toList();

      final byOther = <String, List<_Msg>>{};
      for (final m in msgs) {
        final other = m.senderId == uid ? m.receiverId : m.senderId;
        byOther.putIfAbsent(other, () => []).add(m);
      }

      final ids = byOther.keys.toList();
      final names = <String, String>{};
      final photos = <String, String?>{};
      final activity = <String, DateTime?>{};

      if (ids.isNotEmpty) {
        try {
          final pd = await client.from('personal_details').select('user_id, name').inFilter('user_id', ids);
          for (final row in (pd as List<dynamic>?) ?? const []) {
            final m = Map<String, dynamic>.from(row as Map);
            final id = m['user_id']?.toString();
            if (id != null) names[id] = m['name']?.toString().trim().isNotEmpty == true ? m['name'].toString() : 'Member';
          }
        } catch (_) {}

        try {
          final ph = await client.from('photos').select('user_id, user_photos').inFilter('user_id', ids);
          for (final row in (ph as List<dynamic>?) ?? const []) {
            final m = Map<String, dynamic>.from(row as Map);
            final id = m['user_id']?.toString();
            if (id == null) continue;
            final list = parseUserPhotosList(m['user_photos']);
            if (list.isNotEmpty) {
              final signed = await signUserProfilePhoto(client, id, list.first.toString());
              photos[id] = signed;
            } else {
              photos[id] = null;
            }
          }
        } catch (_) {}

        try {
          final act = await client.from('users').select('id, last_active_at').inFilter('id', ids);
          for (final row in (act as List<dynamic>?) ?? const []) {
            final m = Map<String, dynamic>.from(row as Map);
            final id = m['id']?.toString();
            if (id != null) activity[id] = parseLastActive(m['last_active_at']);
          }
        } catch (_) {}
      }

      final list = <_Conversation>[];
      for (final id in ids) {
        final listMsgs = byOther[id]!;
        listMsgs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        // Only the newest message is previewed — decrypt just that one.
        final last = await _decryptMsg(uid, listMsgs.first);
        final unread = listMsgs.where((m) => m.receiverId == uid && !m.isRead).length;
        list.add(
          _Conversation(
            otherUserId: id,
            otherUserName: names[id] ?? 'Member',
            photoUrl: photos[id],
            lastMessage: last.content,
            lastMessageAt: last.createdAt,
            unreadCount: unread,
            lastActiveAt: activity[id],
          ),
        );
      }
      list.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));

      if (!mounted) return;
      setState(() {
        _conversations = list;
        if (_selected != null) {
          final match = list.where((c) => c.otherUserId == _selected!.otherUserId).toList();
          if (match.isNotEmpty) {
            _selected = match.first;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load conversations.');
    }
  }

  Future<void> _openConversation(
    SupabaseClient client,
    _Conversation c, {
    required bool wideLayout,
  }) async {
    final uid = _userId;
    if (uid == null) return;
    setState(() {
      _selected = c;
      if (!wideLayout) _mobileShowList = false;
    });
    await _loadThread(client, uid, c.otherUserId);
    await _checkMutual(client, uid, c.otherUserId);
    _scrollThreadToEnd();
  }

  Future<void> _checkMutual(SupabaseClient client, String me, String other) async {
    try {
      final a = await client.from('likes').select('status').eq('user_id', me).eq('liked_user_id', other).maybeSingle();
      final b = await client.from('likes').select('status').eq('user_id', other).eq('liked_user_id', me).maybeSingle();
      final ok = a != null &&
          b != null &&
          a['status']?.toString() != 'declined' &&
          b['status']?.toString() != 'declined';
      if (mounted) setState(() => _mutualWithSelected = ok);
    } catch (_) {
      if (mounted) setState(() => _mutualWithSelected = false);
    }
  }

  /// Resolves an encrypted row to display text via [E2E.decrypt]; plaintext
  /// rows pass through untouched. Undecryptable content gets the same
  /// placeholder the web shows.
  Future<_Msg> _decryptMsg(String uid, _Msg m) async {
    if (!m.isEncrypted || m.iv == null || m.iv!.isEmpty) return m;
    final other = m.senderId == uid ? m.receiverId : m.senderId;
    final dec = await E2E.decrypt(m.content, m.iv!, other);
    return m.withContent(dec ?? '🔒 Encrypted message');
  }

  Future<void> _loadThread(
    SupabaseClient client,
    String uid,
    String otherId, {
    bool silent = false,
    bool skipMarkRead = false,
  }) async {
    if (!silent && mounted) setState(() => _threadLoading = true);
    try {
      final res = await client
          .from('messages')
          .select('id, sender_id, receiver_id, content, is_read, created_at, is_encrypted, iv')
          .or('and(sender_id.eq.$uid,receiver_id.eq.$otherId),and(sender_id.eq.$otherId,receiver_id.eq.$uid)')
          .order('created_at', ascending: true);

      final raw = res as List<dynamic>? ?? [];
      final parsed = raw.map((e) => _Msg.fromMap(Map<String, dynamic>.from(e as Map))).toList();
      final list = <_Msg>[
        for (final m in parsed) await _decryptMsg(uid, m),
      ];
      if (!mounted) return;
      final otherHasMessaged = list.any((m) => m.senderId == otherId);
      setState(() {
        _thread = list;
        _otherPersonHasMessaged = otherHasMessaged;
      });

      if (!skipMarkRead) {
        try {
          await client
              .from('messages')
              .update({'is_read': true})
              .eq('receiver_id', uid)
              .eq('sender_id', otherId)
              .eq('is_read', false);
        } catch (_) {}
        await _loadConversations(client, uid, silent: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _thread = []);
    } finally {
      if (mounted) setState(() => _threadLoading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollThreadToEnd());
    }
  }

  void _scrollThreadToEnd() {
    if (!_threadScroll.hasClients) return;
    final max = _threadScroll.position.maxScrollExtent;
    _threadScroll.jumpTo(max);
  }

  Future<void> _send() async {
    final uid = _userId;
    final sel = _selected;
    final client = Supabase.instance.client;
    if (uid == null || sel == null || _sending) return;
    final text = _composer.text.trim();
    if (text.isEmpty) return;

    // Can send if premium OR if the other person already sent us a message (non-premium reply allowed)
    final canSend = _isPremium || _otherPersonHasMessaged;
    if (!canSend) {
      await showSubscriptionDialog(context, featureName: 'Personalized messaging');
      return;
    }
    if (!_mutualWithSelected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can only message mutual matches.')),
      );
      return;
    }

    setState(() => _sending = true);
    final err = await ProfileSocialActions.sendMessage(
      client: client,
      senderId: uid,
      receiverId: sel.otherUserId,
      content: text,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    _composer.clear();
    await _loadThread(client, uid, sel.otherUserId, silent: true);
    await _loadConversations(client, uid, silent: true);
    _scrollThreadToEnd();
  }

  List<_Conversation> get _filteredConversations {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return List<_Conversation>.from(_conversations);
    return _conversations.where((c) => c.otherUserName.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _brand));
    }
    if (_error != null && _userId == null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)));
    }

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 720;
        if (!wide) {
          return _mobileShowList ? _buildListPane(context, wide: false) : _buildChatPane(context, wide: false);
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 8)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: (c.maxWidth * 0.36).clamp(280.0, 400.0), child: _buildListPane(context, wide: true)),
                  Expanded(child: _buildChatPane(context, wide: true)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildListPane(BuildContext context, {required bool wide}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.forum_rounded, color: _brand, size: 26),
                  const SizedBox(width: 8),
                  Text('Messages', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search conversations…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 22),
                  filled: true,
                  fillColor: const Color(0xFFF3F4F6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
          ),
        Expanded(
          child: _filteredConversations.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _search.trim().isEmpty
                          ? 'No messages yet. When you and another member like each other, you can start chatting here.'
                          : 'No conversations match your search.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black.withValues(alpha: 0.45), fontWeight: FontWeight.w600),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                  itemCount: _filteredConversations.length,
                  itemBuilder: (context, i) {
                    final conv = _filteredConversations[i];
                    final selected = _selected?.otherUserId == conv.otherUserId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Material(
                        color: selected ? const Color(0xFFE8F5F1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () async {
                            final client = Supabase.instance.client;
                            final uid = _userId;
                            if (uid == null) return;
                            await _openConversation(client, conv, wideLayout: wide);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            child: Row(
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    CircleAvatar(
                                      radius: 26,
                                      backgroundColor: _brand.withValues(alpha: 0.12),
                                      child: conv.photoUrl != null && conv.photoUrl!.isNotEmpty
                                          ? ClipOval(
                                              child: SizedBox(
                                                width: 52,
                                                height: 52,
                                                child: AdaptiveNetworkPhoto(imageUrl: conv.photoUrl!),
                                              ),
                                            )
                                          : Icon(Icons.person_rounded, color: _brand.withValues(alpha: 0.5), size: 28),
                                    ),
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: formatActivityTime(conv.lastActiveAt) == 'Online'
                                              ? const Color(0xFF10B981)
                                              : Colors.grey.shade400,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 2),
                                        ),
                                      ),
                                    ),
                                    if (conv.unreadCount > 0)
                                      Positioned(
                                        top: -4,
                                        right: -4,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFF1493),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                          child: Text(
                                            '${conv.unreadCount > 9 ? '9+' : conv.unreadCount}',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              conv.otherUserName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                            ),
                                          ),
                                          Text(
                                            _timeHm(conv.lastMessageAt),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.black.withValues(alpha: 0.35),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        conv.lastMessage,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.45)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _timeHm(DateTime dt) {
    final t = TimeOfDay.fromDateTime(dt.toLocal());
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  Widget _buildChatPane(BuildContext context, {required bool wide}) {
    final sel = _selected;
    final uid = _userId;
    if (sel == null) {
      return ColoredBox(
        color: const Color(0xFFF8FAFC),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 72, color: _brand.withValues(alpha: 0.2)),
                const SizedBox(height: 16),
                Text(
                  'Your inbox',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pick a conversation to read and reply. Mutual matches can chat when you have Premium.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black.withValues(alpha: 0.45), height: 1.4),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final activityLabel = formatActivityTime(sel.lastActiveAt);
    final online = activityLabel == 'Online';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.white,
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
            child: Row(
              children: [
                if (!wide)
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => setState(() {
                      _mobileShowList = true;
                    }),
                  ),
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: _brand.withValues(alpha: 0.12),
                      child: sel.photoUrl != null && sel.photoUrl!.isNotEmpty
                          ? ClipOval(
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: AdaptiveNetworkPhoto(imageUrl: sel.photoUrl!),
                              ),
                            )
                          : Icon(Icons.person_rounded, color: _brand.withValues(alpha: 0.5)),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: online ? const Color(0xFF10B981) : Colors.grey.shade400,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sel.otherUserName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      Text(
                        activityLabel.isEmpty ? 'Offline' : activityLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: online ? const Color(0xFF059669) : Colors.black.withValues(alpha: 0.38),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Container(
            color: const Color(0xFFF8FAFC),
            child: _threadLoading
                ? const Center(child: CircularProgressIndicator(color: _brand))
                : ListView.builder(
                    controller: _threadScroll,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    itemCount: _thread.length,
                    itemBuilder: (context, i) {
                      final m = _thread[i];
                      final mine = m.senderId == uid;
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: wide ? 420 : MediaQuery.sizeOf(context).width * 0.82),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: mine
                                  ? const LinearGradient(colors: [Color(0xFF2FA086), Color(0xFF248A73)])
                                  : null,
                              color: mine ? null : Colors.white,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(mine ? 16 : 4),
                                bottomRight: Radius.circular(mine ? 4 : 16),
                              ),
                              border: mine ? null : Border.all(color: Colors.black.withValues(alpha: 0.06)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                              child: Column(
                                crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m.content,
                                    style: TextStyle(
                                      color: mine ? Colors.white : Colors.black87,
                                      fontSize: 14,
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _timeHm(m.createdAt),
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: mine ? Colors.white.withValues(alpha: 0.75) : Colors.black38,
                                        ),
                                      ),
                                      if (mine) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          m.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                                          size: 14,
                                          color: m.isRead ? const Color(0xFF93C5FD) : Colors.white54,
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
        Material(
          color: Colors.white,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + MediaQuery.paddingOf(context).bottom),
            child: _composerBlock(),
          ),
        ),
      ],
    );
  }

  Widget _composerBlock() {
    final canSend = _isPremium || _otherPersonHasMessaged;
    if (!canSend) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Subscribe to Premium to send replies from your inbox.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
              ),
            ),
            TextButton(
              onPressed: () => showSubscriptionDialog(context, featureName: 'Personalized messaging'),
              child: const Text('UPGRADE', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      );
    }
    if (!_mutualWithSelected) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Text(
          'Messaging is available only with mutual matches (you have both accepted interest).',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade900),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _composer,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Type a message…',
              filled: true,
              fillColor: const Color(0xFFF3F4F6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: (_sending || _composer.text.trim().isEmpty) ? null : _send,
          style: FilledButton.styleFrom(
            backgroundColor: _brand,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.all(14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _sending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.send_rounded, size: 22),
        ),
      ],
    );
  }
}

class _Conversation {
  _Conversation({
    required this.otherUserId,
    required this.otherUserName,
    required this.photoUrl,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.lastActiveAt,
  });

  final String otherUserId;
  final String otherUserName;
  final String? photoUrl;
  final String lastMessage;
  final DateTime lastMessageAt;
  final int unreadCount;
  final DateTime? lastActiveAt;
}

class _Msg {
  _Msg({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.createdAt,
    required this.isRead,
    this.isEncrypted = false,
    this.iv,
  });

  factory _Msg.fromMap(Map<String, dynamic> m) {
    return _Msg(
      id: m['id']?.toString() ?? '',
      senderId: m['sender_id']?.toString() ?? '',
      receiverId: m['receiver_id']?.toString() ?? '',
      content: m['content']?.toString() ?? '',
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now().toUtc(),
      isRead: m['is_read'] == true,
      isEncrypted: m['is_encrypted'] == true,
      iv: m['iv']?.toString(),
    );
  }

  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final DateTime createdAt;
  final bool isRead;
  final bool isEncrypted;
  final String? iv;

  /// Copy with the decrypted (or placeholder) text in place of ciphertext.
  _Msg withContent(String newContent) => _Msg(
        id: id,
        senderId: senderId,
        receiverId: receiverId,
        content: newContent,
        createdAt: createdAt,
        isRead: isRead,
        iv: iv,
      );
}
