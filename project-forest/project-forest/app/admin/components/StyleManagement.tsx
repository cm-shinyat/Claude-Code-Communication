'use client';

import { useState, useEffect } from 'react';

interface Style {
  id: number;
  name: string;
  font: string;
  max_chars: number;
  max_lines: number;
  font_size: number;
  auto_format_rules: string;
  created_at: string;
  updated_at: string;
}

const FONTS = [
  'Noto Sans JP',
  'Hiragino Sans',
  'Yu Gothic UI',
  'Meiryo UI',
  'MS Gothic',
  'MS Mincho',
  'Arial',
  'Times New Roman'
];

export default function StyleManagement() {
  const [styles, setStyles] = useState<Style[]>([]);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingStyle, setEditingStyle] = useState<Partial<Style> | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [previewText, setPreviewText] = useState('サンプルテキスト Sample Text 123');

  const [formData, setFormData] = useState({
    name: '',
    font: 'Noto Sans JP',
    max_chars: 24,
    max_lines: 2,
    font_size: 16,
    auto_format_rules: ''
  });

  // Mock data for demonstration
  useEffect(() => {
    const mockStyles: Style[] = [
      {
        id: 1,
        name: 'デフォルト',
        font: 'Noto Sans JP',
        max_chars: 24,
        max_lines: 2,
        font_size: 16,
        auto_format_rules: '24文字で自動改行、2行まで',
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-01T00:00:00Z'
      },
      {
        id: 2,
        name: 'ダイアログ',
        font: 'Hiragino Sans',
        max_chars: 40,
        max_lines: 4,
        font_size: 18,
        auto_format_rules: '40文字で自動改行、4行まで、感嘆符後に一時停止',
        created_at: '2024-01-02T00:00:00Z',
        updated_at: '2024-01-02T00:00:00Z'
      },
      {
        id: 3,
        name: 'ナレーション',
        font: 'Yu Gothic UI',
        max_chars: 50,
        max_lines: 3,
        font_size: 14,
        auto_format_rules: '50文字で自動改行、3行まで、句読点で一時停止',
        created_at: '2024-01-03T00:00:00Z',
        updated_at: '2024-01-03T00:00:00Z'
      },
      {
        id: 4,
        name: 'システムメッセージ',
        font: 'MS Gothic',
        max_chars: 30,
        max_lines: 1,
        font_size: 12,
        auto_format_rules: '30文字で切り詰め、1行のみ',
        created_at: '2024-01-04T00:00:00Z',
        updated_at: '2024-01-04T00:00:00Z'
      }
    ];
    setStyles(mockStyles);
  }, []);

  const filteredStyles = styles.filter(style =>
    style.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    style.font.toLowerCase().includes(searchTerm.toLowerCase()) ||
    style.auto_format_rules.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (editingStyle) {
      // Update existing style
      setStyles(styles.map(style => 
        style.id === editingStyle.id 
          ? { ...style, ...formData, updated_at: new Date().toISOString() }
          : style
      ));
    } else {
      // Add new style
      const newStyle: Style = {
        id: Math.max(...styles.map(s => s.id), 0) + 1,
        ...formData,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      };
      setStyles([...styles, newStyle]);
    }
    resetForm();
  };

  const handleEdit = (style: Style) => {
    setEditingStyle(style);
    setFormData({
      name: style.name,
      font: style.font,
      max_chars: style.max_chars,
      max_lines: style.max_lines,
      font_size: style.font_size,
      auto_format_rules: style.auto_format_rules
    });
    setIsModalOpen(true);
  };

  const handleDelete = (id: number) => {
    if (confirm('このスタイル設定を削除してもよろしいですか？使用中のテキストに影響する可能性があります。')) {
      setStyles(styles.filter(style => style.id !== id));
    }
  };

  const resetForm = () => {
    setFormData({
      name: '',
      font: 'Noto Sans JP',
      max_chars: 24,
      max_lines: 2,
      font_size: 16,
      auto_format_rules: ''
    });
    setEditingStyle(null);
    setIsModalOpen(false);
  };

  const duplicateStyle = (style: Style) => {
    const newStyle: Style = {
      ...style,
      id: Math.max(...styles.map(s => s.id), 0) + 1,
      name: `${style.name}のコピー`,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };
    setStyles([...styles, newStyle]);
  };

  const applyAutoFormat = (text: string, style: Style): string => {
    let formatted = text;
    const maxChars = style.max_chars;
    
    // Simple auto-format simulation
    if (formatted.length > maxChars) {
      const lines = [];
      let currentLine = '';
      const words = formatted.split('');
      
      for (const char of words) {
        if (currentLine.length >= maxChars) {
          lines.push(currentLine);
          currentLine = char;
        } else {
          currentLine += char;
        }
        
        if (lines.length >= style.max_lines) {
          break;
        }
      }
      
      if (currentLine && lines.length < style.max_lines) {
        lines.push(currentLine);
      }
      
      formatted = lines.join('\n');
    }
    
    return formatted;
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex justify-between items-center">
        <h2 className="text-xl font-semibold text-gray-900">スタイル設定管理</h2>
        <button
          onClick={() => setIsModalOpen(true)}
          className="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition-colors"
        >
          新規スタイル追加
        </button>
      </div>

      {/* Info */}
      <div className="bg-blue-50 border border-blue-200 rounded-md p-4">
        <div className="flex">
          <div className="flex-shrink-0">
            <div className="text-blue-400">ℹ️</div>
          </div>
          <div className="ml-3">
            <h3 className="text-sm font-medium text-blue-800">スタイル設定について</h3>
            <div className="mt-2 text-sm text-blue-700">
              <p>スタイル設定はテキストの表示方法を定義します。フォント、最大文字数、行数、自動フォーマットルールを設定できます。</p>
            </div>
          </div>
        </div>
      </div>

      {/* Search */}
      <div className="max-w-md">
        <input
          type="text"
          placeholder="スタイル名、フォント、ルールで検索..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
        />
      </div>

      {/* Styles List */}
      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
        {filteredStyles.map((style) => (
          <div key={style.id} className="bg-white shadow rounded-lg p-6">
            <div className="flex justify-between items-start mb-4">
              <h3 className="text-lg font-medium text-gray-900">{style.name}</h3>
              <div className="flex space-x-2">
                <button
                  onClick={() => duplicateStyle(style)}
                  className="text-gray-400 hover:text-gray-600"
                  title="複製"
                >
                  📋
                </button>
                <button
                  onClick={() => handleEdit(style)}
                  className="text-blue-600 hover:text-blue-900"
                  title="編集"
                >
                  ✏️
                </button>
                <button
                  onClick={() => handleDelete(style.id)}
                  className="text-red-600 hover:text-red-900"
                  title="削除"
                >
                  🗑️
                </button>
              </div>
            </div>
            
            <div className="space-y-3">
              <div className="grid grid-cols-2 gap-4 text-sm">
                <div>
                  <span className="text-gray-500">フォント:</span>
                  <div className="font-medium">{style.font}</div>
                </div>
                <div>
                  <span className="text-gray-500">サイズ:</span>
                  <div className="font-medium">{style.font_size}px</div>
                </div>
                <div>
                  <span className="text-gray-500">最大文字数:</span>
                  <div className="font-medium">{style.max_chars}文字</div>
                </div>
                <div>
                  <span className="text-gray-500">最大行数:</span>
                  <div className="font-medium">{style.max_lines}行</div>
                </div>
              </div>
              
              {style.auto_format_rules && (
                <div>
                  <span className="text-gray-500 text-sm">自動フォーマット:</span>
                  <div className="text-sm text-gray-700 mt-1">{style.auto_format_rules}</div>
                </div>
              )}
              
              {/* Preview */}
              <div className="mt-4 border-t pt-4">
                <span className="text-gray-500 text-sm">プレビュー:</span>
                <div 
                  className="mt-2 p-3 border rounded bg-gray-50"
                  style={{
                    fontFamily: style.font,
                    fontSize: `${style.font_size}px`,
                    lineHeight: '1.5'
                  }}
                >
                  {applyAutoFormat(previewText, style)}
                </div>
              </div>
            </div>
          </div>
        ))}
      </div>

      {filteredStyles.length === 0 && (
        <div className="text-center py-8 text-gray-500">
          {searchTerm ? '検索条件に一致するスタイルが見つかりませんでした。' : 'スタイルがまだ登録されていません。'}
        </div>
      )}

      {/* Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50">
          <div className="relative top-20 mx-auto p-5 border w-11/12 max-w-4xl shadow-lg rounded-md bg-white">
            <div className="mt-3">
              <h3 className="text-lg font-medium text-gray-900 mb-4">
                {editingStyle ? 'スタイル編集' : '新規スタイル作成'}
              </h3>
              
              <div className="grid grid-cols-2 gap-8">
                {/* Form */}
                <div>
                  <form onSubmit={handleSubmit} className="space-y-4">
                    <div>
                      <label className="block text-sm font-medium text-gray-700">スタイル名 *</label>
                      <input
                        type="text"
                        required
                        value={formData.name}
                        onChange={(e) => setFormData({...formData, name: e.target.value})}
                        className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                      />
                    </div>

                    <div>
                      <label className="block text-sm font-medium text-gray-700">フォント *</label>
                      <select
                        required
                        value={formData.font}
                        onChange={(e) => setFormData({...formData, font: e.target.value})}
                        className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                      >
                        {FONTS.map(font => (
                          <option key={font} value={font}>{font}</option>
                        ))}
                      </select>
                    </div>

                    <div className="grid grid-cols-3 gap-4">
                      <div>
                        <label className="block text-sm font-medium text-gray-700">最大文字数 *</label>
                        <input
                          type="number"
                          required
                          min="1"
                          max="200"
                          value={formData.max_chars}
                          onChange={(e) => setFormData({...formData, max_chars: parseInt(e.target.value)})}
                          className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                        />
                      </div>
                      <div>
                        <label className="block text-sm font-medium text-gray-700">最大行数 *</label>
                        <input
                          type="number"
                          required
                          min="1"
                          max="10"
                          value={formData.max_lines}
                          onChange={(e) => setFormData({...formData, max_lines: parseInt(e.target.value)})}
                          className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                        />
                      </div>
                      <div>
                        <label className="block text-sm font-medium text-gray-700">フォントサイズ *</label>
                        <input
                          type="number"
                          required
                          min="8"
                          max="48"
                          value={formData.font_size}
                          onChange={(e) => setFormData({...formData, font_size: parseInt(e.target.value)})}
                          className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                        />
                      </div>
                    </div>

                    <div>
                      <label className="block text-sm font-medium text-gray-700">自動フォーマットルール</label>
                      <textarea
                        rows={3}
                        value={formData.auto_format_rules}
                        onChange={(e) => setFormData({...formData, auto_format_rules: e.target.value})}
                        placeholder="例: 24文字で自動改行、句読点で一時停止"
                        className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                      />
                    </div>

                    <div className="flex justify-end space-x-3 pt-4">
                      <button
                        type="button"
                        onClick={resetForm}
                        className="px-4 py-2 border border-gray-300 rounded-md text-gray-700 hover:bg-gray-50"
                      >
                        キャンセル
                      </button>
                      <button
                        type="submit"
                        className="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700"
                      >
                        {editingStyle ? '更新' : '作成'}
                      </button>
                    </div>
                  </form>
                </div>

                {/* Preview */}
                <div>
                  <h4 className="text-sm font-medium text-gray-700 mb-4">リアルタイムプレビュー</h4>
                  
                  <div className="space-y-4">
                    <div>
                      <label className="block text-sm font-medium text-gray-700">プレビューテキスト</label>
                      <textarea
                        rows={3}
                        value={previewText}
                        onChange={(e) => setPreviewText(e.target.value)}
                        className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                      />
                    </div>
                    
                    <div className="border rounded-lg p-4 bg-gray-50">
                      <div className="text-xs text-gray-500 mb-2">表示結果:</div>
                      <div 
                        className="p-3 bg-white border rounded"
                        style={{
                          fontFamily: formData.font,
                          fontSize: `${formData.font_size}px`,
                          lineHeight: '1.5',
                          minHeight: `${formData.font_size * 1.5 * formData.max_lines}px`
                        }}
                      >
                        {applyAutoFormat(previewText, {
                          id: 0,
                          name: formData.name,
                          font: formData.font,
                          max_chars: formData.max_chars,
                          max_lines: formData.max_lines,
                          font_size: formData.font_size,
                          auto_format_rules: formData.auto_format_rules,
                          created_at: '',
                          updated_at: ''
                        })}
                      </div>
                      
                      <div className="mt-2 text-xs text-gray-500">
                        文字数: {previewText.length} / {formData.max_chars} | 
                        行数: {Math.ceil(previewText.length / formData.max_chars)} / {formData.max_lines}
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}