#!/usr/bin/env python3
"""
JSON to SQLite Migration Script (Python version)

Simple alternative to the Dart script if you prefer Python.

Usage:
    python3 scripts/migrate_json_to_sqlite.py

Requirements:
    pip install sqlite3  (usually built-in with Python)
"""

import json
import sqlite3
import os
from pathlib import Path

# Configuration
JSON_FILES = [
    'assets/CM.nodes.json',
    # Add more files here
]
OUTPUT_DB = 'assets/database/lnu_maps.db'

def create_schema(cursor):
    """Create database schema"""
    print('📦 Creating schema...')
    
    # Structures table (Корпуси)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS structures (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            subtitle TEXT,
            default_building_id TEXT,
            location_address TEXT,
            location_city TEXT,
            location_coordinates TEXT
        )
    ''')
    
    # Buildings table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS buildings (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            subtitle TEXT,
            structure_id TEXT NOT NULL,
            default_floor_id TEXT NOT NULL,
            offset_x REAL DEFAULT 0,
            offset_y REAL DEFAULT 0,
            FOREIGN KEY (structure_id) REFERENCES structures(id)
        )
    ''')
    
    # Floors table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS floors (
            id TEXT PRIMARY KEY,
            building_id TEXT NOT NULL,
            name TEXT NOT NULL,
            z REAL NOT NULL,
            background TEXT NOT NULL,
            subtitle TEXT,
            FOREIGN KEY (building_id) REFERENCES buildings(id)
        )
    ''')
    
    # Points table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS points (
            id TEXT PRIMARY KEY,
            x REAL NOT NULL,
            y REAL NOT NULL,
            building_id TEXT NOT NULL,
            floor_id TEXT NOT NULL,
            label TEXT,
            type TEXT,
            FOREIGN KEY (building_id) REFERENCES buildings(id),
            FOREIGN KEY (floor_id) REFERENCES floors(id)
        )
    ''')
    
    # Edges table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS edges (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            from_point_id TEXT NOT NULL,
            to_point_id TEXT NOT NULL,
            weight REAL NOT NULL,
            FOREIGN KEY (from_point_id) REFERENCES points(id),
            FOREIGN KEY (to_point_id) REFERENCES points(id)
        )
    ''')
    
    print('   ✓ Schema created')

def create_indexes(cursor):
    """Create database indexes for performance"""
    print('⚡ Creating indexes...')
    
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_buildings_structure ON buildings(structure_id)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_points_label ON points(label)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_points_floor ON points(floor_id)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_points_building ON points(building_id)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_edges_from ON edges(from_point_id)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_floors_building ON floors(building_id)')
    
    print('   ✓ Created 6 indexes')

def parse_json_file(json_path: str) -> dict[str, any]:
    """
    Parse the JSON file and extract structures, buildings, floors, points, and edges.
    
    Actual JSON structure:
    {
        "id": "CM",
        "name": "Головний Корпус",
        "defaultBuilding": "CM/BM",
        "location": {...},
        "buildings": {
            "CM/BM": {
                "floors": {
                    "CM/BM/F1": {...}
                }
            }
        },
        "points": {...},
        "nodes": {...}  // adjacency list (edges)
    }
    """
    print(f"Reading JSON file: {json_path}")
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    result = {
        'structures': [],
        'buildings': [],
        'floors': [],
        'points': [],
        'edges': []
    }
    
    # Parse structure (Корпус) - top level
    structure_id = data.get('id', 'unknown')
    location = data.get('location', {})
    result['structures'].append({
        'id': structure_id,
        'name': data.get('name', structure_id),
        'subtitle': data.get('subtitle'),
        'default_building_id': data.get('defaultBuilding'),
        'location_address': location.get('address'),
        'location_city': location.get('city'),
        'location_coordinates': json.dumps(location.get('coordinates')) if location.get('coordinates') else None
    })
    print(f"Structure: {result['structures'][0]['name']} ({structure_id})")
    
    # Parse buildings
    buildings_data = data.get('buildings', {})
    print(f"Parsing {len(buildings_data)} buildings...")
    for building_id, building in buildings_data.items():
        result['buildings'].append({
            'id': building_id,
            'name': building.get('name', building_id),
            'subtitle': building.get('subtitle'),
            'structure_id': structure_id,  # Link to parent structure
            'default_floor_id': building.get('defaultFloor'),
            'offset_x': building.get('offset', {}).get('x', 0),
            'offset_y': building.get('offset', {}).get('y', 0)
        })
        
        # Parse floors nested within buildings
        floors_data = building.get('floors', {})
        for floor_id, floor in floors_data.items():
            result['floors'].append({
                'id': floor_id,
                'building_id': building_id,  # Use parent building_id
                'name': floor.get('name', floor_id),
                'z': floor.get('z', 0),
                'background': floor.get('background'),
                'subtitle': floor.get('subtitle')
            })
    
    print(f"Found {len(result['buildings'])} buildings and {len(result['floors'])} floors")
    
    # Parse points
    points_data = data.get('points', {})
    print(f"Parsing {len(points_data)} points...")
    for point_id, point in points_data.items():
        result['points'].append({
            'id': point_id,
            'x': point.get('x', 0),
            'y': point.get('y', 0),
            'building_id': point.get('buildingId'),
            'floor_id': point.get('floorId'),
            'label': point.get('label'),
            'kind': point.get('kind'),
            'color': point.get('color')
        })
    
    # Parse edges from adjacency list (called "nodes" in JSON)
    adjacency_data = data.get('nodes', {})
    print(f"Parsing edges from {len(adjacency_data)} nodes...")
    edge_id = 1
    for from_id, neighbors in adjacency_data.items():
        for to_id, weight in neighbors.items():
            result['edges'].append({
                'id': edge_id,
                'from_point_id': from_id,
                'to_point_id': to_id,
                'weight': weight
            })
            edge_id += 1
    
    print(f"Parsed 1 structure, {len(result['buildings'])} buildings, {len(result['floors'])} floors, "
          f"{len(result['points'])} points, {len(result['edges'])} edges")
    
    return result

def insert_data(cursor, data):
    """Insert parsed data into database"""
    print('💾 Inserting data...')
    
    # Insert structures first (parent table)
    for structure in data['structures']:
        cursor.execute('''
            INSERT INTO structures (id, name, subtitle, default_building_id, location_address, location_city, location_coordinates)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (
            structure['id'],
            structure['name'],
            structure['subtitle'],
            structure['default_building_id'],
            structure['location_address'],
            structure['location_city'],
            structure['location_coordinates']
        ))
    print(f'   ✓ Inserted {len(data["structures"])} structures')
    
    # Insert buildings
    for building in data['buildings']:
        cursor.execute('''
            INSERT INTO buildings (id, name, subtitle, structure_id, default_floor_id, offset_x, offset_y)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (
            building['id'],
            building['name'],
            building['subtitle'],
            building['structure_id'],
            building['default_floor_id'],
            building['offset_x'],
            building['offset_y']
        ))
    print(f'   ✓ Inserted {len(data["buildings"])} buildings')
    
    # Insert floors
    for floor in data['floors']:
        cursor.execute('''
            INSERT INTO floors (id, building_id, name, z, background, subtitle)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (
            floor['id'],
            floor['building_id'],
            floor['name'],
            floor['z'],
            floor['background'],
            floor['subtitle']
        ))
    print(f'   ✓ Inserted {len(data["floors"])} floors')
    
    # Insert points
    for point in data['points']:
        cursor.execute('''
            INSERT INTO points (id, x, y, building_id, floor_id, label, type)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (
            point['id'],
            point['x'],
            point['y'],
            point['building_id'],
            point['floor_id'],
            point['label'],
            point.get('kind')  # Use 'kind' from parsed data
        ))
    print(f'   ✓ Inserted {len(data["points"])} points')
    
    # Insert edges
    for edge in data['edges']:
        cursor.execute('''
            INSERT INTO edges (from_point_id, to_point_id, weight)
            VALUES (?, ?, ?)
        ''', (
            edge['from_point_id'],
            edge['to_point_id'],
            edge['weight']
        ))
    print(f'   ✓ Inserted {len(data["edges"])} edges')

def verify_data(cursor):
    """Verify migrated data"""
    print('🔍 Verifying data...')
    
    cursor.execute('SELECT COUNT(*) FROM buildings')
    buildings = cursor.fetchone()[0]
    print(f'   ✓ Buildings: {buildings}')
    
    cursor.execute('SELECT COUNT(*) FROM floors')
    floors = cursor.fetchone()[0]
    print(f'   ✓ Floors: {floors}')
    
    cursor.execute('SELECT COUNT(*) FROM points')
    points = cursor.fetchone()[0]
    print(f'   ✓ Points: {points}')
    
    cursor.execute('SELECT COUNT(*) FROM edges')
    edges = cursor.fetchone()[0]
    print(f'   ✓ Edges: {edges}')
    
    # Check for orphaned data
    cursor.execute('''
        SELECT COUNT(*) FROM points 
        WHERE building_id NOT IN (SELECT id FROM buildings)
    ''')
    orphaned = cursor.fetchone()[0]
    if orphaned > 0:
        print(f'   ⚠️  Warning: {orphaned} orphaned points found')

def main():
    print('🚀 Starting JSON to SQLite migration...\n')
    
    # Ensure output directory exists
    os.makedirs(os.path.dirname(OUTPUT_DB), exist_ok=True)
    
    # Delete existing database
    if os.path.exists(OUTPUT_DB):
        os.remove(OUTPUT_DB)
        print('   Deleted existing database\n')
    
    # Connect to database
    conn = sqlite3.connect(OUTPUT_DB)
    cursor = conn.cursor()
    
    # Enable foreign keys
    cursor.execute('PRAGMA foreign_keys = ON')
    
    try:
        # Create schema
        create_schema(cursor)
        
        # Parse all JSON files
        print('\n📖 Reading JSON files...')
        all_data = {
            'structures': [],
            'buildings': [],
            'floors': [],
            'points': [],
            'edges': []
        }
        
        for json_file in JSON_FILES:
            if os.path.exists(json_file):
                data = parse_json_file(json_file)
                all_data['structures'].extend(data['structures'])
                all_data['buildings'].extend(data['buildings'])
                all_data['floors'].extend(data['floors'])
                all_data['points'].extend(data['points'])
                all_data['edges'].extend(data['edges'])
            else:
                print(f'   ⚠️  File not found: {json_file}')
        
        print(f'\n   ✓ Total parsed:')
        print(f'     - {len(all_data["structures"])} structures')
        print(f'     - {len(all_data["buildings"])} buildings')
        print(f'     - {len(all_data["floors"])} floors')
        print(f'     - {len(all_data["points"])} points')
        print(f'     - {len(all_data["edges"])} edges')
        
        # Insert data
        print()
        insert_data(cursor, all_data)
        
        # Create indexes
        print()
        create_indexes(cursor)
        
        # Verify
        print()
        verify_data(cursor)
        
        # Commit changes before VACUUM (VACUUM cannot run in a transaction)
        conn.commit()
        
        # Optimize database
        print('\n⚡ Optimizing database...')
        cursor.execute('VACUUM')
        cursor.execute('ANALYZE')
        print('   ✓ Optimized')
        
        print(f'\n✅ Migration completed successfully!')
        print(f'📁 Database created at: {os.path.abspath(OUTPUT_DB)}')
        
    except Exception as e:
        print(f'\n❌ Migration failed: {e}')
        import traceback
        traceback.print_exc()
        conn.rollback()
        return 1
    finally:
        conn.close()
    
    return 0

if __name__ == '__main__':
    exit(main())
