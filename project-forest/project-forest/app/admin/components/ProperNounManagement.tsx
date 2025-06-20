'use client';

import { useState, useEffect } from 'react';

interface ProperNoun {
  id: number;
  term: string;
  reading: string;
  translation: string;
  category: string;
  description: string;
  style_guide_ref: string;
  created_at: string;
  updated_at: string;
}

const CATEGORIES = [
  '人名',
  '地名',
  '組織・団体',
  'アイテム・道具',
  '魔法・スキル',
  '種族・モンスター',
  'その他'
];

export default function ProperNounManagement() {
  const [properNouns, setProperNouns] = useState<ProperNoun[]>([]);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingNoun, setEditingNoun] = useState<Partial<ProperNoun> | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('');
  const [unregisteredTerms, setUnregisteredTerms] = useState<string[]>([]);

  const [formData, setFormData] = useState({
    term: '',
    reading: '',
    translation: '',
    category: '',
    description: '',
    style_guide_ref: ''
  });

  // Mock data for demonstration
  useEffect(() => {
    const mockProperNouns: ProperNoun[] = [
      {
        id: 1,
        term: 'エルデンリング',
        reading: 'えるでんりんぐ',
        translation: 'Elden Ring',
        category: 'アイテム・道具',
        description: '世界を支配する力を持つ伝説の指輪',
        style_guide_ref: 'スタイルガイド 3.2.1',
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-01T00:00:00Z'
      },
      {
        id: 2,
        term: 'ランドビトウィーン',
        reading: 'らんどびとうぃーん',
        translation: 'The Lands Between',
        category: '地名',
        description: 'ゲームの舞台となる狭間の地',
        style_guide_ref: 'スタイルガイド 2.1.5',
        created_at: '2024-01-02T00:00:00Z',
        updated_at: '2024-01-02T00:00:00Z'
      },
      {
        id: 3,
        term: 'マリカ',
        reading: 'まりか',
        translation: 'Marika',
        category: '人名',
        description: '永遠の女王マリカ',
        style_guide_ref: 'スタイルガイド 1.3.2',
        created_at: '2024-01-03T00:00:00Z',
        updated_at: '2024-01-03T00:00:00Z'
      },
      {
        id: 4,
        term: 'デミゴッド',
        reading: 'でみごっど',
        translation: 'Demigod',
        category: '種族・モンスター',
        description: '神と人の間に生まれた半神',
        style_guide_ref: 'スタイルガイド 4.1.1',
        created_at: '2024-01-04T00:00:00Z',
        updated_at: '2024-01-04T00:00:00Z'
      }
    ];
    setProperNouns(mockProperNouns);

    // Mock unregistered terms
    setUnregisteredTerms(['グレイス', 'タイムルーン', 'フラスク']);
  }, []);

  const filteredNouns = properNouns.filter(noun => {
    const matchesSearch = noun.term.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         noun.reading.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         noun.translation.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         noun.description.toLowerCase().includes(searchTerm.toLowerCase());
    const matchesCategory = !selectedCategory || noun.category === selectedCategory;
    return matchesSearch && matchesCategory;
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (editingNoun) {
      // Update existing noun
      setProperNouns(properNouns.map(noun => 
        noun.id === editingNoun.id 
          ? { ...noun, ...formData, updated_at: new Date().toISOString() }
          : noun
      ));
    } else {
      // Add new noun
      const newNoun: ProperNoun = {
        id: Math.max(...properNouns.map(n => n.id), 0) + 1,
        ...formData,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      };
      setProperNouns([...properNouns, newNoun]);
    }
    resetForm();
  };

  const handleEdit = (noun: ProperNoun) => {
    setEditingNoun(noun);
    setFormData({
      term: noun.term,
      reading: noun.reading,
      translation: noun.translation,
      category: noun.category,
      description: noun.description,
      style_guide_ref: noun.style_guide_ref
    });
    setIsModalOpen(true);
  };

  const handleDelete = (id: number) => {
    if (confirm('この固有名詞を削除してもよろしいですか？')) {
      setProperNouns(properNouns.filter(noun => noun.id !== id));
    }
  };

  const resetForm = () => {
    setFormData({
      term: '',
      reading: '',
      translation: '',
      category: '',
      description: '',
      style_guide_ref: ''
    });
    setEditingNoun(null);
    setIsModalOpen(false);
  };

  const handleQuickAdd = (term: string) => {
    setFormData({
      term: term,
      reading: '',
      translation: '',
      category: '',
      description: '',
      style_guide_ref: ''
    });
    setIsModalOpen(true);
  };

  const detectUnregisteredTerms = () => {
    // In a real implementation, this would scan text entries for unregistered terms
    alert('テキストをスキャンして未登録の固有名詞を検出します（実装予定）');
  };

  const importStyleGuide = () => {
    // In a real implementation, this would import from external style guide
    alert('スタイルガイドからインポートします（実装予定）');
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex justify-between items-center">
        <h2 className="text-xl font-semibold text-gray-900">固有名詞管理</h2>
        <div className="flex space-x-3">
          <button
            onClick={detectUnregisteredTerms}
            className="bg-yellow-600 text-white px-4 py-2 rounded-md hover:bg-yellow-700 transition-colors"
          >
            未登録語句検出
          </button>
          <button
            onClick={importStyleGuide}
            className="bg-green-600 text-white px-4 py-2 rounded-md hover:bg-green-700 transition-colors"
          >
            スタイルガイド読込
          </button>
          <button
            onClick={() => setIsModalOpen(true)}
            className="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition-colors"
          >
            新規追加
          </button>
        </div>
      </div>

      {/* Unregistered Terms Alert */}
      {unregisteredTerms.length > 0 && (
        <div className="bg-yellow-50 border border-yellow-200 rounded-md p-4">
          <div className="flex">
            <div className="flex-shrink-0">
              <div className="text-yellow-400">⚠️</div>
            </div>
            <div className="ml-3">
              <h3 className="text-sm font-medium text-yellow-800">未登録の固有名詞が検出されました</h3>
              <div className="mt-2">
                <div className="flex flex-wrap gap-2">
                  {unregisteredTerms.map((term, index) => (
                    <button
                      key={index}
                      onClick={() => handleQuickAdd(term)}
                      className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800 hover:bg-yellow-200 cursor-pointer"
                    >
                      {term} +
                    </button>
                  ))}
                </div>
                <p className="text-xs text-yellow-700 mt-2">クリックして登録画面を開きます</p>
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
            placeholder="固有名詞、読み方、説明で検索..."
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
          <div className="text-2xl font-bold text-blue-600">{properNouns.length}</div>
          <div className="text-sm text-gray-600">登録済み</div>
        </div>
        <div className="bg-white p-4 rounded-lg shadow">
          <div className="text-2xl font-bold text-yellow-600">{unregisteredTerms.length}</div>
          <div className="text-sm text-gray-600">未登録検出</div>
        </div>
        <div className="bg-white p-4 rounded-lg shadow">
          <div className="text-2xl font-bold text-green-600">{CATEGORIES.length}</div>
          <div className="text-sm text-gray-600">カテゴリ数</div>
        </div>
        <div className="bg-white p-4 rounded-lg shadow">
          <div className="text-2xl font-bold text-purple-600">
            {new Set(properNouns.map(n => n.category)).size}
          </div>
          <div className="text-sm text-gray-600">使用中カテゴリ</div>
        </div>
      </div>

      {/* Proper Nouns List */}
      <div className="bg-white shadow rounded-lg overflow-hidden">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                固有名詞
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                読み方
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                英語表記
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                カテゴリ
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                説明
              </th>
              <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                操作
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {filteredNouns.map((noun) => (
              <tr key={noun.id} className="hover:bg-gray-50">
                <td className="px-6 py-4 whitespace-nowrap">
                  <div className="text-sm font-medium text-gray-900">
                    {noun.term}
                  </div>
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {noun.reading}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {noun.translation}
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                    {noun.category}
                  </span>
                </td>
                <td className="px-6 py-4">
                  <div className="text-sm text-gray-900 max-w-xs truncate">
                    {noun.description}
                  </div>
                  {noun.style_guide_ref && (
                    <div className="text-xs text-gray-500 mt-1">
                      参照: {noun.style_guide_ref}
                    </div>
                  )}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium space-x-2">
                  <button
                    onClick={() => handleEdit(noun)}
                    className="text-blue-600 hover:text-blue-900"
                  >
                    編集
                  </button>
                  <button
                    onClick={() => handleDelete(noun.id)}
                    className="text-red-600 hover:text-red-900"
                  >
                    削除
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        
        {filteredNouns.length === 0 && (
          <div className="text-center py-8 text-gray-500">
            {searchTerm || selectedCategory ? '検索条件に一致する固有名詞が見つかりませんでした。' : '固有名詞がまだ登録されていません。'}
          </div>
        )}
      </div>

      {/* Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50">
          <div className="relative top-20 mx-auto p-5 border w-11/12 max-w-3xl shadow-lg rounded-md bg-white">
            <div className="mt-3">
              <h3 className="text-lg font-medium text-gray-900 mb-4">
                {editingNoun ? '固有名詞編集' : '新規固有名詞登録'}
              </h3>
              <form onSubmit={handleSubmit} className="space-y-4">
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-gray-700">固有名詞 *</label>
                    <input
                      type="text"
                      required
                      value={formData.term}
                      onChange={(e) => setFormData({...formData, term: e.target.value})}
                      className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-700">読み方</label>
                    <input
                      type="text"
                      value={formData.reading}
                      onChange={(e) => setFormData({...formData, reading: e.target.value})}
                      placeholder="ひらがなで入力"
                      className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                    />
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-gray-700">英語表記</label>
                    <input
                      type="text"
                      value={formData.translation}
                      onChange={(e) => setFormData({...formData, translation: e.target.value})}
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
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700">説明</label>
                  <textarea
                    rows={3}
                    value={formData.description}
                    onChange={(e) => setFormData({...formData, description: e.target.value})}
                    placeholder="この固有名詞の説明や使用方法"
                    className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700">スタイルガイド参照</label>
                  <input
                    type="text"
                    value={formData.style_guide_ref}
                    onChange={(e) => setFormData({...formData, style_guide_ref: e.target.value})}
                    placeholder="スタイルガイド 2.1.5"
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
                    {editingNoun ? '更新' : '登録'}
                  </button>
                </div>
              </form>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}