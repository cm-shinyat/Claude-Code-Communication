import { NextRequest, NextResponse } from 'next/server';
import { getAllUsers } from '../../../lib/auth';
import { hasPermission } from '../../../lib/rbac';

export async function GET(request: NextRequest) {
  try {
    const userRole = request.headers.get('x-user-role') as any;

    if (!hasPermission(userRole, 'manage_users')) {
      return NextResponse.json(
        { error: 'Insufficient permissions' },
        { status: 403 }
      );
    }

    const users = await getAllUsers();
    return NextResponse.json(users);
  } catch (error) {
    console.error('Get users error:', error);
    return NextResponse.json(
      { error: 'Failed to retrieve users' },
      { status: 500 }
    );
  }
}