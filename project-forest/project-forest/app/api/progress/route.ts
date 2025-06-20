import { NextRequest, NextResponse } from 'next/server';
import { executeQuery } from '@/lib/database';

export async function GET(request: NextRequest) {
  try {
    const searchParams = request.nextUrl.searchParams;
    const groupBy = searchParams.get('groupBy') || 'status';
    const category = searchParams.get('category');

    let whereClause = 'WHERE 1=1';
    const params: any[] = [];

    if (category) {
      whereClause += ' AND file_category = ?';
      params.push(category);
    }

    let query = '';
    
    if (groupBy === 'status') {
      query = `
        SELECT 
          status,
          COUNT(*) as count,
          COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() as percentage
        FROM text_entries
        ${whereClause}
        GROUP BY status
        ORDER BY 
          CASE status
            WHEN '未処理' THEN 1
            WHEN '確認依頼' THEN 2
            WHEN '原文相談' THEN 3
            WHEN '完了' THEN 4
            WHEN 'オミット' THEN 5
            ELSE 6
          END
      `;
    } else if (groupBy === 'category') {
      query = `
        SELECT 
          COALESCE(file_category, 'その他') as category,
          COUNT(*) as count,
          COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() as percentage,
          SUM(CASE WHEN status = '完了' THEN 1 ELSE 0 END) as completed,
          SUM(CASE WHEN status = '未処理' THEN 1 ELSE 0 END) as pending,
          SUM(CASE WHEN status = '確認依頼' THEN 1 ELSE 0 END) as review_requested,
          SUM(CASE WHEN status = 'オミット' THEN 1 ELSE 0 END) as omitted
        FROM text_entries
        ${whereClause}
        GROUP BY file_category
        ORDER BY count DESC
      `;
    } else if (groupBy === 'language') {
      query = `
        SELECT 
          t.language_code,
          COUNT(*) as count,
          COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() as percentage,
          SUM(CASE WHEN t.status = '完了' THEN 1 ELSE 0 END) as completed,
          SUM(CASE WHEN t.status = '未処理' THEN 1 ELSE 0 END) as pending,
          SUM(CASE WHEN t.status = '確認依頼' THEN 1 ELSE 0 END) as review_requested,
          SUM(CASE WHEN t.status = 'オミット' THEN 1 ELSE 0 END) as omitted
        FROM translations t
        INNER JOIN text_entries te ON t.text_entry_id = te.id
        ${whereClause.replace('WHERE', 'WHERE')}
        GROUP BY t.language_code
        ORDER BY count DESC
      `;
    } else {
      return NextResponse.json(
        { error: 'Invalid groupBy parameter. Use: status, category, or language' },
        { status: 400 }
      );
    }

    const results = await executeQuery(query, params);

    // Get overall statistics
    const overallQuery = `
      SELECT 
        COUNT(*) as total_entries,
        SUM(CASE WHEN status = '完了' THEN 1 ELSE 0 END) as completed_entries,
        SUM(CASE WHEN status = '未処理' THEN 1 ELSE 0 END) as pending_entries,
        SUM(CASE WHEN status = '確認依頼' THEN 1 ELSE 0 END) as review_requested_entries,
        SUM(CASE WHEN status = 'オミット' THEN 1 ELSE 0 END) as omitted_entries,
        SUM(CASE WHEN status = '原文相談' THEN 1 ELSE 0 END) as consultation_entries
      FROM text_entries
      ${whereClause}
    `;

    const overallStats = await executeQuery(query, params);

    // Get recent activity
    const recentActivityQuery = `
      SELECT 
        eh.edit_type,
        eh.created_at,
        u.username as editor_name,
        te.label as text_label
      FROM edit_history eh
      INNER JOIN text_entries te ON eh.text_entry_id = te.id
      INNER JOIN users u ON eh.edited_by = u.id
      ${whereClause.replace('text_entries', 'te')}
      ORDER BY eh.created_at DESC
      LIMIT 10
    `;

    const recentActivity = await executeQuery(recentActivityQuery, params);

    return NextResponse.json({
      data: results,
      overall: overallStats[0] || {},
      recentActivity,
      groupBy,
    });
  } catch (error) {
    console.error('Error fetching progress data:', error);
    return NextResponse.json(
      { error: 'Failed to fetch progress data' },
      { status: 500 }
    );
  }
}