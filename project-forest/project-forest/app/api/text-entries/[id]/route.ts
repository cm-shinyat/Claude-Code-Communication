import { NextRequest, NextResponse } from 'next/server';
import { executeQuery } from '@/lib/database';
import { TextEntry, Translation, EditHistory } from '@/lib/types';

export async function GET(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const id = parseInt(params.id);
    
    if (isNaN(id)) {
      return NextResponse.json(
        { error: 'Invalid ID' },
        { status: 400 }
      );
    }

    // Get text entry
    const textEntry = await executeQuery<TextEntry>(
      'SELECT * FROM text_entries WHERE id = ?',
      [id]
    );

    if (textEntry.length === 0) {
      return NextResponse.json(
        { error: 'Text entry not found' },
        { status: 404 }
      );
    }

    // Get translations
    const translations = await executeQuery<Translation>(
      'SELECT * FROM translations WHERE text_entry_id = ?',
      [id]
    );

    // Get edit history
    const history = await executeQuery<EditHistory & { editor_name: string }>(
      `SELECT eh.*, u.username as editor_name
       FROM edit_history eh
       LEFT JOIN users u ON eh.edited_by = u.id
       WHERE eh.text_entry_id = ?
       ORDER BY eh.created_at DESC
       LIMIT 100`,
      [id]
    );

    // Get active edit sessions
    const activeSessions = await executeQuery(
      `SELECT es.*, u.username
       FROM edit_sessions es
       LEFT JOIN users u ON es.user_id = u.id
       WHERE es.text_entry_id = ? AND es.is_active = TRUE
       AND es.last_activity > DATE_SUB(NOW(), INTERVAL 5 MINUTE)`,
      [id]
    );

    return NextResponse.json({
      ...textEntry[0],
      translations,
      history,
      activeSessions,
    });
  } catch (error) {
    console.error('Error fetching text entry:', error);
    return NextResponse.json(
      { error: 'Failed to fetch text entry' },
      { status: 500 }
    );
  }
}

export async function PUT(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const id = parseInt(params.id);
    const body = await request.json();
    
    if (isNaN(id)) {
      return NextResponse.json(
        { error: 'Invalid ID' },
        { status: 400 }
      );
    }

    const {
      label,
      file_category,
      original_text,
      status,
      max_chars,
      max_lines,
      updated_by,
      language_code = 'ja',
    } = body;

    // Get current entry for history
    const currentEntry = await executeQuery<TextEntry>(
      'SELECT * FROM text_entries WHERE id = ?',
      [id]
    );

    if (currentEntry.length === 0) {
      return NextResponse.json(
        { error: 'Text entry not found' },
        { status: 404 }
      );
    }

    const oldText = currentEntry[0].original_text;

    // Update text entry
    const updateQuery = `
      UPDATE text_entries 
      SET label = ?, file_category = ?, original_text = ?, status = ?, 
          max_chars = ?, max_lines = ?, updated_by = ?, updated_at = NOW()
      WHERE id = ?
    `;

    await executeQuery(updateQuery, [
      label,
      file_category,
      original_text,
      status,
      max_chars,
      max_lines,
      updated_by,
      id,
    ]);

    // Create edit history entry
    await executeQuery(
      `INSERT INTO edit_history 
       (text_entry_id, language_code, old_text, new_text, edited_by, edit_type)
       VALUES (?, ?, ?, ?, ?, 'update')`,
      [id, language_code, oldText, original_text, updated_by]
    );

    // Get updated entry
    const updatedEntry = await executeQuery<TextEntry>(
      'SELECT * FROM text_entries WHERE id = ?',
      [id]
    );

    return NextResponse.json(updatedEntry[0]);
  } catch (error) {
    console.error('Error updating text entry:', error);
    return NextResponse.json(
      { error: 'Failed to update text entry' },
      { status: 500 }
    );
  }
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const id = parseInt(params.id);
    
    if (isNaN(id)) {
      return NextResponse.json(
        { error: 'Invalid ID' },
        { status: 400 }
      );
    }

    // Check if entry exists
    const entry = await executeQuery<TextEntry>(
      'SELECT * FROM text_entries WHERE id = ?',
      [id]
    );

    if (entry.length === 0) {
      return NextResponse.json(
        { error: 'Text entry not found' },
        { status: 404 }
      );
    }

    // Delete text entry (cascade will handle related records)
    await executeQuery('DELETE FROM text_entries WHERE id = ?', [id]);

    return NextResponse.json({ message: 'Text entry deleted successfully' });
  } catch (error) {
    console.error('Error deleting text entry:', error);
    return NextResponse.json(
      { error: 'Failed to delete text entry' },
      { status: 500 }
    );
  }
}