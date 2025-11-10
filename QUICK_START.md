# 🎯 Quick Reference: JSON to SQLite Migration

## TL;DR - Get Started in 3 Steps

```bash
# 1. Run migration script
dart run lib/scripts/migrate_json_to_sqlite.dart

# 2. Verify it worked
sqlite3 assets/database/lnu_maps.db "SELECT COUNT(*) FROM points;"

# 3. Test it
flutter run
```

---

## 📁 Your JSON Structure

If your JSON looks like this:

```json
{
  "buildings": { "CM": {...} },
  "floors": { "floor_1": {...} },
  "points": { "point_1": {...} },
  "adjacencyList": { "point_1": [...] },
  "offsets": { "CM": {...} }
}
```

✅ **You're good to go!** Just run the script.

---

## 🔧 Custom JSON Format?

### Your JSON is different?

Edit `lib/scripts/migrate_json_to_sqlite.dart`:

```dart
// Line ~120 - Customize this function
void _parseJsonStructure(Map<String, dynamic> jsonData, ...) {
  // Add your custom parsing logic here
}
```

Or use the Python script and modify the `parse_json_file()` function.

---

## ⚡ Two Scripts Available

| Script     | When to Use                        | Command                                            |
| ---------- | ---------------------------------- | -------------------------------------------------- |
| **Dart**   | Default, integrated with Flutter   | `dart run lib/scripts/migrate_json_to_sqlite.dart` |
| **Python** | Prefer Python, easier to customize | `python3 scripts/migrate_json_to_sqlite.py`        |

Both do the same thing - choose what you're comfortable with!

---

## 🔍 Verify Migration

```bash
# Check database exists
ls -lh assets/database/lnu_maps.db

# Check data counts
sqlite3 assets/database/lnu_maps.db << EOF
SELECT 'Buildings:', COUNT(*) FROM buildings;
SELECT 'Floors:', COUNT(*) FROM floors;
SELECT 'Points:', COUNT(*) FROM points;
SELECT 'Edges:', COUNT(*) FROM edges;
EOF

# Check sample data
sqlite3 assets/database/lnu_maps.db "SELECT * FROM points WHERE label IS NOT NULL LIMIT 5;"
```

---

## 🐛 Common Issues

### "File not found: assets/CM.nodes.json"

**Fix:** Update the file path in the script:

```dart
static const List<String> jsonFilePaths = [
  'assets/YOUR_ACTUAL_FILE.json',  // ← Change this
];
```

### "Foreign key constraint failed"

**Fix:** Your data has orphaned references. The script will show warnings - check your JSON data integrity.

### Migration runs but app crashes

**Fix:**

1. Check database exists: `ls assets/database/lnu_maps.db`
2. Verify pubspec.yaml has: `- assets/database/lnu_maps.db`
3. Run `flutter clean && flutter pub get`

---

## 📊 Expected Output

```
🚀 Starting JSON to SQLite migration...

📦 Creating database...
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
```

If you see this ↑ you're done! 🎉

---

## 🚀 What's Next?

1. ✅ Migration done → Database created
2. 📱 Run your app: `flutter run`
3. 🧪 Everything should work automatically
4. 📚 Want to understand more? Read `docs/MIGRATION_GUIDE.md`

---

## 💡 Pro Tips

-   **Backup first:** `cp assets/CM.nodes.json assets/CM.nodes.json.backup`
-   **Test with small dataset:** Create a small JSON file first
-   **Check indexes:** They massively improve performance
-   **Use SQLite browser:** Great for visual inspection

---

## 🆘 Still Stuck?

1. Check `docs/DATA_MIGRATION_GUIDE.md` - detailed troubleshooting
2. Verify your JSON structure matches expected format
3. Run with debug: Add `print()` statements in the script
4. Check file permissions: Ensure assets/ folder is writable

---

## 🎓 Learn More

-   **Architecture:** `docs/MIGRATION_GUIDE.md`
-   **Data Migration:** `docs/DATA_MIGRATION_GUIDE.md`
-   **Widget Examples:** `docs/before_after_examples.md`
-   **Configuration:** `docs/database_config_guide.md`

---

**Ready?** Run: `dart run lib/scripts/migrate_json_to_sqlite.dart` 🚀
