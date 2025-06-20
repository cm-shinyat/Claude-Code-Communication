-- Project Forest Database Schema

-- Users table for authentication and role management
CREATE TABLE users (
  id INT PRIMARY KEY AUTO_INCREMENT,
  username VARCHAR(100) UNIQUE NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role ENUM('admin', 'scenario_writer', 'translator', 'reviewer') NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Text entries table for multilingual text management
CREATE TABLE text_entries (
  id INT PRIMARY KEY AUTO_INCREMENT,
  label VARCHAR(255) NOT NULL,
  file_category VARCHAR(100),
  original_text TEXT,
  language_code VARCHAR(10) DEFAULT 'ja',
  status ENUM('未処理','確認依頼','完了','オミット','原文相談') DEFAULT '未処理',
  max_chars INT,
  max_lines INT,
  created_by INT,
  updated_by INT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (created_by) REFERENCES users(id),
  FOREIGN KEY (updated_by) REFERENCES users(id),
  INDEX idx_label (label),
  INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Translations table
CREATE TABLE translations (
  id INT PRIMARY KEY AUTO_INCREMENT,
  text_entry_id INT NOT NULL,
  language_code VARCHAR(10) NOT NULL,
  translated_text TEXT,
  status ENUM('未処理','確認依頼','完了','オミット') DEFAULT '未処理',
  translator_id INT,
  reviewer_id INT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (text_entry_id) REFERENCES text_entries(id) ON DELETE CASCADE,
  FOREIGN KEY (translator_id) REFERENCES users(id),
  FOREIGN KEY (reviewer_id) REFERENCES users(id),
  UNIQUE KEY unique_translation (text_entry_id, language_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Edit history table
CREATE TABLE edit_history (
  id INT PRIMARY KEY AUTO_INCREMENT,
  text_entry_id INT NOT NULL,
  language_code VARCHAR(10) NOT NULL,
  old_text TEXT,
  new_text TEXT,
  edited_by INT NOT NULL,
  edit_type ENUM('create','update','delete') NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (text_entry_id) REFERENCES text_entries(id) ON DELETE CASCADE,
  FOREIGN KEY (edited_by) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Characters table
CREATE TABLE characters (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(100) NOT NULL,
  pronoun_first VARCHAR(50),
  pronoun_second VARCHAR(50),
  face_graphic VARCHAR(255),
  description TEXT,
  traits TEXT,
  favorites TEXT,
  dislikes TEXT,
  special_reactions TEXT,
  created_by INT,
  updated_by INT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (created_by) REFERENCES users(id),
  FOREIGN KEY (updated_by) REFERENCES users(id),
  INDEX idx_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Styles table
CREATE TABLE styles (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(100) NOT NULL UNIQUE,
  font VARCHAR(100),
  max_chars INT,
  max_lines INT,
  font_size INT,
  auto_format_rules TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Tags table
CREATE TABLE tags (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(100) NOT NULL UNIQUE,
  display_text VARCHAR(100),
  icon VARCHAR(255),
  description TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Text-Tag relationship table
CREATE TABLE text_tags (
  text_entry_id INT NOT NULL,
  tag_id INT NOT NULL,
  PRIMARY KEY (text_entry_id, tag_id),
  FOREIGN KEY (text_entry_id) REFERENCES text_entries(id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Forbidden words table
CREATE TABLE forbidden_words (
  id INT PRIMARY KEY AUTO_INCREMENT,
  word VARCHAR(100) NOT NULL UNIQUE,
  replacement VARCHAR(100),
  reason TEXT,
  category VARCHAR(50),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_word (word)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Proper nouns table
CREATE TABLE proper_nouns (
  id INT PRIMARY KEY AUTO_INCREMENT,
  term VARCHAR(255) NOT NULL,
  reading VARCHAR(255),
  translation VARCHAR(255),
  category VARCHAR(100),
  description TEXT,
  style_guide_ref VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_term (term),
  INDEX idx_category (category)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- File import/export history
CREATE TABLE file_history (
  id INT PRIMARY KEY AUTO_INCREMENT,
  filename VARCHAR(255) NOT NULL,
  file_type ENUM('import','export') NOT NULL,
  file_format ENUM('csv','json','xml') NOT NULL,
  file_path VARCHAR(500),
  record_count INT,
  status ENUM('success','failed','processing') NOT NULL,
  error_message TEXT,
  user_id INT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Session management for concurrent editing
CREATE TABLE edit_sessions (
  id INT PRIMARY KEY AUTO_INCREMENT,
  user_id INT NOT NULL,
  text_entry_id INT NOT NULL,
  language_code VARCHAR(10),
  started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  is_active BOOLEAN DEFAULT TRUE,
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (text_entry_id) REFERENCES text_entries(id) ON DELETE CASCADE,
  INDEX idx_active_sessions (text_entry_id, is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;