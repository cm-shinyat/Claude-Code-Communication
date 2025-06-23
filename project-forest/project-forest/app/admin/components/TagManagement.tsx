'use client';

import { useState, useEffect } from 'react';

interface Tag {
  id: number;
  name: string;
  display_text: string;
  icon: string;
  description: string;
  created_at: string;
  updated_at: string;
}

export default function TagManagement() {
  const [tags, setTags] = useState<Tag[]>([]);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingTag, setEditingTag] = useState<Partial<Tag> | null>(null);
  const [searchTerm, setSearchTerm] = useState('');

  const [formData, setFormData] = useState({
    name: '',
    display_text: '',
    icon: '',
    description: ''
  });

  // Load tags from API
  useEffect(() => {
    fetchTags();
  }, []);

  const fetchTags = async (search?: string) => {
    try {
      const url = search ? `/api/tags?search=${encodeURIComponent(search)}` : '/api/tags';
      const response = await fetch(url);
      if (response.ok) {
        const data = await response.json();
        setTags(data);
      } else {
        console.error('Failed to fetch tags');
      }
    } catch (error) {
      console.error('Error fetching tags:', error);
    }
  };

  const filteredTags = searchTerm 
    ? tags.filter(tag =>
        tag.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
        tag.display_text.toLowerCase().includes(searchTerm.toLowerCase()) ||
        tag.description.toLowerCase().includes(searchTerm.toLowerCase())
      )
    : tags;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      if (editingTag) {
        // Update existing tag
        const response = await fetch(`/api/tags/${editingTag.id}`, {
          method: 'PUT',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(formData),
        });
        
        if (response.ok) {
          await fetchTags();
        } else {
          console.error('Failed to update tag');
        }
      } else {
        // Add new tag
        const response = await fetch('/api/tags', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(formData),
        });
        
        if (response.ok) {
          await fetchTags();
        } else {
          console.error('Failed to create tag');
        }
      }
      resetForm();
    } catch (error) {
      console.error('Error submitting tag:', error);
    }
  };

  const handleEdit = (tag: Tag) => {
    setEditingTag(tag);
    setFormData({
      name: tag.name,
      display_text: tag.display_text,
      icon: tag.icon,
      description: tag.description
    });
    setIsModalOpen(true);
  };

  const handleDelete = async (id: number) => {
    if (confirm('このタグを削除してもよろしいですか？関連するテキストからもタグが削除されます。')) {
      try {
        const response = await fetch(`/api/tags/${id}`, {
          method: 'DELETE',
        });
        
        if (response.ok) {
          await fetchTags();
        } else {
          console.error('Failed to delete tag');
        }
      } catch (error) {
        console.error('Error deleting tag:', error);
      }
    }
  };

  const resetForm = () => {
    setFormData({
      name: '',
      display_text: '',
      icon: '',
      description: ''
    });
    setEditingTag(null);
    setIsModalOpen(false);
  };

  const handleSearch = (tagName: string) => {
    // In a real implementation, this would search for texts using this tag
    alert(`「${tagName}」タグを使用しているテキストを検索します（実装予定）`);
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex justify-between items-center">
        <h2 className="text-xl font-semibold text-gray-900">タグ管理</h2>
        <button
          onClick={() => setIsModalOpen(true)}
          className="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition-colors"
        >
          新規タグ追加
        </button>
      </div>

      {/* Info */}
      <div className="bg-blue-50 border border-blue-200 rounded-md p-4">
        <div className="flex">
          <div className="flex-shrink-0">
            <div className="text-blue-400">ℹ️</div>
          </div>
          <div className="ml-3">
            <h3 className="text-sm font-medium text-blue-800">タグについて</h3>
            <div className="mt-2 text-sm text-blue-700">
              <p>タグはテキスト内で動的な値を表示するために使用されます。テキストエディタでタグを使用すると、アイコンで表示され編集不可になります。</p>
            </div>
          </div>
        </div>
      </div>

      {/* Search */}
      <div className="max-w-md">
        <input
          type="text"
          placeholder="タグ名、表示テキスト、説明で検索..."
          value={searchTerm}
          onChange={(e) => {
            setSearchTerm(e.target.value);
            fetchTags(e.target.value);
          }}
          className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
        />
      </div>

      {/* Tags List */}
      <div className="bg-white shadow rounded-lg overflow-hidden">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                タグ名
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                表示テキスト
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
            {filteredTags.map((tag) => (
              <tr key={tag.id} className="hover:bg-gray-50">
                <td className="px-6 py-4 whitespace-nowrap">
                  <div className="flex items-center">
                    <span className="text-lg mr-2">{tag.icon}</span>
                    <div className="text-sm font-medium text-gray-900">
                      {tag.name}
                    </div>
                  </div>
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                    {tag.display_text}
                  </span>
                </td>
                <td className="px-6 py-4">
                  <div className="text-sm text-gray-900 max-w-xs">
                    {tag.description}
                  </div>
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {new Date(tag.updated_at).toLocaleDateString('ja-JP')}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium space-x-2">
                  <button
                    onClick={() => handleSearch(tag.name)}
                    className="text-green-600 hover:text-green-900"
                  >
                    検索
                  </button>
                  <button
                    onClick={() => handleEdit(tag)}
                    className="text-blue-600 hover:text-blue-900"
                  >
                    編集
                  </button>
                  <button
                    onClick={() => handleDelete(tag.id)}
                    className="text-red-600 hover:text-red-900"
                  >
                    削除
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        
        {filteredTags.length === 0 && (
          <div className="text-center py-8 text-gray-500">
            {searchTerm ? '検索条件に一致するタグが見つかりませんでした。' : 'タグがまだ登録されていません。'}
          </div>
        )}
      </div>

      {/* Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50">
          <div className="relative top-20 mx-auto p-5 border w-11/12 max-w-2xl shadow-lg rounded-md bg-white">
            <div className="mt-3">
              <h3 className="text-lg font-medium text-gray-900 mb-4">
                {editingTag ? 'タグ編集' : '新規タグ登録'}
              </h3>
              <form onSubmit={handleSubmit} className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700">タグ名 *</label>
                  <input
                    type="text"
                    required
                    value={formData.name}
                    onChange={(e) => setFormData({...formData, name: e.target.value})}
                    placeholder="character_name"
                    className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                  <p className="text-xs text-gray-500 mt-1">英数字とアンダースコアのみ使用可能</p>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700">表示テキスト *</label>
                  <input
                    type="text"
                    required
                    value={formData.display_text}
                    onChange={(e) => setFormData({...formData, display_text: e.target.value})}
                    placeholder="{CHARACTER_NAME}"
                    className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                  <p className="text-xs text-gray-500 mt-1">テキスト内で実際に表示される形式</p>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700">アイコン</label>
                  <input
                    type="text"
                    value={formData.icon}
                    onChange={(e) => setFormData({...formData, icon: e.target.value})}
                    placeholder="👤"
                    className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                  <p className="text-xs text-gray-500 mt-1">タグを視覚的に識別するためのアイコン（絵文字推奨）</p>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700">説明 *</label>
                  <textarea
                    rows={3}
                    required
                    value={formData.description}
                    onChange={(e) => setFormData({...formData, description: e.target.value})}
                    placeholder="このタグの用途や使用方法を説明してください"
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
                    {editingTag ? '更新' : '登録'}
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