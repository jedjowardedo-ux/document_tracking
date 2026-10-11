import 'package:cloud_firestore/cloud_firestore.dart';

// division -> office names (order is preserved and becomes `sort_order`)
const Map<String, List<String>> _officesByDivision = {
  'Executive': [
    'Board of Regents',
    'Office of the University President',
    'Office of the Campus Director',
    'Management Committee',
    'Public Information and Strategic Communications Office',
    'Planning and Strategic Foresight Office',
    'Privacy Compliance Office',
    'Security and Safety Office',
    'Pollution Control and Environmental Stewardship Office',
  ],
  'Administration & Finance': [
    'Office of the VP for Administration and Finance',
    'Personnel and Human Resource Management Office',
    'Information and Communication Technology Office',
    'Gender and Development Office',
    'Supply and Property Management Office',
    'Project Development and Management Office',
    'General Services Office',
    'Records Management Office',
    'Procurement Office',
    'Disaster Risk Reduction and Management Office',
    'Cashiering Office',
    'Accounting Office',
    'Budget Office',
    'Production Office',
  ],
  'Academic Affairs': [
    'Office of the VP for Academics and Quality Assurance',
    'Quality Assurance Office',
    'Instruction Office',
    "Dean's Office",
    'NSTP Office',
    'Instructional Material Development Center',
    'Learning Resource Center',
    'Department Chairs (Academics, RIE)',
  ],
  'Research & Extension': [
    'Office of the VP for Research, Innovation, and Extension',
    'Research Office',
    'Extension Office',
    'Innovation and Technology Support Office',
    'Research Centers',
    'Fabrication Laboratory',
  ],
  'Student Affairs': [
    'Office of the VP for Students Affairs and Services',
    'Admission Office',
    'Registration Office',
    'Scholarships & Financial Assistance Office',
    'Housing and Residential Services Office',
    'Services for Students with Special Needs Office',
    'Health Services Office',
    'Sports Development Office',
    'Culture and Arts Affairs Office',
    'Student Government Office',
    'Student Organization Office',
    'Student Publication Office',
    'Student Discipline Office',
    'Multi-Faith Services Office',
    'Economic Enterprise Office',
    'Guidance and Counseling Services Office',
    'Career and Job Placement Office',
    'Alumni Relations Office',
  ],
  'Colleges': [
    'College of Business and Management',
    'College of Teacher Education',
    'College of Fisheries and Marine Sciences',
    'College of Sciences',
  ],
};

String _slug(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

/// Writes every office to the `offices` collection.
/// Safe to run more than once: each office has a fixed document id, so it
/// updates instead of duplicating. Returns how many offices were written.
Future<int> seedOffices() async {
  final db = FirebaseFirestore.instance;
  final col = db.collection('offices');
  final batch = db.batch();

  var order = 0;
  _officesByDivision.forEach((division, names) {
    for (final name in names) {
      order++;
      batch.set(
        col.doc(_slug(name)),
        {
          'office_name': name, // same column name as your `office` table
          'name': name, // kept so existing widgets that read `name` still work
          'division': division,
          'sort_order': order,
        },
        SetOptions(merge: true),
      );
    }
  });

  await batch.commit();
  return order;
}