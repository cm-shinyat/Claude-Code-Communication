'use client';

import { useState, useEffect } from 'react';

interface ForbiddenWord {
  id: number;
  word: string;
  replacement: string;
  reason: string;
  category: string;
  created_at: string;
  updated_at: string;
}

const CATEGORIES = [
  '不適切表現',
  '暴力的表現',
  '差別的表現',
  '宗教的表現',
  '政治的表現',
  'その他'
];

export default function ForbiddenWordManagement() {
  const [forbiddenWords, setForbiddenWords] = useState<ForbiddenWord[]>([]);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingWord, setEditingWord] = useState<Partial<ForbiddenWord> | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('');
  const [detectedWords, setDetectedWords] = useState<{word: string, count: number, locations: string[]}[]>([]);
  const [isImportModalOpen, setIsImportModalOpen] = useState(false);

  const [formData, setFormData] = useState({
    word: '',
    replacement: '',
    reason: '',
    category: ''
  });

  // Mock data for demonstration
  useEffect(() => {
    const mockForbiddenWords: ForbiddenWord[] = [
      {
        id: 1,
        word: '殺す',
        replacement: '倒す',
        reason: '暴力的表現のため',
        category: '暴力的表現',
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-01T00:00:00Z'
      },
      {
        id: 2,
        word: '死ね',
        replacement: '消えろ',
        reason: '暴力的表現のため',
        category: '暴力的表現',
        created_at: '2024-01-02T00:00:00Z',
        updated_at: '2024-01-02T00:00:00Z'
      },
      {
        id: 3,
        word: 'バカ',
        replacement: 'おろか者',
        reason: '不適切な表現のため',
        category: '不適切表現',
        created_at: '2024-01-03T00:00:00Z',
        updated_at: '2024-01-03T00:00:00Z'
      },
      {
        id: 4,
        word: 'クソ',
        replacement: 'くだらない',
        reason: '不適切な表現のため',
        category: '不適切表現',
        created_at: '2024-01-04T00:00:00Z',
        updated_at: '2024-01-04T00:00:00Z'
      }
    ];
    setForbiddenWords(mockForbiddenWords);

    // Mock detected words
    setDetectedWords([
      { word: '殺す', count: 3, locations: ['ch01_01.txt', 'ch02_05.txt', 'battle_01.txt'] },
      { word: 'バカ', count: 1, locations: ['ch03_02.txt'] }
    ]);
  }, []);

  const filteredWords = forbiddenWords.filter(word => {
    const matchesSearch = word.word.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         word.replacement.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         word.reason.toLowerCase().includes(searchTerm.toLowerCase());
    const matchesCategory = !selectedCategory || word.category === selectedCategory;
    return matchesSearch && matchesCategory;
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (editingWord) {
      // Update existing word
      setForbiddenWords(forbiddenWords.map(word => 
        word.id === editingWord.id 
          ? { ...word, ...formData, updated_at: new Date().toISOString() }
          : word
      ));
    } else {
      // Add new word
      const newWord: ForbiddenWord = {
        id: Math.max(...forbiddenWords.map(w => w.id), 0) + 1,
        ...formData,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      };
      setForbiddenWords([...forbiddenWords, newWord]);
    }
    resetForm();
  };

  const handleEdit = (word: ForbiddenWord) => {
    setEditingWord(word);
    setFormData({
      word: word.word,
      replacement: word.replacement,
      reason: word.reason,
      category: word.category
    });
    setIsModalOpen(true);
  };

  const handleDelete = (id: number) => {
    if (confirm('この禁止用語を削除してもよろしいですか？')) {
      setForbiddenWords(forbiddenWords.filter(word => word.id !== id));
    }
  };

  const resetForm = () => {
    setFormData({
      word: '',
      replacement: '',
      reason: '',
      category: ''
    });
    setEditingWord(null);
    setIsModalOpen(false);
  };

  const scanAllTexts = () => {
    // In a real implementation, this would scan all text entries
    alert('全テキストをスキャンして禁止用語を検出します（実装予定）');
  };

  const importKDEList = () => {
    // In a real implementation, this would import KDE list
    setIsImportModalOpen(true);
  };

  const replaceAllOccurrences = (word: string, replacement: string) => {
    if (confirm(`「${word}」を「${replacement}」に一括置換してもよろしいですか？この操作は元に戻せません。`)) {
      // In a real implementation, this would replace all occurrences in text entries
      alert(`「${word}」の一括置換を実行します（実装予定）`);
    }
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex justify-between items-center">
        <h2 className="text-xl font-semibold text-gray-900">禁止用語管理</h2>
        <div className="flex space-x-3">
          <button
            onClick={scanAllTexts}
            className="bg-yellow-600 text-white px-4 py-2 rounded-md hover:bg-yellow-700 transition-colors"
          >
            全テキストスキャン
          </button>
          <button
            onClick={importKDEList}
            className="bg-green-600 text-white px-4 py-2 rounded-md hover:bg-green-700 transition-colors"
          >
            KDEリスト読込
          </button>
          <button
            onClick={() => setIsModalOpen(true)}
            className="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition-colors"
          >
            新規追加
          </button>
        </div>
      </div>

      {/* Detection Alert */}
      {detectedWords.length > 0 && (
        <div className="bg-red-50 border border-red-200 rounded-md p-4">
          <div className="flex">
            <div className="flex-shrink-0">
              <div className="text-red-400">🚨</div>
            </div>
            <div className="ml-3">
              <h3 className="text-sm font-medium text-red-800">禁止用語が検出されました</h3>
              <div className="mt-2 space-y-2">
                {detectedWords.map((detected, index) => (
                  <div key={index} className="flex items-center justify-between bg-white p-2 rounded border">
                    <div>
                      <span className="font-medium text-red-800">「{detected.word}」</span>
                      <span className="text-sm text-red-600 ml-2">
                        {detected.count}箇所で検出: {detected.locations.join(', ')}
                      </span>
                    </div>
                    <div className="flex space-x-2">
                      <button
                        onClick={() => {
                          const forbidden = forbiddenWords.find(fw => fw.word === detected.word);
                          if (forbidden) {
                            replaceAllOccurrences(forbidden.word, forbidden.replacement);
                          }
                        }}
                        className="text-xs bg-red-100 text-red-800 px-2 py-1 rounded hover:bg-red-200"
                      >
                        一括置換
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Filters */}
      <div className="flex space-x-4">
        <div className="flex-1 max-w-md">
          <input
            type="text"
            placeholder="禁止用語、置換語、理由で検索..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>
        <div className="w-48">
          <select
            value={selectedCategory}
            onChange={(e) => setSelectedCategory(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          >
            <option value="">全カテゴリ</option>
            {CATEGORIES.map(category => (
              <option key={category} value={category}>{category}</option>
            ))}
          </select>
        </div>
      </div>

      {/* Statistics */}
      <div className="grid grid-cols-4 gap-4">
        <div className="bg-white p-4 rounded-lg shadow">
          <div className="text-2xl font-bold text-red-600">{forbiddenWords.length}</div>
          <div className="text-sm text-gray-600">禁止用語数</div>
        </div>
        <div className="bg-white p-4 rounded-lg shadow">
          <div className="text-2xl font-bold text-yellow-600">
            {detectedWords.reduce((sum, d) => sum + d.count, 0)}
          </div>
          <div className="text-sm text-gray-600">検出箇所数</div>
        </div>
        <div className="bg-white p-4 rounded-lg shadow">
          <div className="text-2xl font-bold text-blue-600">{CATEGORIES.length}</div>
          <div className="text-sm text-gray-600">カテゴリ数</div>
        </div>
        <div className="bg-white p-4 rounded-lg shadow">
          <div className="text-2xl font-bold text-green-600">
            {forbiddenWords.filter(w => w.replacement).length}
          </div>
          <div className="text-sm text-gray-600">置換語設定済み</div>
        </div>
      </div>

      {/* Forbidden Words List */}
      <div className="bg-white shadow rounded-lg overflow-hidden">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                禁止用語
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                置換語
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                カテゴリ
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                理由
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                更新日
              </th>
              <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                操作
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {filteredWords.map((word) => (
              <tr key={word.id} className="hover:bg-gray-50">
                <td className="px-6 py-4 whitespace-nowrap">
                  <div className="text-sm font-medium text-red-600">
                    {word.word}
                  </div>
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  <div className="text-sm text-green-600 font-medium">
                    {word.replacement || '-'}
                  </div>
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium
                    ${word.category === '暴力的表現' ? 'bg-red-100 text-red-800' :
                      word.category === '不適切表現' ? 'bg-yellow-100 text-yellow-800' :
                      word.category === '差別的表現' ? 'bg-purple-100 text-purple-800' :
                      'bg-gray-100 text-gray-800'}`}>
                    {word.category}
                  </span>
                </td>
                <td className="px-6 py-4">
                  <div className="text-sm text-gray-900 max-w-xs truncate">
                    {word.reason}
                  </div>
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {new Date(word.updated_at).toLocaleDateString('ja-JP')}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium space-x-2">
                  <button
                    onClick={() => handleEdit(word)}
                    className="text-blue-600 hover:text-blue-900"
                  >
                    編集
                  </button>
                  <button
                    onClick={() => handleDelete(word.id)}
                    className="text-red-600 hover:text-red-900"
                  >
                    削除
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        
        {filteredWords.length === 0 && (
          <div className="text-center py-8 text-gray-500">
            {searchTerm || selectedCategory ? '検索条件に一致する禁止用語が見つかりませんでした。' : '禁止用語がまだ登録されていません。'}
          </div>
        )}
      </div>

      {/* Add/Edit Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50">
          <div className="relative top-20 mx-auto p-5 border w-11/12 max-w-2xl shadow-lg rounded-md bg-white">
            <div className="mt-3">
              <h3 className="text-lg font-medium text-gray-900 mb-4">
                {editingWord ? '禁止用語編集' : '新規禁止用語登録'}
              </h3>
              <form onSubmit={handleSubmit} className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700">禁止用語 *</label>
                  <input
                    type="text"
                    required
                    value={formData.word}
                    onChange={(e) => setFormData({...formData, word: e.target.value})}
                    className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700">置換語</label>
                  <input
                    type="text"
                    value={formData.replacement}
                    onChange={(e) => setFormData({...formData, replacement: e.target.value})}
                    placeholder="推奨される代替表現"
                    className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700">カテゴリ *</label>
                  <select
                    required
                    value={formData.category}
                    onChange={(e) => setFormData({...formData, category: e.target.value})}
                    className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                  >
                    <option value="">選択してください</option>
                    {CATEGORIES.map(category => (
                      <option key={category} value={category}>{category}</option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700">理由 *</label>
                  <textarea
                    rows={3}
                    required
                    value={formData.reason}
                    onChange={(e) => setFormData({...formData, reason: e.target.value})}
                    placeholder="なぜこの語句が禁止されているのか説明してください"
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
                    {editingWord ? '更新' : '登録'}
                  </button>
                </div>
              </form>
            </div>
          </div>
        </div>
      )}

      {/* Import Modal */}
      {isImportModalOpen && (
        <div className="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50">
          <div className="relative top-20 mx-auto p-5 border w-11/12 max-w-2xl shadow-lg rounded-md bg-white">
            <div className="mt-3">
              <h3 className="text-lg font-medium text-gray-900 mb-4">KDEリストインポート</h3>
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700">ファイル選択</label>
                  <input
                    type="file"
                    accept=".csv,.txt"
                    className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                  <p className="text-xs text-gray-500 mt-1">CSV形式またはテキスト形式のファイルをアップロードしてください</p>
                </div>
                
                <div className="bg-yellow-50 border border-yellow-200 rounded-md p-4">
                  <div className="flex">
                    <div className="flex-shrink-0">
                      <div className="text-yellow-400">⚠️</div>
                    </div>
                    <div className="ml-3">
                      <h3 className="text-sm font-medium text-yellow-800">注意事項</h3>
                      <div className="mt-2 text-sm text-yellow-700">
                        <ul className="list-disc list-inside space-y-1">
                          <li>既存の禁止用語と重複する場合は上書きされます</li>
                          <li>大量のデータの場合、処理に時間がかかる場合があります</li>
                          <li>インポート前にバックアップを取ることをお勧めします</li>
                        </ul>
                      </div>
                    </div>
                  </div>
                </div>

                <div className="flex justify-end space-x-3 pt-4">
                  <button
                    type="button"
                    onClick={() => setIsImportModalOpen(false)}
                    className="px-4 py-2 border border-gray-300 rounded-md text-gray-700 hover:bg-gray-50"
                  >
                    キャンセル
                  </button>
                  <button
                    onClick={() => {
                      alert('KDEリストをインポートします（実装予定）');
                      setIsImportModalOpen(false);
                    }}
                    className="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700"
                  >
                    インポート実行
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}