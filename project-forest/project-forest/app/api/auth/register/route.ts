import { NextRequest, NextResponse } from 'next/server';
import { createUser, generateToken } from '../../../../lib/auth';

export async function POST(request: NextRequest) {
  try {
    const { username, email, password, role } = await request.json();

    if (!username || !email || !password || !role) {
      return NextResponse.json(
        { error: 'Username, email, password, and role are required' },
        { status: 400 }
      );
    }

    const validRoles = ['admin', 'scenario_writer', 'translator', 'reviewer'];
    if (!validRoles.includes(role)) {
      return NextResponse.json(
        { error: 'Invalid role specified' },
        { status: 400 }
      );
    }

    if (password.length < 8) {
      return NextResponse.json(
        { error: 'Password must be at least 8 characters long' },
        { status: 400 }
      );
    }

    const user = await createUser(username, email, password, role);
    const token = generateToken(user);

    return NextResponse.json({
      token,
      user
    }, { status: 201 });
  } catch (error: any) {
    console.error('Registration error:', error);
    
    if (error.code === 'ER_DUP_ENTRY') {
      return NextResponse.json(
        { error: 'Username or email already exists' },
        { status: 409 }
      );
    }

    return NextResponse.json(
      { error: 'Failed to create user' },
      { status: 500 }
    );
  }
}