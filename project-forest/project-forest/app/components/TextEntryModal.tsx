'use client';

import { useState, useEffect } from 'react';
import { TextEntry, Translation, EditHistory } from '@/lib/types';

interface TextEntryModalProps {
  entry: TextEntry | null;
  isOpen: boolean;
  onClose: () => void;
  onSave: (entry: Partial<TextEntry>) => Promise<void>;
  onDelete?: (id: number) => Promise<void>;
  currentUser?: { id: number; username: string; role: string };
}

export default function TextEntryModal({
  entry,
  isOpen,
  onClose,
  onSave,
  onDelete,
  currentUser
}: TextEntryModalProps) {
  const [formData, setFormData] = useState<Partial<TextEntry>>({});
  const [translations, setTranslations] = useState<Translation[]>([]);
  const [history, setHistory] = useState<EditHistory[]>([]);
  const [activeTab, setActiveTab] = useState<'edit' | 'translations' | 'history'>('edit');
  const [isLoading, setIsLoading] = useState(false);
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    if (entry) {
      setFormData({
        id: entry.id,
        label: entry.label,
        file_category: entry.file_category,
        original_text: entry.original_text,
        language_code: entry.language_code,
        status: entry.status,
        max_chars: entry.max_chars,
        max_lines: entry.max_lines,
      });
      
      // Fetch detailed data if editing existing entry
      if (entry.id) {
        fetchEntryDetails(entry.id);
      }
    } else {
      setFormData({
        language_code: 'ja',
        status: '未処理',
      });
      setTranslations([]);
      setHistory([]);
    }
  }, [entry]);

  const fetchEntryDetails = async (id: number) => {
    setIsLoading(true);
    try {
      const response = await fetch(`/api/text-entries/${id}`);
      if (response.ok) {
        const data = await response.json();
        setTranslations(data.translations || []);
        setHistory(data.history || []);
      }
    } catch (error) {
      console.error('Error fetching entry details:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleSave = async () => {
    if (!formData.label?.trim()) {
      alert('ラベルは必須です');
      return;
    }

    setIsSaving(true);
    try {
      await onSave({
        ...formData,
        updated_by: currentUser?.id,
      });
      onClose();
    } catch (error) {
      console.error('Error saving entry:', error);
      alert('保存に失敗しました');
    } finally {
      setIsSaving(false);
    }
  };

  const handleDelete = async () => {
    if (!entry?.id || !onDelete) return;
    
    if (confirm('このエントリを削除しますか？この操作は取り消せません。')) {
      try {
        await onDelete(entry.id);
        onClose();
      } catch (error) {
        console.error('Error deleting entry:', error);
        alert('削除に失敗しました');
      }
    }
  };

  const handleRevert = async (historyId: number) => {
    if (!entry?.id || !currentUser) return;
    
    if (confirm('この履歴に戻しますか？')) {
      try {
        const response = await fetch(`/api/history/${entry.id}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ historyId, userId: currentUser.id }),
        });
        
        if (response.ok) {
          const data = await response.json();
          setFormData(prev => ({
            ...prev,
            original_text: data.entry.original_text,
          }));
          fetchEntryDetails(entry.id);
        }
      } catch (error) {
        console.error('Error reverting entry:', error);
        alert('履歴の復元に失敗しました');
      }
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50">
      <div className="bg-white rounded-lg shadow-xl max-w-4xl w-full max-h-[90vh] overflow-hidden">
        <div className="flex justify-between items-center p-6 border-b">
          <h2 className="text-xl font-semibold">
            {entry ? 'テキストエントリ編集' : '新規テキストエントリ'}
          </h2>
          <button
            onClick={onClose}
            className="text-gray-500 hover:text-gray-700 text-2xl"
          >
            ×
          </button>
        </div>

        {entry && (
          <div className="border-b">
            <nav className="flex">
              <button
                className={`px-6 py-3 font-medium ${
                  activeTab === 'edit'
                    ? 'text-blue-600 border-b-2 border-blue-600'
                    : 'text-gray-600 hover:text-gray-800'
                }`}
                onClick={() => setActiveTab('edit')}
              >
                編集
              </button>
              <button
                className={`px-6 py-3 font-medium ${
                  activeTab === 'translations'
                    ? 'text-blue-600 border-b-2 border-blue-600'
                    : 'text-gray-600 hover:text-gray-800'
                }`}
                onClick={() => setActiveTab('translations')}
              >
                翻訳 ({translations.length})
              </button>
              <button
                className={`px-6 py-3 font-medium ${
                  activeTab === 'history'
                    ? 'text-blue-600 border-b-2 border-blue-600'
                    : 'text-gray-600 hover:text-gray-800'
                }`}
                onClick={() => setActiveTab('history')}
              >
                履歴 ({history.length})
              </button>
            </nav>
          </div>
        )}

        <div className="p-6 overflow-y-auto max-h-[60vh]">
          {activeTab === 'edit' && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    ラベル *
                  </label>
                  <input
                    type="text"
                    value={formData.label || ''}
                    onChange={(e) => setFormData(prev => ({ ...prev, label: e.target.value }))}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                    placeholder="例: MENU_001"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    ファイルカテゴリ
                  </label>
                  <input
                    type="text"
                    value={formData.file_category || ''}
                    onChange={(e) => setFormData(prev => ({ ...prev, file_category: e.target.value }))}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                    placeholder="例: メニュー"
                  />
                </div>
              </div>

              <div className="grid grid-cols-3 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    言語コード
                  </label>
                  <select
                    value={formData.language_code || 'ja'}
                    onChange={(e) => setFormData(prev => ({ ...prev, language_code: e.target.value }))}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                  >
                    <option value="ja">日本語 (ja)</option>
                    <option value="en">English (en)</option>
                    <option value="ko">한국어 (ko)</option>
                    <option value="zh">中文 (zh)</option>
                  </select>
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    ステータス
                  </label>
                  <select
                    value={formData.status || '未処理'}
                    onChange={(e) => setFormData(prev => ({ ...prev, status: e.target.value as any }))}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                  >
                    <option value="未処理">未処理</option>
                    <option value="確認依頼">確認依頼</option>
                    <option value="完了">完了</option>
                    <option value="オミット">オミット</option>
                    <option value="原文相談">原文相談</option>
                  </select>
                </div>
                <div className="grid grid-cols-2 gap-2">
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      最大文字数
                    </label>
                    <input
                      type="number"
                      value={formData.max_chars || ''}
                      onChange={(e) => setFormData(prev => ({ ...prev, max_chars: parseInt(e.target.value) || undefined }))}
                      className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                      min="1"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      最大行数
                    </label>
                    <input
                      type="number"
                      value={formData.max_lines || ''}
                      onChange={(e) => setFormData(prev => ({ ...prev, max_lines: parseInt(e.target.value) || undefined }))}
                      className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                      min="1"
                    />
                  </div>
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  原文
                </label>
                <textarea
                  value={formData.original_text || ''}
                  onChange={(e) => setFormData(prev => ({ ...prev, original_text: e.target.value }))}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                  rows={6}
                  placeholder="原文を入力してください"
                />
                {formData.max_chars && formData.original_text && (
                  <div className="mt-1 text-sm text-gray-600">
                    文字数: {formData.original_text.length} / {formData.max_chars}
                    {formData.original_text.length > formData.max_chars && (
                      <span className="text-red-600 ml-2">文字数超過</span>
                    )}
                  </div>
                )}
              </div>
            </div>
          )}

          {activeTab === 'translations' && (
            <div className="space-y-4">
              {isLoading ? (
                <div className="text-center py-4">読み込み中...</div>
              ) : translations.length === 0 ? (
                <div className="text-center py-4 text-gray-500">翻訳がありません</div>
              ) : (
                translations.map((translation) => (
                  <div key={translation.id} className="border rounded-lg p-4">
                    <div className="flex justify-between items-center mb-2">
                      <div className="flex items-center space-x-4">
                        <span className="font-medium">{translation.language_code}</span>
                        <span className={`px-2 py-1 rounded text-sm ${
                          translation.status === '完了' ? 'bg-green-100 text-green-800' :
                          translation.status === '確認依頼' ? 'bg-yellow-100 text-yellow-800' :
                          translation.status === 'オミット' ? 'bg-gray-100 text-gray-800' :
                          'bg-blue-100 text-blue-800'
                        }`}>
                          {translation.status}
                        </span>
                      </div>
                      <span className="text-sm text-gray-500">
                        {new Date(translation.updated_at).toLocaleString()}
                      </span>
                    </div>
                    <div className="text-gray-700">
                      {translation.translated_text || '(翻訳なし)'}
                    </div>
                  </div>
                ))
              )}
            </div>
          )}

          {activeTab === 'history' && (
            <div className="space-y-4">
              {isLoading ? (
                <div className="text-center py-4">読み込み中...</div>
              ) : history.length === 0 ? (
                <div className="text-center py-4 text-gray-500">履歴がありません</div>
              ) : (
                history.map((hist) => (
                  <div key={hist.id} className="border rounded-lg p-4">
                    <div className="flex justify-between items-center mb-2">
                      <div className="flex items-center space-x-4">
                        <span className={`px-2 py-1 rounded text-sm ${
                          hist.edit_type === 'create' ? 'bg-green-100 text-green-800' :
                          hist.edit_type === 'update' ? 'bg-blue-100 text-blue-800' :
                          'bg-red-100 text-red-800'
                        }`}>
                          {hist.edit_type === 'create' ? '作成' :
                           hist.edit_type === 'update' ? '更新' : '削除'}
                        </span>
                        <span className="text-sm font-medium">{hist.editor_name}</span>
                      </div>
                      <div className="flex items-center space-x-2">
                        <span className="text-sm text-gray-500">
                          {new Date(hist.created_at).toLocaleString()}
                        </span>
                        {hist.edit_type === 'update' && (
                          <button
                            onClick={() => handleRevert(hist.id)}
                            className="text-xs px-2 py-1 bg-gray-100 hover:bg-gray-200 rounded"
                          >
                            復元
                          </button>
                        )}
                      </div>
                    </div>
                    {hist.old_text !== hist.new_text && (
                      <div className="grid grid-cols-2 gap-4 text-sm">
                        {hist.old_text && (
                          <div>
                            <div className="text-gray-600 font-medium mb-1">変更前:</div>
                            <div className="bg-red-50 p-2 rounded border">{hist.old_text}</div>
                          </div>
                        )}
                        {hist.new_text && (
                          <div>
                            <div className="text-gray-600 font-medium mb-1">変更後:</div>
                            <div className="bg-green-50 p-2 rounded border">{hist.new_text}</div>
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                ))
              )}
            </div>
          )}
        </div>

        <div className="flex justify-between items-center p-6 border-t bg-gray-50">
          <div>
            {entry && onDelete && (
              <button
                onClick={handleDelete}
                className="px-4 py-2 bg-red-600 text-white rounded-md hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500"
              >
                削除
              </button>
            )}
          </div>
          <div className="flex space-x-3">
            <button
              onClick={onClose}
              className="px-4 py-2 bg-gray-300 text-gray-700 rounded-md hover:bg-gray-400 focus:outline-none focus:ring-2 focus:ring-gray-500"
            >
              キャンセル
            </button>
            <button
              onClick={handleSave}
              disabled={isSaving}
              className="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:opacity-50"
            >
              {isSaving ? '保存中...' : '保存'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}