'use client';

import { useState, useEffect } from 'react';

interface ProgressData {
  data: Array<{
    status?: string;
    category?: string;
    language_code?: string;
    count: number;
    percentage: number;
    completed?: number;
    pending?: number;
    review_requested?: number;
    omitted?: number;
  }>;
  overall: {
    total_entries: number;
    completed_entries: number;
    pending_entries: number;
    review_requested_entries: number;
    omitted_entries: number;
    consultation_entries: number;
  };
  recentActivity: Array<{
    edit_type: string;
    created_at: string;
    editor_name: string;
    text_label: string;
  }>;
  groupBy: string;
}

interface ProgressDashboardProps {
  selectedCategory?: string;
}

export default function ProgressDashboard({ selectedCategory }: ProgressDashboardProps) {
  const [progressData, setProgressData] = useState<ProgressData | null>(null);
  const [groupBy, setGroupBy] = useState<'status' | 'category' | 'language'>('status');
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    fetchProgressData();
  }, [groupBy, selectedCategory]);

  const fetchProgressData = async () => {
    setIsLoading(true);
    try {
      const params = new URLSearchParams({
        groupBy,
        ...(selectedCategory && { category: selectedCategory }),
      });
      
      const response = await fetch(`/api/progress?${params}`);
      if (response.ok) {
        const data = await response.json();
        setProgressData(data);
      }
    } catch (error) {
      console.error('Error fetching progress data:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case '完了': return 'bg-green-500';
      case '確認依頼': return 'bg-yellow-500';
      case '原文相談': return 'bg-orange-500';
      case '未処理': return 'bg-blue-500';
      case 'オミット': return 'bg-gray-500';
      default: return 'bg-gray-400';
    }
  };

  const getStatusLabel = (status: string) => {
    const labels: Record<string, string> = {
      '完了': 'Completed',
      '確認依頼': 'Review Requested',
      '原文相談': 'Consultation',
      '未処理': 'Pending',
      'オミット': 'Omitted',
    };
    return labels[status] || status;
  };

  if (isLoading) {
    return (
      <div className="bg-white p-6 rounded-lg shadow">
        <div className="text-center py-8">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600 mx-auto"></div>
          <p className="mt-2 text-gray-600">データを読み込み中...</p>
        </div>
      </div>
    );
  }

  if (!progressData) {
    return (
      <div className="bg-white p-6 rounded-lg shadow">
        <p className="text-center text-gray-600">データを取得できませんでした</p>
      </div>
    );
  }

  const { data, overall, recentActivity } = progressData;

  return (
    <div className="space-y-6">
      {/* Overall Statistics */}
      <div className="bg-white p-6 rounded-lg shadow">
        <h3 className="text-lg font-semibold mb-4">全体統計</h3>
        <div className="grid grid-cols-2 md:grid-cols-6 gap-4">
          <div className="text-center">
            <div className="text-2xl font-bold text-gray-900">{overall.total_entries}</div>
            <div className="text-sm text-gray-600">総エントリ数</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-green-600">{overall.completed_entries}</div>
            <div className="text-sm text-gray-600">完了</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-blue-600">{overall.pending_entries}</div>
            <div className="text-sm text-gray-600">未処理</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-yellow-600">{overall.review_requested_entries}</div>
            <div className="text-sm text-gray-600">確認依頼</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-orange-600">{overall.consultation_entries}</div>
            <div className="text-sm text-gray-600">原文相談</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-gray-600">{overall.omitted_entries}</div>
            <div className="text-sm text-gray-600">オミット</div>
          </div>
        </div>
      </div>

      {/* Progress Breakdown */}
      <div className="bg-white p-6 rounded-lg shadow">
        <div className="flex justify-between items-center mb-4">
          <h3 className="text-lg font-semibold">進捗詳細</h3>
          <div className="flex space-x-2">
            <button
              onClick={() => setGroupBy('status')}
              className={`px-3 py-1 rounded text-sm ${
                groupBy === 'status'
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
              }`}
            >
              ステータス別
            </button>
            <button
              onClick={() => setGroupBy('category')}
              className={`px-3 py-1 rounded text-sm ${
                groupBy === 'category'
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
              }`}
            >
              カテゴリ別
            </button>
            <button
              onClick={() => setGroupBy('language')}
              className={`px-3 py-1 rounded text-sm ${
                groupBy === 'language'
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
              }`}
            >
              言語別
            </button>
          </div>
        </div>

        <div className="space-y-4">
          {data.map((item, index) => {
            const label = item.status || item.category || item.language_code || 'Unknown';
            const isStatus = groupBy === 'status';
            
            return (
              <div key={index} className="border rounded-lg p-4">
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center space-x-3">
                    {isStatus && (
                      <div className={`w-3 h-3 rounded-full ${getStatusColor(label)}`}></div>
                    )}
                    <span className="font-medium">
                      {isStatus ? `${label} (${getStatusLabel(label)})` : label}
                    </span>
                  </div>
                  <div className="text-right">
                    <span className="text-lg font-semibold">{item.count}</span>
                    <span className="text-sm text-gray-600 ml-2">({item.percentage.toFixed(1)}%)</span>
                  </div>
                </div>
                
                {/* Progress bar */}
                <div className="w-full bg-gray-200 rounded-full h-2 mb-2">
                  <div
                    className={`h-2 rounded-full ${isStatus ? getStatusColor(label) : 'bg-blue-500'}`}
                    style={{ width: `${item.percentage}%` }}
                  ></div>
                </div>

                {/* Detailed breakdown for non-status groupings */}
                {!isStatus && (item.completed !== undefined) && (
                  <div className="grid grid-cols-4 gap-2 text-sm text-gray-600">
                    <div>完了: {item.completed || 0}</div>
                    <div>未処理: {item.pending || 0}</div>
                    <div>確認依頼: {item.review_requested || 0}</div>
                    <div>オミット: {item.omitted || 0}</div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>

      {/* Recent Activity */}
      <div className="bg-white p-6 rounded-lg shadow">
        <h3 className="text-lg font-semibold mb-4">最近のアクティビティ</h3>
        {recentActivity.length === 0 ? (
          <p className="text-gray-600 text-center py-4">最近のアクティビティがありません</p>
        ) : (
          <div className="space-y-3">
            {recentActivity.map((activity, index) => (
              <div key={index} className="flex items-center justify-between p-3 bg-gray-50 rounded">
                <div className="flex items-center space-x-3">
                  <span className={`px-2 py-1 rounded text-xs font-medium ${
                    activity.edit_type === 'create' ? 'bg-green-100 text-green-800' :
                    activity.edit_type === 'update' ? 'bg-blue-100 text-blue-800' :
                    'bg-red-100 text-red-800'
                  }`}>
                    {activity.edit_type === 'create' ? '作成' :
                     activity.edit_type === 'update' ? '更新' : '削除'}
                  </span>
                  <span className="font-medium">{activity.editor_name}</span>
                  <span className="text-gray-600">が</span>
                  <span className="font-medium">{activity.text_label}</span>
                  <span className="text-gray-600">を{
                    activity.edit_type === 'create' ? '作成しました' :
                    activity.edit_type === 'update' ? '更新しました' : '削除しました'
                  }</span>
                </div>
                <span className="text-sm text-gray-500">
                  {new Date(activity.created_at).toLocaleString()}
                </span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}