import 'package:flutter/material.dart';

import '../../models/trusted_contact.dart';
import '../../services/contacts_service.dart';
import 'add_contact_dialog.dart';

class ContactsScreen extends StatelessWidget {
  final ContactsService contactsService;
  final String uid;

  const ContactsScreen({
    super.key,
    required this.contactsService,
    required this.uid,
  });

  Future<void> _openAddDialog(BuildContext context, int currentCount) async {
    if (currentCount >= ContactsService.maxContacts) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'You can only have up to ${ContactsService.maxContacts} contacts.')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => AddContactDialog(
        contactsService: contactsService,
        uid: uid,
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, TrustedContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove contact?'),
        content: Text('${contact.name} will no longer be alerted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true) {
      await contactsService.deleteContact(uid: uid, contactId: contact.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trusted contacts')),
      body: StreamBuilder<List<TrustedContact>>(
        stream: contactsService.watchContacts(uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final contacts = snapshot.data!;
          if (contacts.isEmpty) {
            return const _EmptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: contacts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = contacts[i];
              return ListTile(
                leading: CircleAvatar(child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?')),
                title: Text(c.name),
                subtitle: Text('${c.phone}\n${c.email}'),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context, c),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: StreamBuilder<List<TrustedContact>>(
        stream: contactsService.watchContacts(uid),
        builder: (context, snapshot) {
          final count = snapshot.data?.length ?? 0;
          return FloatingActionButton.extended(
            onPressed: () => _openAddDialog(context, count),
            icon: const Icon(Icons.person_add),
            label: const Text('Add'),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No trusted contacts yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Add up to ${ContactsService.maxContacts} people who should be alerted if you don\'t check in.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}