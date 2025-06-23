import { NextRequest, NextResponse } from 'next/server';
import { executeQuery } from '@/lib/database';
import { EditHistory } from '@/lib/types';

export async function GET(
  request: NextRequest,
  context: { params: Promise<{ id: string }> }
) {
  try {
    const routeParams = await context.params;
    const id = parseInt(routeParams.id);
    
    if (isNaN(id)) {
      return NextResponse.json(
        { error: 'Invalid ID' },
        { status: 400 }
      );
    }

    const searchParams = request.nextUrl.searchParams;
    const limit = parseInt(searchParams.get('limit') || '50');
    const offset = parseInt(searchParams.get('offset') || '0');

    // Get edit history for the text entry
    const query = `
      SELECT 
        eh.*,
        u.username as editor_name,
        u.role as editor_role
      FROM edit_history eh
      LEFT JOIN users u ON eh.edited_by = u.id
      WHERE eh.text_entry_id = ?
      ORDER BY eh.created_at DESC
      LIMIT ? OFFSET ?
    `;

    const history = await executeQuery<EditHistory & { 
      editor_name: string; 
      editor_role: string 
    }>(query, [id, limit, offset]);

    // Get total count
    const countResult = await executeQuery<{ total: number }>(
      'SELECT COUNT(*) as total FROM edit_history WHERE text_entry_id = ?',
      [id]
    );

    const total = countResult[0]?.total || 0;

    return NextResponse.json({
      data: history,
      pagination: {
        total,
        limit,
        offset,
        hasMore: offset + limit < total,
      },
    });
  } catch (error) {
    console.error('Error fetching edit history:', error);
    return NextResponse.json(
      { error: 'Failed to fetch edit history' },
      { status: 500 }
    );
  }
}

export async function POST(
  request: NextRequest,
  context: { params: Promise<{ id: string }> }
) {
  try {
    const routeParams = await context.params;
    const textEntryId = parseInt(routeParams.id);
    const body = await request.json();
    
    if (isNaN(textEntryId)) {
      return NextResponse.json(
        { error: 'Invalid text entry ID' },
        { status: 400 }
      );
    }

    const { historyId, userId } = body;

    if (!historyId || !userId) {
      return NextResponse.json(
        { error: 'History ID and User ID are required' },
        { status: 400 }
      );
    }

    // Get the history entry to revert to
    const historyEntry = await executeQuery<EditHistory>(
      'SELECT * FROM edit_history WHERE id = ? AND text_entry_id = ?',
      [historyId, textEntryId]
    );

    if (historyEntry.length === 0) {
      return NextResponse.json(
        { error: 'History entry not found' },
        { status: 404 }
      );
    }

    const targetHistory = historyEntry[0];

    // Get current text entry
    const currentEntry = await executeQuery(
      'SELECT * FROM text_entries WHERE id = ?',
      [textEntryId]
    );

    if (currentEntry.length === 0) {
      return NextResponse.json(
        { error: 'Text entry not found' },
        { status: 404 }
      );
    }

    const current = currentEntry[0] as any;
    const revertToText = targetHistory.new_text;

    // Update the text entry
    await executeQuery(
      `UPDATE text_entries 
       SET original_text = ?, updated_by = ?, updated_at = NOW()
       WHERE id = ?`,
      [revertToText, userId, textEntryId]
    );

    // Create new history entry for the revert
    await executeQuery(
      `INSERT INTO edit_history 
       (text_entry_id, language_code, old_text, new_text, edited_by, edit_type)
       VALUES (?, ?, ?, ?, ?, 'update')`,
      [
        textEntryId, 
        targetHistory.language_code, 
        current.original_text, 
        revertToText, 
        userId
      ]
    );

    // Get updated entry
    const updatedEntry = await executeQuery(
      'SELECT * FROM text_entries WHERE id = ?',
      [textEntryId]
    );

    return NextResponse.json({
      message: 'Text entry reverted successfully',
      entry: updatedEntry[0],
    });
  } catch (error) {
    console.error('Error reverting text entry:', error);
    return NextResponse.json(
      { error: 'Failed to revert text entry' },
      { status: 500 }
    );
  }
}