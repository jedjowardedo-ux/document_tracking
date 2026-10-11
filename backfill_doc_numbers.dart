import 'package:cloud_firestore/cloud_firestore.dart';

/// Numbers every existing document 1, 2, 3... (oldest first) and sets the
/// counter so the next upload continues from the last number.
Future<int> backfillDocNumbers() async {
  final db = FirebaseFirestore.instance;
  final snap = await db.collection('documents').orderBy('createdAt').get();

  final batch = db.batch();
  var n = 0;
  for (final d in snap.docs) {
    n++;
    batch.update(d.reference, {'docNumber': n});
  }
  batch.set(db.collection('counters').doc('documents'), {'last': n});

  await batch.commit();
  return n;
}