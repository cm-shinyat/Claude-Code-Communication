import { NextRequest, NextResponse } from 'next/server';
import { executeQuery, executeTransaction } from '@/lib/database';

export async function POST(request: NextRequest) {
  try {
    const formData = await request.formData();
    const file = formData.get('file') as File;
    const user_id = formData.get('user_id') as string;
    const update_existing = formData.get('update_existing') === 'true';

    if (!file) {
      return NextResponse.json({ error: 'No file provided' }, { status: 400 });
    }

    if (!user_id) {
      return NextResponse.json({ error: 'User ID required' }, { status: 400 });
    }

    const csvContent = await file.text();
    const lines = csvContent.trim().split('\n');
    
    if (lines.length < 2) {
      return NextResponse.json({ error: 'CSV file must have at least a header and one data row' }, { status: 400 });
    }

    const headers = lines[0].split(',').map(h => h.trim().replace(/"/g, ''));
    const requiredHeaders = ['label', 'original_text', 'language_code'];
    
    const missingHeaders = requiredHeaders.filter(header => !headers.includes(header));
    if (missingHeaders.length > 0) {
      return NextResponse.json({ 
        error: `Missing required headers: ${missingHeaders.join(', ')}` 
      }, { status: 400 });
    }

    const results = {
      created: 0,
      updated: 0,
      errors: [] as string[],
      total_rows: lines.length - 1,
    };

    await executeTransaction(async (connection) => {
      for (let i = 1; i < lines.length; i++) {
        try {
          const values = parseCsvLine(lines[i]);
          if (values.length !== headers.length) {
            results.errors.push(`Row ${i + 1}: Column count mismatch`);
            continue;
          }

          const rowData = headers.reduce((obj, header, index) => {
            obj[header] = values[index];
            return obj;
          }, {} as Record<string, string>);

          // Validate required fields
          if (!rowData.label || !rowData.original_text) {
            results.errors.push(`Row ${i + 1}: Missing required fields`);
            continue;
          }

          const language_code = rowData.language_code || 'ja';
          const status = rowData.status || '未処理';
          const file_category = rowData.file_category || null;
          const max_chars = rowData.max_chars ? parseInt(rowData.max_chars) : null;
          const max_lines = rowData.max_lines ? parseInt(rowData.max_lines) : null;

          if (update_existing && rowData.id) {
            // Update existing entry
            const entryId = parseInt(rowData.id);
            if (!isNaN(entryId)) {
              const [existingEntry] = await connection.execute(
                'SELECT * FROM text_entries WHERE id = ?',
                [entryId]
              );

              if ((existingEntry as any[]).length > 0) {
                await connection.execute(
                  `UPDATE text_entries 
                   SET label = ?, file_category = ?, original_text = ?, 
                       language_code = ?, status = ?, max_chars = ?, max_lines = ?,
                       updated_by = ?, updated_at = NOW()
                   WHERE id = ?`,
                  [rowData.label, file_category, rowData.original_text, 
                   language_code, status, max_chars, max_lines, user_id, entryId]
                );

                // Add to history
                await connection.execute(
                  `INSERT INTO edit_history 
                   (text_entry_id, language_code, old_text, new_text, edited_by, edit_type)
                   VALUES (?, ?, ?, ?, ?, 'update')`,
                  [entryId, language_code, (existingEntry as any[])[0].original_text, 
                   rowData.original_text, user_id]
                );

                results.updated++;
                continue;
              }
            }
          }

          // Create new entry
          const [result] = await connection.execute(
            `INSERT INTO text_entries 
             (label, file_category, original_text, language_code, status, 
              max_chars, max_lines, created_by, updated_by)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [rowData.label, file_category, rowData.original_text, 
             language_code, status, max_chars, max_lines, user_id, user_id]
          );

          const newEntryId = (result as any).insertId;

          // Add to history
          await connection.execute(
            `INSERT INTO edit_history 
             (text_entry_id, language_code, new_text, edited_by, edit_type)
             VALUES (?, ?, ?, ?, 'create')`,
            [newEntryId, language_code, rowData.original_text, user_id]
          );

          // Handle translations if provided
          if (rowData.translated_text && language_code !== 'ja') {
            await connection.execute(
              `INSERT INTO translations 
               (text_entry_id, language_code, translated_text, status, translator_id)
               VALUES (?, ?, ?, ?, ?)
               ON DUPLICATE KEY UPDATE 
               translated_text = VALUES(translated_text), 
               status = VALUES(status),
               translator_id = VALUES(translator_id),
               updated_at = NOW()`,
              [newEntryId, language_code, rowData.translated_text, status, user_id]
            );
          }

          results.created++;
        } catch (error) {
          results.errors.push(`Row ${i + 1}: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
      }
    });

    // Log import
    await executeQuery(
      `INSERT INTO file_history 
       (filename, file_type, file_format, record_count, status, user_id, error_message)
       VALUES (?, 'import', 'csv', ?, ?, ?, ?)`,
      [
        file.name, 
        results.created + results.updated, 
        results.errors.length > 0 ? 'success' : 'success', 
        user_id,
        results.errors.length > 0 ? results.errors.join('; ') : null
      ]
    );

    return NextResponse.json(results);
  } catch (error) {
    console.error('Error importing CSV:', error);
    return NextResponse.json(
      { error: 'Failed to import CSV' },
      { status: 500 }
    );
  }
}

function parseCsvLine(line: string): string[] {
  const result: string[] = [];
  let current = '';
  let inQuotes = false;
  let i = 0;

  while (i < line.length) {
    const char = line[i];
    
    if (char === '"') {
      if (inQuotes && line[i + 1] === '"') {
        // Escaped quote
        current += '"';
        i += 2;
      } else {
        // Toggle quote state
        inQuotes = !inQuotes;
        i++;
      }
    } else if (char === ',' && !inQuotes) {
      // Field separator
      result.push(current.trim());
      current = '';
      i++;
    } else {
      current += char;
      i++;
    }
  }
  
  result.push(current.trim());
  return result;
}