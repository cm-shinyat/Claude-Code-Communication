import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import mysql from 'mysql2/promise';

const JWT_SECRET = process.env.JWT_SECRET || 'your-super-secret-jwt-key';
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '7d';

export interface User {
  id: number;
  username: string;
  email: string;
  role: 'admin' | 'scenario_writer' | 'translator' | 'reviewer';
  created_at: string;
  updated_at: string;
}

export interface AuthToken {
  token: string;
  user: Omit<User, 'password_hash'>;
}

export interface DecodedToken {
  userId: number;
  username: string;
  email: string;
  role: string;
  iat: number;
  exp: number;
}

const dbConfig = {
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'project_forest',
  charset: 'utf8mb4'
};

export async function getDbConnection() {
  return await mysql.createConnection(dbConfig);
}

export async function hashPassword(password: string): Promise<string> {
  const saltRounds = 12;
  return await bcrypt.hash(password, saltRounds);
}

export async function verifyPassword(password: string, hashedPassword: string): Promise<boolean> {
  return await bcrypt.compare(password, hashedPassword);
}

export function generateToken(user: User): string {
  const payload = {
    userId: user.id,
    username: user.username,
    email: user.email,
    role: user.role
  };
  
  return jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
}

export function verifyToken(token: string): DecodedToken | null {
  try {
    return jwt.verify(token, JWT_SECRET) as DecodedToken;
  } catch (error) {
    return null;
  }
}

export async function createUser(
  username: string,
  email: string,
  password: string,
  role: User['role']
): Promise<User> {
  const connection = await getDbConnection();
  
  try {
    const hashedPassword = await hashPassword(password);
    
    const [result] = await connection.execute(
      'INSERT INTO users (username, email, password_hash, role) VALUES (?, ?, ?, ?)',
      [username, email, hashedPassword, role]
    );
    
    const insertId = (result as any).insertId;
    
    const [rows] = await connection.execute(
      'SELECT id, username, email, role, created_at, updated_at FROM users WHERE id = ?',
      [insertId]
    );
    
    return (rows as User[])[0];
  } finally {
    await connection.end();
  }
}

export async function getUserByEmail(email: string): Promise<(User & { password_hash: string }) | null> {
  const connection = await getDbConnection();
  
  try {
    const [rows] = await connection.execute(
      'SELECT * FROM users WHERE email = ?',
      [email]
    );
    
    const users = rows as (User & { password_hash: string })[];
    return users.length > 0 ? users[0] : null;
  } finally {
    await connection.end();
  }
}

export async function getUserById(id: number): Promise<User | null> {
  const connection = await getDbConnection();
  
  try {
    const [rows] = await connection.execute(
      'SELECT id, username, email, role, created_at, updated_at FROM users WHERE id = ?',
      [id]
    );
    
    const users = rows as User[];
    return users.length > 0 ? users[0] : null;
  } finally {
    await connection.end();
  }
}

export async function authenticateUser(email: string, password: string): Promise<AuthToken | null> {
  const user = await getUserByEmail(email);
  
  if (!user) {
    return null;
  }
  
  const isValidPassword = await verifyPassword(password, user.password_hash);
  
  if (!isValidPassword) {
    return null;
  }
  
  const { password_hash, ...userWithoutPassword } = user;
  const token = generateToken(userWithoutPassword);
  
  return {
    token,
    user: userWithoutPassword
  };
}

export async function getAllUsers(): Promise<User[]> {
  const connection = await getDbConnection();
  
  try {
    const [rows] = await connection.execute(
      'SELECT id, username, email, role, created_at, updated_at FROM users ORDER BY created_at DESC'
    );
    
    return rows as User[];
  } finally {
    await connection.end();
  }
}

export async function updateUser(
  id: number,
  updates: Partial<Pick<User, 'username' | 'email' | 'role'>>
): Promise<User | null> {
  const connection = await getDbConnection();
  
  try {
    const setClause = Object.keys(updates).map(key => `${key} = ?`).join(', ');
    const values = Object.values(updates);
    
    await connection.execute(
      `UPDATE users SET ${setClause} WHERE id = ?`,
      [...values, id]
    );
    
    return await getUserById(id);
  } finally {
    await connection.end();
  }
}

export async function deleteUser(id: number): Promise<boolean> {
  const connection = await getDbConnection();
  
  try {
    const [result] = await connection.execute(
      'DELETE FROM users WHERE id = ?',
      [id]
    );
    
    return (result as any).affectedRows > 0;
  } finally {
    await connection.end();
  }
}