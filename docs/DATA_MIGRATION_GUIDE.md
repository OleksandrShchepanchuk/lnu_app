# JSON to SQLite Data Migration Guide

## 🎯 Goal

Convert your existing JSON map files (like `assets/CM.nodes.json`) into a SQLite database (`assets/database/lnu_maps.db`).

---

## 📋 Prerequisites

1. Your JSON files in the `assets/` folder
2. Dart SDK installed
3. Dependencies installed: `flutter pub get`

---

## 🚀 Method 1: Automated Migration Script (Recommended)

### Step 1: Prepare Your JSON Files

Make sure your JSON files are in the expected format. Example structure:

```json
{
    "buildings": {
        "CM": {
            "name": "Central Main Building",
            "subtitle": "Main Campus",
            "defaultFloor": "floor_1"
        }
    },
    "floors": {
        "floor_1": {
            "buildingId": "CM",
            "name": "Ground Floor",
            "z": 0,
            "background": "assets/s/p/z1.svg"
        }
    },
    "points": {
        "point_1": {
            "x": 100.5,
            "y": 200.3,
            "buildingId": "CM",
            "floorId": "floor_1",
            "label": "Room 101",
            "type": "room"
        }
    },
    "adjacencyList": {
        "point_1": [
            {
                "pointId": "point_2",
                "weight": 5.0
            }
        ]
    },
    "offsets": {
        "CM": {
            "x": 100.0,
            "y": 200.0
        }
    }
}
```

### Step 2: Configure the Migration Script

Edit `lib/scripts/migrate_json_to_sqlite.dart`:

```dart
static const List<String> jsonFilePaths = [
  'assets/CM.nodes.json',        // Your main JSON file
  'assets/other_building.json',  // Add more if needed
];
```

### Step 3: Run the Migration

```bash
dart run lib/scripts/migrate_json_to_sqlite.dart
```

**Expected output:**

```
🚀 Starting JSON to SQLite migration...

📦 Creating database...
   Deleted existing database
   ✓ Database created
   ✓ Schema created
📖 Reading JSON files...
   Reading: assets/CM.nodes.json
   ✓ Parsed 5 buildings
   ✓ Parsed 15 floors
   ✓ Parsed 1247 points
   ✓ Parsed 3542 edges
💾 Inserting data into database...
   ✓ Inserted 5 buildings
   ✓ Inserted 15 floors
   ✓ Inserted 1247 points
   ✓ Inserted 3542 edges
⚡ Creating indexes...
   ✓ Created 5 indexes
🔍 Verifying data...
   ✓ Buildings: 5
   ✓ Floors: 15
   ✓ Points: 1247
   ✓ Edges: 3542

✅ Migration completed successfully!
📁 Database created at: /path/to/lnu_app/assets/database/lnu_maps.db
```

### Step 4: Verify the Database

Use DB Browser for SQLite or command line:

```bash
# Install sqlite3 if needed
sudo apt install sqlite3  # Linux
brew install sqlite3      # macOS

# Open the database
sqlite3 assets/database/lnu_maps.db

# Run some queries
sqlite> .tables
sqlite> SELECT COUNT(*) FROM points;
sqlite> SELECT * FROM buildings LIMIT 5;
sqlite> .quit
```

### Step 5: Add to Assets

Verify it's in your `pubspec.yaml`:

```yaml
flutter:
    assets:
        - assets/database/lnu_maps.db
```

---

## 🔧 Method 2: Custom JSON Structure

If your JSON structure is different, customize the parsing logic:

### Option A: Modify the Parser

Edit `_parseJsonStructure()` in the migration script:

```dart
void _parseJsonStructure(
  Map<String, dynamic> jsonData,
  Map<String, dynamic> allData,
) {
  // YOUR CUSTOM PARSING LOGIC HERE

  // Example: If your JSON has a different structure
  if (jsonData.containsKey('mapData')) {
    final mapData = jsonData['mapData'];

    // Parse your custom format
    for (final building in mapData['buildings']) {
      allData['buildings'].add({
        'id': building['buildingCode'],
        'name': building['buildingName'],
        // ... map your fields
      });
    }
  }
}
```

### Option B: Pre-process JSON

Create a separate script to normalize your JSON first:

```dart
// lib/scripts/normalize_json.dart
import 'dart:convert';
import 'dart:io';

void main() async {
  // Read your custom JSON
  final file = File('assets/your_custom.json');
  final jsonData = json.decode(await file.readAsString());

  // Convert to expected format
  final normalized = {
    'buildings': _convertBuildings(jsonData),
    'floors': _convertFloors(jsonData),
    'points': _convertPoints(jsonData),
    'adjacencyList': _convertEdges(jsonData),
  };

  // Write normalized JSON
  await File('assets/normalized.json').writeAsString(
    json.encode(normalized),
  );

  print('✅ JSON normalized!');
}
```

---

## 🛠️ Method 3: Manual Migration (Alternative)

If you prefer manual control or have a complex structure:

### Step 1: Create Empty Database

```bash
sqlite3 assets/database/lnu_maps.db
```

### Step 2: Create Schema

```sql
-- Copy and paste the schema from MIGRATION_GUIDE.md
CREATE TABLE buildings (...);
CREATE TABLE floors (...);
CREATE TABLE points (...);
CREATE TABLE edges (...);

-- Create indexes
CREATE INDEX idx_points_label ON points(label);
CREATE INDEX idx_points_floor ON points(floor_id);
-- ... etc
```

### Step 3: Convert JSON to SQL

Create a Python/Node.js script:

```python
# convert_json_to_sql.py
import json
import sqlite3

# Load JSON
with open('assets/CM.nodes.json') as f:
    data = json.load(f)

# Connect to database
conn = sqlite3.connect('assets/database/lnu_maps.db')
cursor = conn.cursor()

# Insert buildings
for building_id, building in data['buildings'].items():
    cursor.execute('''
        INSERT INTO buildings (id, name, subtitle, default_floor_id)
        VALUES (?, ?, ?, ?)
    ''', (building_id, building['name'], building.get('subtitle'), building['defaultFloor']))

# Insert points
for point_id, point in data['points'].items():
    cursor.execute('''
        INSERT INTO points (id, x, y, building_id, floor_id, label, type)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', (point_id, point['x'], point['y'], point['buildingId'],
          point['floorId'], point.get('label'), point.get('type')))

# Insert edges
for from_id, neighbors in data['adjacencyList'].items():
    for neighbor in neighbors:
        cursor.execute('''
            INSERT INTO edges (from_point_id, to_point_id, weight)
            VALUES (?, ?, ?)
        ''', (from_id, neighbor['pointId'], neighbor['weight']))

conn.commit()
conn.close()
print('✅ Migration complete!')
```

Run:

```bash
python3 convert_json_to_sql.py
```

---

## 🔍 Troubleshooting

### Error: "JSON structure not recognized"

**Solution:** Your JSON format is different. Customize `_parseJsonStructure()` to match your format.

### Error: "Foreign key constraint failed"

**Solution:** Make sure buildings and floors are inserted before points.

### Warning: "Orphaned points found"

**Solution:** Some points reference non-existent buildings/floors. Check your data integrity:

```sql
-- Find orphaned points
SELECT p.id, p.building_id
FROM points p
WHERE p.building_id NOT IN (SELECT id FROM buildings);
```

### Migration runs but no data

**Solution:** Check if your JSON keys match. Add debug prints:

```dart
print('JSON keys: ${jsonData.keys}');
print('Buildings found: ${jsonData['buildings']}');
```

---

## 📊 Validation

After migration, verify your data:

```bash
sqlite3 assets/database/lnu_maps.db

-- Check counts
SELECT 'Buildings:', COUNT(*) FROM buildings;
SELECT 'Floors:', COUNT(*) FROM floors;
SELECT 'Points:', COUNT(*) FROM points;
SELECT 'Edges:', COUNT(*) FROM edges;

-- Check sample data
SELECT * FROM buildings LIMIT 3;
SELECT * FROM points WHERE label IS NOT NULL LIMIT 5;

-- Check graph connectivity
SELECT
  e.from_point_id,
  p1.label as from_label,
  e.to_point_id,
  p2.label as to_label,
  e.weight
FROM edges e
JOIN points p1 ON e.from_point_id = p1.id
JOIN points p2 ON e.to_point_id = p2.id
LIMIT 10;
```

---

## 🎯 Next Steps

After successful migration:

1. ✅ Verify database file exists at `assets/database/lnu_maps.db`
2. ✅ Run app with `flutter run`
3. ✅ Test map loading and navigation
4. ✅ Check pathfinding works correctly
5. ✅ Monitor app performance
6. ✅ (Optional) Remove old JSON files once confirmed working

---

## 💡 Tips

### Optimize Database Size

```sql
-- After inserting all data
VACUUM;
ANALYZE;
```

### Backup Your Data

```bash
# Before migration
cp assets/CM.nodes.json assets/CM.nodes.json.backup

# After migration
cp assets/database/lnu_maps.db assets/database/lnu_maps.db.backup
```

### Test with Smaller Dataset First

Create a test JSON with just a few points to verify your migration works before running on the full dataset.

---

## 📝 Example: Complete Migration Workflow

```bash
# 1. Backup your JSON
cp assets/CM.nodes.json assets/CM.nodes.json.backup

# 2. Install dependencies
flutter pub get

# 3. Run migration
dart run lib/scripts/migrate_json_to_sqlite.dart

# 4. Verify database
sqlite3 assets/database/lnu_maps.db "SELECT COUNT(*) FROM points;"

# 5. Test in app
flutter run

# 6. If successful, commit
git add assets/database/lnu_maps.db
git commit -m "Add SQLite database with migrated map data"
```

---

## 🆘 Need Help?

1. Check the migration script output for errors
2. Verify your JSON structure matches expected format
3. Use SQLite browser to inspect the database
4. Check foreign key relationships
5. Validate data counts match your JSON

---

**Ready to migrate?** Run: `dart run lib/scripts/migrate_json_to_sqlite.dart`
