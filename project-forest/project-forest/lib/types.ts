export interface User {
  id: number;
  username: string;
  email: string;
  role: 'admin' | 'scenario_writer' | 'translator' | 'reviewer';
  created_at: string;
  updated_at: string;
}

export interface TextEntry {
  id: number;
  label: string;
  file_category?: string;
  original_text?: string;
  language_code: string;
  status: '未処理' | '確認依頼' | '完了' | 'オミット' | '原文相談';
  max_chars?: number;
  max_lines?: number;
  created_by?: number;
  updated_by?: number;
  created_at: string;
  updated_at: string;
}

export interface Translation {
  id: number;
  text_entry_id: number;
  language_code: string;
  translated_text?: string;
  status: '未処理' | '確認依頼' | '完了' | 'オミット';
  translator_id?: number;
  reviewer_id?: number;
  created_at: string;
  updated_at: string;
}

export interface EditHistory {
  id: number;
  text_entry_id: number;
  language_code: string;
  old_text?: string;
  new_text?: string;
  edited_by: number;
  edit_type: 'create' | 'update' | 'delete';
  created_at: string;
  editor_name?: string;
}

export interface Character {
  id: number;
  name: string;
  pronoun_first?: string;
  pronoun_second?: string;
  face_graphic?: string;
  description?: string;
  traits?: string;
  favorites?: string;
  dislikes?: string;
  special_reactions?: string;
  created_by?: number;
  updated_by?: number;
  created_at: string;
  updated_at: string;
}

export interface Tag {
  id: number;
  name: string;
  display_text?: string;
  icon?: string;
  description?: string;
  created_at: string;
  updated_at: string;
}

export interface ForbiddenWord {
  id: number;
  word: string;
  replacement?: string;
  reason?: string;
  category?: string;
  created_at: string;
  updated_at: string;
}

export interface FileHistory {
  id: number;
  filename: string;
  file_type: 'import' | 'export';
  file_format: 'csv' | 'json' | 'xml';
  file_path?: string;
  record_count?: number;
  status: 'success' | 'failed' | 'processing';
  error_message?: string;
  user_id: number;
  created_at: string;
}

export interface EditSession {
  id: number;
  user_id: number;
  text_entry_id: number;
  language_code?: string;
  started_at: string;
  last_activity: string;
  is_active: boolean;
  username?: string;
}

export interface TextEntryWithTranslations extends TextEntry {
  translations?: Translation[];
  tags?: Tag[];
  edit_sessions?: EditSession[];
}