'use client';

import { useState, useEffect } from 'react';

interface Character {
  id: number;
  name: string;
  pronoun_first: string;
  pronoun_second: string;
  face_graphic: string;
  description: string;
  traits: string;
  favorites: string;
  dislikes: string;
  special_reactions: string;
  created_at: string;
  updated_at: string;
}

export default function CharacterManagement() {
  const [characters, setCharacters] = useState<Character[]>([]);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingCharacter, setEditingCharacter] = useState<Partial<Character> | null>(null);
  const [searchTerm, setSearchTerm] = useState('');

  const [formData, setFormData] = useState({
    name: '',
    pronoun_first: '',
    pronoun_second: '',
    face_graphic: '',
    description: '',
    traits: '',
    favorites: '',
    dislikes: '',
    special_reactions: ''
  });

  // Mock data for demonstration
  useEffect(() => {
    const mockCharacters: Character[] = [
      {
        id: 1,
        name: '主人公',
        pronoun_first: '俺',
        pronoun_second: '俺',
        face_graphic: '/images/protagonist.png',
        description: 'ゲームの主人公。正義感が強く、仲間思いの性格。',
        traits: '勇敢、正義感、リーダーシップ',
        favorites: '剣術、冒険、仲間との時間',
        dislikes: '不正、裏切り、弱い者いじめ',
        special_reactions: '怒り時は口調が荒くなる',
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-01T00:00:00Z'
      },
      {
        id: 2,
        name: 'エリス',
        pronoun_first: '私',
        pronoun_second: '私',
        face_graphic: '/images/eris.png',
        description: '魔法使いの少女。知識豊富で冷静だが、時に感情的になることも。',
        traits: '知的、冷静、好奇心旺盛',
        favorites: '読書、魔法研究、静かな場所',
        dislikes: '騒がしい場所、無知、暴力',
        special_reactions: '興奮すると早口になる',
        created_at: '2024-01-02T00:00:00Z',
        updated_at: '2024-01-02T00:00:00Z'
      }
    ];
    setCharacters(mockCharacters);
  }, []);

  const filteredCharacters = characters.filter(character =>
    character.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    character.description.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (editingCharacter) {
      // Update existing character
      setCharacters(characters.map(char => 
        char.id === editingCharacter.id 
          ? { ...char, ...formData, updated_at: new Date().toISOString() }
          : char
      ));
    } else {
      // Add new character
      const newCharacter: Character = {
        id: Math.max(...characters.map(c => c.id), 0) + 1,
        ...formData,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      };
      setCharacters([...characters, newCharacter]);
    }
    resetForm();
  };

  const handleEdit = (character: Character) => {
    setEditingCharacter(character);
    setFormData({
      name: character.name,
      pronoun_first: character.pronoun_first,
      pronoun_second: character.pronoun_second,
      face_graphic: character.face_graphic,
      description: character.description,
      traits: character.traits,
      favorites: character.favorites,
      dislikes: character.dislikes,
      special_reactions: character.special_reactions
    });
    setIsModalOpen(true);
  };

  const handleDelete = (id: number) => {
    if (confirm('このキャラクターを削除してもよろしいですか？')) {
      setCharacters(characters.filter(char => char.id !== id));
    }
  };

  const resetForm = () => {
    setFormData({
      name: '',
      pronoun_first: '',
      pronoun_second: '',
      face_graphic: '',
      description: '',
      traits: '',
      favorites: '',
      dislikes: '',
      special_reactions: ''
    });
    setEditingCharacter(null);
    setIsModalOpen(false);
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex justify-between items-center">
        <h2 className="text-xl font-semibold text-gray-900">キャラクター設定管理</h2>
        <button
          onClick={() => setIsModalOpen(true)}
          className="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition-colors"
        >
          新規追加
        </button>
      </div>

      {/* Search */}
      <div className="max-w-md">
        <input
          type="text"
          placeholder="キャラクター名または説明で検索..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
        />
      </div>

      {/* Characters List */}
      <div className="bg-white shadow rounded-lg overflow-hidden">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                キャラクター名
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                一人称/二人称
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                説明
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
            {filteredCharacters.map((character) => (
              <tr key={character.id} className="hover:bg-gray-50">
                <td className="px-6 py-4 whitespace-nowrap">
                  <div className="flex items-center">
                    <div className="flex-shrink-0 h-10 w-10">
                      <div className="h-10 w-10 rounded-full bg-gray-300 flex items-center justify-center">
                        👤
                      </div>
                    </div>
                    <div className="ml-4">
                      <div className="text-sm font-medium text-gray-900">
                        {character.name}
                      </div>
                    </div>
                  </div>
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {character.pronoun_first}/{character.pronoun_second}
                </td>
                <td className="px-6 py-4">
                  <div className="text-sm text-gray-900 max-w-xs truncate">
                    {character.description}
                  </div>
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {new Date(character.updated_at).toLocaleDateString('ja-JP')}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium space-x-2">
                  <button
                    onClick={() => handleEdit(character)}
                    className="text-blue-600 hover:text-blue-900"
                  >
                    編集
                  </button>
                  <button
                    onClick={() => handleDelete(character.id)}
                    className="text-red-600 hover:text-red-900"
                  >
                    削除
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50">
          <div className="relative top-20 mx-auto p-5 border w-11/12 max-w-4xl shadow-lg rounded-md bg-white">
            <div className="mt-3">
              <h3 className="text-lg font-medium text-gray-900 mb-4">
                {editingCharacter ? 'キャラクター編集' : '新規キャラクター登録'}
              </h3>
              <form onSubmit={handleSubmit} className="space-y-4">
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-gray-700">キャラクター名</label>
                    <input
                      type="text"
                      required
                      value={formData.name}
                      onChange={(e) => setFormData({...formData, name: e.target.value})}
                      className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-700">顔グラフィック</label>
                    <input
                      type="text"
                      value={formData.face_graphic}
                      onChange={(e) => setFormData({...formData, face_graphic: e.target.value})}
                      placeholder="/images/character.png"
                      className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                    />
                  </div>
                </div>
                
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-gray-700">一人称</label>
                    <input
                      type="text"
                      value={formData.pronoun_first}
                      onChange={(e) => setFormData({...formData, pronoun_first: e.target.value})}
                      className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-700">二人称</label>
                    <input
                      type="text"
                      value={formData.pronoun_second}
                      onChange={(e) => setFormData({...formData, pronoun_second: e.target.value})}
                      className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                    />
                  </div>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700">基本説明</label>
                  <textarea
                    rows={3}
                    value={formData.description}
                    onChange={(e) => setFormData({...formData, description: e.target.value})}
                    className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700">特徴・性格</label>
                  <textarea
                    rows={2}
                    value={formData.traits}
                    onChange={(e) => setFormData({...formData, traits: e.target.value})}
                    placeholder="勇敢、正義感、リーダーシップ"
                    className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-gray-700">好物・趣味</label>
                    <textarea
                      rows={2}
                      value={formData.favorites}
                      onChange={(e) => setFormData({...formData, favorites: e.target.value})}
                      className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-700">嫌いなもの</label>
                    <textarea
                      rows={2}
                      value={formData.dislikes}
                      onChange={(e) => setFormData({...formData, dislikes: e.target.value})}
                      className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                    />
                  </div>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700">特殊反応</label>
                  <textarea
                    rows={2}
                    value={formData.special_reactions}
                    onChange={(e) => setFormData({...formData, special_reactions: e.target.value})}
                    placeholder="怒り時は口調が荒くなる"
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
                    {editingCharacter ? '更新' : '登録'}
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