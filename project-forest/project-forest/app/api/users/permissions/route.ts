import { NextRequest, NextResponse } from 'next/server';
import { getUserPermissions } from '../../../../lib/rbac';

export async function GET(request: NextRequest) {
  try {
    const userRole = request.headers.get('x-user-role') as any;

    if (!userRole) {
      return NextResponse.json(
        { error: 'User role not found' },
        { status: 400 }
      );
    }

    const permissions = getUserPermissions(userRole);

    return NextResponse.json({
      role: userRole,
      permissions
    });
  } catch (error) {
    console.error('Get permissions error:', error);
    return NextResponse.json(
      { error: 'Failed to retrieve permissions' },
      { status: 500 }
    );
  }
}