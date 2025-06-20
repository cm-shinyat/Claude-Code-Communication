import { NextRequest, NextResponse } from 'next/server';
import { executeQuery } from '@/lib/database';
import { TextEntry, Translation } from '@/lib/types';

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { 
      filters = {}, 
      includeTranslations = true, 
      format = 'csv',
      user_id 
    } = body;

    let whereClause = 'WHERE 1=1';
    const params: any[] = [];

    if (filters.status) {
      whereClause += ' AND te.status = ?';
      params.push(filters.status);
    }

    if (filters.category) {
      whereClause += ' AND te.file_category = ?';
      params.push(filters.category);
    }

    if (filters.search) {
      whereClause += ' AND (te.label LIKE ? OR te.original_text LIKE ?)';
      params.push(`%${filters.search}%`, `%${filters.search}%`);
    }

    // Get text entries
    const query = `
      SELECT 
        te.*,
        creator.username as creator_name,
        updater.username as updater_name
      FROM text_entries te
      LEFT JOIN users creator ON te.created_by = creator.id
      LEFT JOIN users updater ON te.updated_by = updater.id
      ${whereClause}
      ORDER BY te.id ASC
    `;

    const textEntries = await executeQuery<TextEntry & { creator_name?: string; updater_name?: string }>(query, params);

    let csvData: any[] = [];

    if (includeTranslations) {
      // Get all translations for the entries
      const entryIds = textEntries.map(entry => entry.id);
      if (entryIds.length > 0) {
        const translations = await executeQuery<Translation>(
          `SELECT * FROM translations WHERE text_entry_id IN (${entryIds.map(() => '?').join(',')})`,
          entryIds
        );

        // Group translations by entry
        const translationsByEntry = translations.reduce((acc, translation) => {
          if (!acc[translation.text_entry_id]) {
            acc[translation.text_entry_id] = [];
          }
          acc[translation.text_entry_id].push(translation);
          return acc;
        }, {} as Record<number, Translation[]>);

        // Create CSV rows with translations
        csvData = textEntries.flatMap(entry => {
          const entryTranslations = translationsByEntry[entry.id] || [];
          
          if (entryTranslations.length === 0) {
            return [{
              id: entry.id,
              label: entry.label,
              file_category: entry.file_category || '',
              original_text: entry.original_text || '',
              language_code: entry.language_code,
              translated_text: '',
              status: entry.status,
              max_chars: entry.max_chars || '',
              max_lines: entry.max_lines || '',
              created_at: entry.created_at,
              updated_at: entry.updated_at,
            }];
          }

          return entryTranslations.map(translation => ({
            id: entry.id,
            label: entry.label,
            file_category: entry.file_category || '',
            original_text: entry.original_text || '',
            language_code: translation.language_code,
            translated_text: translation.translated_text || '',
            status: translation.status,
            max_chars: entry.max_chars || '',
            max_lines: entry.max_lines || '',
            created_at: entry.created_at,
            updated_at: entry.updated_at,
          }));
        });
      }
    } else {
      csvData = textEntries.map(entry => ({
        id: entry.id,
        label: entry.label,
        file_category: entry.file_category || '',
        original_text: entry.original_text || '',
        language_code: entry.language_code,
        status: entry.status,
        max_chars: entry.max_chars || '',
        max_lines: entry.max_lines || '',
        created_at: entry.created_at,
        updated_at: entry.updated_at,
      }));
    }

    // Convert to CSV
    if (csvData.length === 0) {
      return NextResponse.json({ error: 'No data to export' }, { status: 400 });
    }

    const headers = Object.keys(csvData[0]);
    const csvRows = [
      headers.join(','),
      ...csvData.map(row => 
        headers.map(header => {
          const value = row[header]?.toString() || '';
          // Escape quotes and wrap in quotes if contains comma, quote, or newline
          if (value.includes(',') || value.includes('"') || value.includes('\n')) {
            return `"${value.replace(/"/g, '""')}"`;
          }
          return value;
        }).join(',')
      )
    ];

    const csvContent = csvRows.join('\n');
    const filename = `text_entries_${new Date().toISOString().split('T')[0]}.csv`;

    // Log export
    await executeQuery(
      `INSERT INTO file_history 
       (filename, file_type, file_format, record_count, status, user_id)
       VALUES (?, 'export', 'csv', ?, 'success', ?)`,
      [filename, csvData.length, user_id]
    );

    return new NextResponse(csvContent, {
      headers: {
        'Content-Type': 'text/csv',
        'Content-Disposition': `attachment; filename="${filename}"`,
      },
    });
  } catch (error) {
    console.error('Error exporting CSV:', error);
    return NextResponse.json(
      { error: 'Failed to export CSV' },
      { status: 500 }
    );
  }
}