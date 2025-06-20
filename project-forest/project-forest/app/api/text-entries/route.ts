import { NextRequest, NextResponse } from 'next/server';
import { executeQuery } from '@/lib/database';
import { TextEntry, Translation } from '@/lib/types';

export async function GET(request: NextRequest) {
  try {
    const searchParams = request.nextUrl.searchParams;
    const page = parseInt(searchParams.get('page') || '1');
    const limit = parseInt(searchParams.get('limit') || '50');
    const search = searchParams.get('search') || '';
    const status = searchParams.get('status') || '';
    const category = searchParams.get('category') || '';
    const offset = (page - 1) * limit;

    let whereClause = 'WHERE 1=1';
    const params: any[] = [];

    if (search) {
      whereClause += ' AND (te.label LIKE ? OR te.original_text LIKE ?)';
      params.push(`%${search}%`, `%${search}%`);
    }

    if (status) {
      whereClause += ' AND te.status = ?';
      params.push(status);
    }

    if (category) {
      whereClause += ' AND te.file_category = ?';
      params.push(category);
    }

    const query = `
      SELECT 
        te.*,
        creator.username as creator_name,
        updater.username as updater_name,
        COUNT(*) OVER() as total_count
      FROM text_entries te
      LEFT JOIN users creator ON te.created_by = creator.id
      LEFT JOIN users updater ON te.updated_by = updater.id
      ${whereClause}
      ORDER BY te.updated_at DESC
      LIMIT ? OFFSET ?
    `;

    params.push(limit, offset);
    const textEntries = await executeQuery<TextEntry & { creator_name?: string; updater_name?: string; total_count: number }>(query, params);

    const totalCount = textEntries.length > 0 ? textEntries[0].total_count : 0;
    const totalPages = Math.ceil(totalCount / limit);

    // Get translations for each text entry
    const entriesWithTranslations = await Promise.all(
      textEntries.map(async (entry) => {
        const translations = await executeQuery<Translation>(
          'SELECT * FROM translations WHERE text_entry_id = ?',
          [entry.id]
        );
        return { ...entry, translations };
      })
    );

    return NextResponse.json({
      data: entriesWithTranslations,
      pagination: {
        page,
        limit,
        total: totalCount,
        totalPages,
        hasNext: page < totalPages,
        hasPrev: page > 1,
      },
    });
  } catch (error) {
    console.error('Error fetching text entries:', error);
    return NextResponse.json(
      { error: 'Failed to fetch text entries' },
      { status: 500 }
    );
  }
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const {
      label,
      file_category,
      original_text,
      language_code = 'ja',
      max_chars,
      max_lines,
      created_by,
    } = body;

    if (!label) {
      return NextResponse.json(
        { error: 'Label is required' },
        { status: 400 }
      );
    }

    const query = `
      INSERT INTO text_entries 
      (label, file_category, original_text, language_code, max_chars, max_lines, created_by, updated_by)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `;

    const result = await executeQuery(query, [
      label,
      file_category,
      original_text,
      language_code,
      max_chars,
      max_lines,
      created_by,
      created_by,
    ]);

    const insertResult = result as any;
    const newEntryId = insertResult.insertId;

    // Create edit history entry
    await executeQuery(
      `INSERT INTO edit_history 
       (text_entry_id, language_code, new_text, edited_by, edit_type)
       VALUES (?, ?, ?, ?, 'create')`,
      [newEntryId, language_code, original_text, created_by]
    );

    // Fetch the created entry
    const createdEntry = await executeQuery<TextEntry>(
      'SELECT * FROM text_entries WHERE id = ?',
      [newEntryId]
    );

    return NextResponse.json(createdEntry[0], { status: 201 });
  } catch (error) {
    console.error('Error creating text entry:', error);
    return NextResponse.json(
      { error: 'Failed to create text entry' },
      { status: 500 }
    );
  }
}