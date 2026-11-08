import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../l10n/app_text.dart';
import '../services/push_relay.dart';
import '../services/safety_service.dart';

/// Chat between a donor and a receiver, available after the donor accepts.
/// Messages live in donor_requests/{id}/messages (only these two people,
/// and only while the request is "accepted").
class ChatScreen extends StatefulWidget {
  final String donorRequestId;
  final String otherUserId;
  final String otherName;

  const ChatScreen({
    super.key,
    required this.donorRequestId,
    required this.otherUserId,
    required this.otherName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const Color _red = Color(0xFFD62839);

  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  DocumentReference<Map<String, dynamic>> get _requestRef => FirebaseFirestore
      .instance
      .collection('donor_requests')
      .doc(widget.donorRequestId);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final user = FirebaseAuth.instance.currentUser;
    final text = _controller.text.trim();
    if (user == null || text.isEmpty || _sending) return;

    setState(() => _sending = true);

    try {
      final sent = await _requestRef.collection('messages').add({
        'senderId': user.uid,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Push to the other person (does nothing if the relay is off).
      PushRelay.notify('message', widget.donorRequestId, messageId: sent.id);

      if (!mounted) return;
      _controller.clear();
    } catch (e) {
      debugPrint('Chat send error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not send the message. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _timeLabel(Timestamp? timestamp) {
    if (timestamp == null) return 'Sending...';
    final date = timestamp.toDate();
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    final now = DateTime.now();
    final sameDay =
        date.year == now.year && date.month == now.month && date.day == now.day;
    return sameDay ? '$hh:$mm' : '${date.day}/${date.month} $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.otherName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => SafetyActions.showMenu(
              context,
              userId: widget.otherUserId,
              name: widget.otherName,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFFFFEBEE),
              child: const Text(
                'Be careful when sharing personal details. BloodConnect does not replace medical advice or emergency services.',
                style: TextStyle(fontSize: 11, color: Color(0xFFB71C1C)),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _requestRef
                    .collection('messages')
                    .orderBy('createdAt', descending: true)
                    .limit(200)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Could not load messages. Please try again.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: _red),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No messages yet. Say hello!'),
                      ),
                    );
                  }

                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data();
                      final mine = data['senderId'] == myUid;
                      final createdAt = data['createdAt'];

                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.76,
                          ),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: mine ? _red : theme.cardColor,
                            borderRadius: BorderRadius.circular(16),
                            border: mine
                                ? null
                                : Border.all(
                                    color: theme.dividerColor.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (data['text'] ?? '').toString(),
                                style: TextStyle(
                                  color: mine
                                      ? Colors.white
                                      : theme.colorScheme.onSurface,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _timeLabel(
                                  createdAt is Timestamp ? createdAt : null,
                                ),
                                style: TextStyle(
                                  fontSize: 9,
                                  color: mine
                                      ? Colors.white70
                                      : theme.colorScheme.onSurface.withValues(
                                          alpha: 0.5,
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _requestRef.snapshots(),
              builder: (context, snapshot) {
                final status = (snapshot.data?.data()?['status'] ?? '')
                    .toString()
                    .toLowerCase();

                if (snapshot.hasData && status != 'accepted') {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    alignment: Alignment.center,
                    child: Text(
                      'This chat is closed.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.send,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(1000),
                          ],
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(
                            hintText: 'Type a message',
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(
                        onPressed: _sending ? null : _send,
                        style: IconButton.styleFrom(backgroundColor: _red),
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
