import { NextRequest, NextResponse } from 'next/server';
import { getUserById, updateUser, deleteUser } from '../../../../lib/auth';
import { hasPermission, canModifyUserRole } from '../../../../lib/rbac';

export async function GET(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const userRole = request.headers.get('x-user-role') as any;
    const requestingUserId = parseInt(request.headers.get('x-user-id') || '0');
    const targetUserId = parseInt(params.id);

    const canViewUser = hasPermission(userRole, 'manage_users') || requestingUserId === targetUserId;

    if (!canViewUser) {
      return NextResponse.json(
        { error: 'Insufficient permissions' },
        { status: 403 }
      );
    }

    const user = await getUserById(targetUserId);

    if (!user) {
      return NextResponse.json(
        { error: 'User not found' },
        { status: 404 }
      );
    }

    return NextResponse.json(user);
  } catch (error) {
    console.error('Get user error:', error);
    return NextResponse.json(
      { error: 'Failed to retrieve user' },
      { status: 500 }
    );
  }
}

export async function PUT(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const userRole = request.headers.get('x-user-role') as any;
    const requestingUserId = parseInt(request.headers.get('x-user-id') || '0');
    const targetUserId = parseInt(params.id);

    const canEditUser = hasPermission(userRole, 'manage_users') || requestingUserId === targetUserId;

    if (!canEditUser) {
      return NextResponse.json(
        { error: 'Insufficient permissions' },
        { status: 403 }
      );
    }

    const { username, email, role } = await request.json();
    const updates: any = {};

    if (username) updates.username = username;
    if (email) updates.email = email;

    if (role && requestingUserId !== targetUserId) {
      if (!hasPermission(userRole, 'manage_users')) {
        return NextResponse.json(
          { error: 'Cannot modify user roles' },
          { status: 403 }
        );
      }

      const targetUser = await getUserById(targetUserId);
      if (targetUser && !canModifyUserRole(userRole, targetUser.role)) {
        return NextResponse.json(
          { error: 'Cannot modify user with equal or higher privileges' },
          { status: 403 }
        );
      }

      updates.role = role;
    }

    if (Object.keys(updates).length === 0) {
      return NextResponse.json(
        { error: 'No valid updates provided' },
        { status: 400 }
      );
    }

    const updatedUser = await updateUser(targetUserId, updates);

    if (!updatedUser) {
      return NextResponse.json(
        { error: 'User not found or update failed' },
        { status: 404 }
      );
    }

    return NextResponse.json(updatedUser);
  } catch (error: any) {
    console.error('Update user error:', error);
    
    if (error.code === 'ER_DUP_ENTRY') {
      return NextResponse.json(
        { error: 'Username or email already exists' },
        { status: 409 }
      );
    }

    return NextResponse.json(
      { error: 'Failed to update user' },
      { status: 500 }
    );
  }
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const userRole = request.headers.get('x-user-role') as any;
    const targetUserId = parseInt(params.id);

    if (!hasPermission(userRole, 'manage_users')) {
      return NextResponse.json(
        { error: 'Insufficient permissions' },
        { status: 403 }
      );
    }

    const targetUser = await getUserById(targetUserId);
    if (targetUser && !canModifyUserRole(userRole, targetUser.role)) {
      return NextResponse.json(
        { error: 'Cannot delete user with equal or higher privileges' },
        { status: 403 }
      );
    }

    const deleted = await deleteUser(targetUserId);

    if (!deleted) {
      return NextResponse.json(
        { error: 'User not found or delete failed' },
        { status: 404 }
      );
    }

    return NextResponse.json({ message: 'User deleted successfully' });
  } catch (error) {
    console.error('Delete user error:', error);
    return NextResponse.json(
      { error: 'Failed to delete user' },
      { status: 500 }
    );
  }
}