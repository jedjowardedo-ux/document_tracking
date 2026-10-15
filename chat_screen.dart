import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'sidebar.dart';

// --- DESIGN TOKENS (same palette as the other screens) ---
class _C {
  static const ink = Color(0xFF0B1B3A);
  static const inkSoft = Color(0xFF14337A);
  static const blue = Color(0xFF2563EB);
  static const paper = Color(0xFFF5F7FB);
  static const line = Color(0xFFE3E8F0);
  static const text = Color(0xFF1E293B);
  static const muted = Color(0xFF64748B);
  static const faint = Color(0xFF94A3B8);
  static const red = Color(0xFFD64545);
}

// One chat per pair of users. Same id no matter who opens it first.
String _chatIdFor(String a, String b) {
  final ids = [a, b]..sort();
  return '${ids[0]}_${ids[1]}';
}

String _formatStamp(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
  return sameDay ? DateFormat('hh:mm a').format(t) : DateFormat('MMM d').format(t);
}

// ---------- DELETE HELPERS ----------

Future<bool> _confirmDialog(
    BuildContext context, {
      required String title,
      required String body,
      String confirmLabel = 'Delete',
    }) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(title,
          style: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.w800, color: _C.ink)),
      content: Text(body,
          style: const TextStyle(fontSize: 13, color: _C.muted)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel', style: TextStyle(color: _C.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel,
              style: const TextStyle(
                  color: _C.red, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

void _showError(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: _C.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

// Deletes every message of a chat (in batches), then the chat itself
Future<void> _deleteChat(String chatId) async {
  final db = FirebaseFirestore.instance;
  final chatRef = db.collection('chats').doc(chatId);
  while (true) {
    final snap = await chatRef.collection('messages').limit(400).get();
    if (snap.docs.isEmpty) break;
    final batch = db.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }
  await chatRef.delete();
}

// Profile photo, or the first letter of the name
class _Avatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final double size;

  const _Avatar({required this.name, this.photoUrl, this.size = 46});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'U';
    final fallback = Center(
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.4,
        ),
      ),
    );

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: _C.blue, shape: BoxShape.circle),
      child: (photoUrl == null || photoUrl!.isEmpty)
          ? fallback
          : ClipOval(
        child: Image.network(
          photoUrl!,
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (_, __, ___) => fallback,
          loadingBuilder: (c, child, p) => p == null ? child : fallback,
        ),
      ),
    );
  }
}

// =====================================================================
// CHAT LIST
// =====================================================================

class _Person {
  final String uid;
  final String name;
  final String office;
  final String? photo;

  const _Person({
    required this.uid,
    required this.name,
    required this.office,
    this.photo,
  });

  factory _Person.fromUser(String id, Map<String, dynamic> u) {
    final photo = (u['photoUrl'] ?? '').toString();
    return _Person(
      uid: id,
      name: (u['name'] ?? u['userName'] ?? 'User').toString(),
      office: (u['officeName'] ?? u['office'] ?? '').toString(),
      photo: photo.isEmpty ? null : photo,
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

// Same field names the other screens use for who sent / received a document
const _senderKeys = ['senderId', 'sender_id', 'uploaderId', 'uploader_id'];
const _recipientKeys = [
  'recipientId',
  'receiverId',
  'receiver_id',
  'receiver_user_id'
];

// One row of the chat list
class _ChatItem {
  final _Person person;
  final Map<String, dynamic>? chat; // null = connected, but no message yet
  final DateTime? at;

  const _ChatItem({required this.person, this.chat, this.at});
}

class _PairEntry {
  final String key;
  final List<List<String>> pairs;
  const _PairEntry(this.key, this.pairs);
}

class _ChatScreenState extends State<ChatScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _query = '';

  late final String? _uid;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _chatsStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _usersStream;
  late final Stream<Set<String>> _connectionsStream;

  // docId -> the (sender, recipient) pairs found in that document, so the
  // history trail is only re-read when the document actually changes
  final Map<String, _PairEntry> _pairCache = {};

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;

    final db = FirebaseFirestore.instance;
    final uid = _uid;
    if (uid == null) {
      _chatsStream = const Stream.empty();
      _usersStream = const Stream.empty();
      _connectionsStream = Stream.value(<String>{});
    } else {
      _chatsStream = db
          .collection('chats')
          .where('participants', arrayContains: uid)
          .snapshots();
      _usersStream = db.collection('users').snapshots();
      _connectionsStream = _buildConnections(uid);
    }
  }

  // ---------- WHO I'VE INTERACTED WITH ----------

  String? _pickId(Map<String, dynamic>? m, List<String> keys) {
    if (m == null) return null;
    for (final k in keys) {
      final v = m[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  // All sender -> recipient hand-offs of one document: the upload itself plus
  // every step in its history (forwards, approvals, ...)
  Future<List<List<String>>> _pairsFor(
      QueryDocumentSnapshot<Map<String, dynamic>> d) async {
    final data = d.data();
    final sender = _pickId(data, _senderKeys);
    final recipient = _pickId(data, _recipientKeys);

    final stamp = data['updatedAt'] is Timestamp
        ? (data['updatedAt'] as Timestamp).millisecondsSinceEpoch
        : 0;
    final key = '$stamp|$recipient|${data['status']}';

    final cached = _pairCache[d.id];
    if (cached != null && cached.key == key) return cached.pairs;

    final pairs = <List<String>>[];
    if (sender != null && recipient != null) pairs.add([sender, recipient]);

    try {
      final steps = await d.reference.collection('history').get();
      for (final s in steps.docs) {
        final h = s.data();
        final a = _pickId(h, _senderKeys);
        final b = _pickId(h, _recipientKeys);
        if (a != null && b != null) pairs.add([a, b]);
      }
    } catch (_) {
      // can't read the trail: fall back to the document's own fields
    }

    _pairCache[d.id] = _PairEntry(key, pairs);
    return pairs;
  }

  // Everyone who has sent me a document or received one from me
  Stream<Set<String>> _buildConnections(String uid) {
    return FirebaseFirestore.instance
        .collection('documents')
        .snapshots()
        .asyncMap((snap) async {
      final all = await Future.wait(snap.docs.map(_pairsFor));
      final result = <String>{};
      for (final pairs in all) {
        for (final p in pairs) {
          if (p[0] == uid && p[1] != uid) result.add(p[1]);
          if (p[1] == uid && p[0] != uid) result.add(p[0]);
        }
      }
      return result;
    });
  }

  // ---------- UI ----------

  void _openRoom(_Person p) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          otherUid: p.uid,
          otherName: p.name,
          otherOffice: p.office,
          otherPhotoUrl: p.photo,
        ),
      ),
    );
  }

  // Message someone you haven't interacted with yet
  void _newChat() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _NewChatSheet(
        myUid: _uid ?? '',
        onPick: (p) {
          Navigator.pop(sheetContext);
          _openRoom(p);
        },
      ),
    );
  }

  // Long press on a row: delete the whole conversation
  Future<void> _confirmDeleteChat(_ChatItem it, String uid) async {
    if (it.chat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No messages to delete yet.')),
      );
      return;
    }
    final ok = await _confirmDialog(
      context,
      title: 'Delete conversation?',
      body:
      'All messages with ${it.person.name} will be permanently deleted for both of you.',
    );
    if (!ok) return;
    try {
      await _deleteChat(_chatIdFor(uid, it.person.uid));
    } catch (e) {
      if (mounted) _showError(context, 'Could not delete: $e');
    }
  }

  Widget _buildHeader() {
    final topPad = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_C.ink, _C.inkSoft],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => _scaffoldKey.currentState?.openDrawer(),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child:
              const Icon(Icons.menu_rounded, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Chat',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'People you work with',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFFE8F0FE),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  color: _C.blue, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _C.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: _C.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(_ChatItem it, String uid) {
    final p = it.person;
    final chat = it.chat;
    final last = (chat?['lastMessage'] ?? '').toString();
    final mine = chat?['lastSenderId'] == uid;
    final unreadMap = chat?['unread'];
    final unread =
    unreadMap is Map ? (unreadMap[uid] as num?)?.toInt() ?? 0 : 0;

    final subtitle = chat == null
        ? (p.office.isEmpty ? 'Tap to start a chat' : p.office)
        : (mine ? 'You: $last' : last);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openRoom(p),
        onLongPress: () => _confirmDeleteChat(it, uid),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _C.line),
          ),
          child: Row(
            children: [
              _Avatar(name: p.name, photoUrl: p.photo),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _C.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: unread > 0 ? _C.text : _C.muted,
                        fontWeight:
                        unread > 0 ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (it.at != null)
                    Text(
                      _formatStamp(it.at),
                      style: const TextStyle(fontSize: 11, color: _C.faint),
                    ),
                  if (unread > 0) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _C.red,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$unread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _C.paper,
      drawer: const Sidebar(currentPage: 'chat.php'),
      floatingActionButton: uid == null
          ? null
          : FloatingActionButton(
        onPressed: _newChat,
        backgroundColor: _C.blue,
        foregroundColor: Colors.white,
        elevation: 2,
        tooltip: 'New chat',
        child: const Icon(Icons.edit_outlined),
      ),
      body: Column(
        children: [
          _buildHeader(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              style: const TextStyle(fontSize: 14, color: _C.text),
              decoration: InputDecoration(
                hintText: 'Search people or offices...',
                hintStyle: const TextStyle(fontSize: 14, color: _C.faint),
                prefixIcon:
                const Icon(Icons.search_rounded, size: 20, color: _C.faint),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _C.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _C.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _C.blue, width: 1.5),
                ),
              ),
            ),
          ),
          Expanded(
            child: uid == null
                ? const Center(child: Text('Please log in to use chat.'))
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _chatsStream,
              builder: (context, chatSnap) {
                if (chatSnap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load chats: ${chatSnap.error}',
                        textAlign: TextAlign.center,
                        style:
                        const TextStyle(color: _C.red, fontSize: 12),
                      ),
                    ),
                  );
                }
                if (!chatSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _usersStream,
                  builder: (context, userSnap) {
                    if (!userSnap.hasData) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }

                    return StreamBuilder<Set<String>>(
                      stream: _connectionsStream,
                      initialData: const <String>{},
                      builder: (context, connSnap) {
                        final users = {
                          for (final d in userSnap.data!.docs)
                            d.id: _Person.fromUser(d.id, d.data())
                        };
                        final byUid = <String, _ChatItem>{};

                        // 1) Conversations that already have messages
                        for (final d in chatSnap.data!.docs) {
                          final chat = d.data();
                          if (chat['lastMessageAt'] == null) continue;
                          final parts = List<String>.from(
                              chat['participants'] ?? const []);
                          final other = parts.firstWhere((x) => x != uid,
                              orElse: () => '');
                          if (other.isEmpty) continue;
                          final ts = chat['lastMessageAt'];
                          byUid[other] = _ChatItem(
                            person: users[other] ??
                                _Person(
                                    uid: other,
                                    name: 'Unknown user',
                                    office: ''),
                            chat: chat,
                            at: ts is Timestamp ? ts.toDate() : null,
                          );
                        }

                        // 2) People I exchanged documents with (no
                        //    messages needed)
                        for (final other in connSnap.data ?? <String>{}) {
                          if (byUid.containsKey(other)) continue;
                          final person = users[other];
                          if (person == null) continue;
                          byUid[other] = _ChatItem(person: person);
                        }

                        final items = byUid.values.where((it) {
                          if (_query.isEmpty) return true;
                          return it.person.name
                              .toLowerCase()
                              .contains(_query) ||
                              it.person.office
                                  .toLowerCase()
                                  .contains(_query);
                        }).toList();

                        // Latest message first, then people with no
                        // messages yet (A-Z)
                        items.sort((a, b) {
                          if (a.at != null && b.at != null) {
                            return b.at!.compareTo(a.at!);
                          }
                          if (a.at != null) return -1;
                          if (b.at != null) return 1;
                          return a.person.name
                              .toLowerCase()
                              .compareTo(b.person.name.toLowerCase());
                        });

                        if (items.isEmpty) {
                          return _emptyState(
                            byUid.isEmpty
                                ? 'No contacts yet'
                                : 'No matches',
                            byUid.isEmpty
                                ? 'People you send documents to, or receive documents from, appear here automatically.'
                                : 'Nobody matches your search.',
                          );
                        }

                        return ListView.separated(
                          padding:
                          const EdgeInsets.fromLTRB(16, 8, 16, 90),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                          itemBuilder: (context, i) =>
                              _row(items[i], uid),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Bottom sheet used to start a brand-new conversation
class _NewChatSheet extends StatefulWidget {
  final String myUid;
  final void Function(_Person person) onPick;

  const _NewChatSheet({required this.myUid, required this.onPick});

  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _C.line,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'New chat',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _C.ink,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: false,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
                style: const TextStyle(fontSize: 14, color: _C.text),
                decoration: InputDecoration(
                  hintText: 'Search people or offices...',
                  hintStyle: const TextStyle(fontSize: 14, color: _C.faint),
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 20, color: _C.faint),
                  filled: true,
                  fillColor: _C.paper,
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream:
                FirebaseFirestore.instance.collection('users').snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final people = snap.data!.docs
                      .where((d) => d.id != widget.myUid)
                      .map((d) => _Person.fromUser(d.id, d.data()))
                      .where((p) =>
                  _query.isEmpty ||
                      p.name.toLowerCase().contains(_query) ||
                      p.office.toLowerCase().contains(_query))
                      .toList()
                    ..sort((a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()));

                  if (people.isEmpty) {
                    return const Center(
                      child: Text('No people found.',
                          style: TextStyle(color: _C.muted, fontSize: 13)),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    itemCount: people.length,
                    itemBuilder: (context, i) {
                      final p = people[i];
                      return ListTile(
                        onTap: () => widget.onPick(p),
                        leading: _Avatar(
                            name: p.name, photoUrl: p.photo, size: 42),
                        title: Text(
                          p.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _C.ink,
                          ),
                        ),
                        subtitle: p.office.isEmpty
                            ? null
                            : Text(p.office,
                            style: const TextStyle(
                                fontSize: 12, color: _C.muted)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// CHAT ROOM (one-to-one conversation)
// =====================================================================

class ChatRoomScreen extends StatefulWidget {
  final String otherUid;
  final String otherName;
  final String otherOffice;
  final String? otherPhotoUrl;

  const ChatRoomScreen({
    super.key,
    required this.otherUid,
    required this.otherName,
    this.otherOffice = '',
    this.otherPhotoUrl,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  late final String _uid;
  late final String _chatId;
  int _lastCount = -1;

  DocumentReference<Map<String, dynamic>> get _chatRef =>
      FirebaseFirestore.instance.collection('chats').doc(_chatId);

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _chatId = _chatIdFor(_uid, widget.otherUid);
    _markRead();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // Clear my unread counter (only if the chat already exists)
  Future<void> _markRead() async {
    try {
      await _chatRef.update({'unread.$_uid': 0});
    } catch (_) {
      // chat doesn't exist yet, nothing to clear
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _uid.isEmpty) return;
    _controller.clear();

    final db = FirebaseFirestore.instance;
    final msgRef = _chatRef.collection('messages').doc();
    final batch = db.batch();

    batch.set(msgRef, {
      'text': text,
      'senderId': _uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      _chatRef,
      {
        'participants': [_uid, widget.otherUid],
        'lastMessage': text,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': _uid,
        'unread': {widget.otherUid: FieldValue.increment(1)},
      },
      SetOptions(merge: true),
    );

    try {
      await batch.commit();
    } catch (e) {
      if (!mounted) return;
      _controller.text = text; // give the text back so it isn't lost
      _showError(context, 'Message not sent: $e');
    }
  }

  // Long press on a message: delete it, then keep the chat list preview in sync
  Future<void> _deleteMessage(
      DocumentReference<Map<String, dynamic>> ref) async {
    final ok = await _confirmDialog(
      context,
      title: 'Delete message?',
      body: 'This message will be removed for both of you.',
    );
    if (!ok) return;

    try {
      await ref.delete();

      final latest = await _chatRef
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (latest.docs.isEmpty) {
        await _chatRef.update({
          'lastMessage': '',
          'lastMessageAt': FieldValue.delete(),
          'lastSenderId': FieldValue.delete(),
        });
      } else {
        final m = latest.docs.first.data();
        await _chatRef.update({
          'lastMessage': (m['text'] ?? '').toString(),
          'lastMessageAt': m['createdAt'] ?? FieldValue.serverTimestamp(),
          'lastSenderId': m['senderId'],
        });
      }
    } catch (e) {
      if (mounted) _showError(context, 'Could not delete: $e');
    }
  }

  Widget _buildHeader() {
    final topPad = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(12, topPad + 8, 20, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_C.ink, _C.inkSoft],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          _Avatar(
              name: widget.otherName, photoUrl: widget.otherPhotoUrl, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.otherName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                if (widget.otherOffice.isNotEmpty)
                  Text(
                    widget.otherOffice,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data();
    final mine = m['senderId'] == _uid;
    final ts = m['createdAt'];
    // A just-sent message has no server time yet: show it as "now"
    final time = ts is Timestamp ? ts.toDate() : DateTime.now();

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        // Only your own messages can be deleted. To allow deleting received
        // ones too, replace with: () => _deleteMessage(doc.reference)
        onLongPress: mine ? () => _deleteMessage(doc.reference) : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            decoration: BoxDecoration(
              color: mine ? _C.blue : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(mine ? 18 : 4),
                bottomRight: Radius.circular(mine ? 4 : 18),
              ),
              border: mine ? null : Border.all(color: _C.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    (m['text'] ?? '').toString(),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: mine ? Colors.white : _C.text,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  DateFormat('hh:mm a').format(time),
                  style: TextStyle(
                    fontSize: 10,
                    color: mine
                        ? Colors.white.withValues(alpha: 0.7)
                        : _C.faint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.paper,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _chatRef
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .limit(200)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load messages: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _C.red, fontSize: 12),
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;

                // New message from them while this screen is open: clear unread
                if (docs.length != _lastCount) {
                  _lastCount = docs.length;
                  if (docs.isNotEmpty &&
                      docs.first.data()['senderId'] != _uid) {
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _markRead());
                  }
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE8F0FE),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.chat_bubble_outline_rounded,
                                color: _C.blue, size: 26),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Say hi to ${widget.otherName.split(' ').first}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _C.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Messages you send will show up here.',
                            style: TextStyle(fontSize: 12, color: _C.muted),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scroll,
                  reverse: true, // newest at the bottom
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  itemCount: docs.length,
                  itemBuilder: (context, i) => _bubble(docs[i]),
                );
              },
            ),
          ),

          // Message box
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: _C.line)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 14, color: _C.text),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle:
                        const TextStyle(fontSize: 14, color: _C.faint),
                        filled: true,
                        fillColor: _C.paper,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: _C.blue,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _send,
                      child: const SizedBox(
                        width: 46,
                        height: 46,
                        child: Icon(Icons.send_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}