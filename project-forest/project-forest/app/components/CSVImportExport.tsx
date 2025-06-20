'use client';

import { useState, useRef } from 'react';

interface CSVImportExportProps {
  onImportComplete?: () => void;
  currentFilters?: any;
  currentUser?: { id: number; username: string };
}

export default function CSVImportExport({ 
  onImportComplete, 
  currentFilters = {},
  currentUser 
}: CSVImportExportProps) {
  const [isExporting, setIsExporting] = useState(false);
  const [isImporting, setIsImporting] = useState(false);
  const [importResult, setImportResult] = useState<any>(null);
  const [exportOptions, setExportOptions] = useState({
    includeTranslations: true,
    format: 'csv',
  });
  const [importOptions, setImportOptions] = useState({
    updateExisting: false,
  });
  
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleExport = async () => {
    setIsExporting(true);
    try {
      const response = await fetch('/api/csv/export', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          filters: currentFilters,
          includeTranslations: exportOptions.includeTranslations,
          format: exportOptions.format,
          user_id: currentUser?.id,
        }),
      });

      if (response.ok) {
        const blob = await response.blob();
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `text_entries_${new Date().toISOString().split('T')[0]}.csv`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        window.URL.revokeObjectURL(url);
      } else {
        const error = await response.json();
        alert(`エクスポートに失敗しました: ${error.error}`);
      }
    } catch (error) {
      console.error('Export error:', error);
      alert('エクスポートに失敗しました');
    } finally {
      setIsExporting(false);
    }
  };

  const handleImport = async (file: File) => {
    if (!currentUser) {
      alert('ユーザー情報が必要です');
      return;
    }

    setIsImporting(true);
    setImportResult(null);

    try {
      const formData = new FormData();
      formData.append('file', file);
      formData.append('user_id', currentUser.id.toString());
      formData.append('update_existing', importOptions.updateExisting.toString());

      const response = await fetch('/api/csv/import', {
        method: 'POST',
        body: formData,
      });

      if (response.ok) {
        const result = await response.json();
        setImportResult(result);
        if (onImportComplete) {
          onImportComplete();
        }
      } else {
        const error = await response.json();
        alert(`インポートに失敗しました: ${error.error}`);
      }
    } catch (error) {
      console.error('Import error:', error);
      alert('インポートに失敗しました');
    } finally {
      setIsImporting(false);
      if (fileInputRef.current) {
        fileInputRef.current.value = '';
      }
    }
  };

  const handleFileSelect = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (file) {
      if (!file.name.toLowerCase().endsWith('.csv')) {
        alert('CSVファイルを選択してください');
        return;
      }
      handleImport(file);
    }
  };

  const downloadTemplate = () => {
    const headers = [
      'label',
      'file_category',
      'original_text',
      'language_code',
      'status',
      'max_chars',
      'max_lines',
      'translated_text',
    ];
    
    const sampleData = [
      'SAMPLE_001',
      'サンプル',
      'これはサンプルテキストです',
      'ja',
      '未処理',
      '50',
      '2',
      '',
    ];

    const csvContent = [
      headers.join(','),
      sampleData.join(','),
    ].join('\n');

    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'text_entries_template.csv';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    window.URL.revokeObjectURL(url);
  };

  return (
    <div className="bg-white p-6 rounded-lg shadow">
      <h3 className="text-lg font-semibold mb-4">CSV インポート・エクスポート</h3>
      
      <div className="grid md:grid-cols-2 gap-6">
        {/* Export Section */}
        <div className="space-y-4">
          <h4 className="font-medium text-gray-900">エクスポート</h4>
          
          <div className="space-y-3">
            <label className="flex items-center space-x-2">
              <input
                type="checkbox"
                checked={exportOptions.includeTranslations}
                onChange={(e) => setExportOptions(prev => ({
                  ...prev,
                  includeTranslations: e.target.checked
                }))}
                className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
              />
              <span className="text-sm">翻訳データを含める</span>
            </label>
          </div>

          <button
            onClick={handleExport}
            disabled={isExporting}
            className="w-full px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:opacity-50"
          >
            {isExporting ? 'エクスポート中...' : 'CSVエクスポート'}
          </button>

          <p className="text-xs text-gray-600">
            現在のフィルター条件でデータをエクスポートします
          </p>
        </div>

        {/* Import Section */}
        <div className="space-y-4">
          <h4 className="font-medium text-gray-900">インポート</h4>
          
          <div className="space-y-3">
            <label className="flex items-center space-x-2">
              <input
                type="checkbox"
                checked={importOptions.updateExisting}
                onChange={(e) => setImportOptions(prev => ({
                  ...prev,
                  updateExisting: e.target.checked
                }))}
                className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
              />
              <span className="text-sm">既存データを更新する（IDがある場合）</span>
            </label>
          </div>

          <input
            ref={fileInputRef}
            type="file"
            accept=".csv"
            onChange={handleFileSelect}
            className="hidden"
          />
          
          <button
            onClick={() => fileInputRef.current?.click()}
            disabled={isImporting}
            className="w-full px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-green-500 disabled:opacity-50"
          >
            {isImporting ? 'インポート中...' : 'CSVファイルを選択'}
          </button>

          <button
            onClick={downloadTemplate}
            className="w-full px-4 py-2 bg-gray-600 text-white rounded-md hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-gray-500"
          >
            テンプレートダウンロード
          </button>

          <div className="text-xs text-gray-600 space-y-1">
            <p>必須列: label, original_text, language_code</p>
            <p>オプション列: file_category, status, max_chars, max_lines, translated_text</p>
          </div>
        </div>
      </div>

      {/* Import Result */}
      {importResult && (
        <div className="mt-6 p-4 bg-gray-50 rounded-lg">
          <h5 className="font-medium text-gray-900 mb-2">インポート結果</h5>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
            <div>
              <span className="text-gray-600">総行数:</span>
              <span className="ml-2 font-medium">{importResult.total_rows}</span>
            </div>
            <div>
              <span className="text-gray-600">作成:</span>
              <span className="ml-2 font-medium text-green-600">{importResult.created}</span>
            </div>
            <div>
              <span className="text-gray-600">更新:</span>
              <span className="ml-2 font-medium text-blue-600">{importResult.updated}</span>
            </div>
            <div>
              <span className="text-gray-600">エラー:</span>
              <span className="ml-2 font-medium text-red-600">{importResult.errors.length}</span>
            </div>
          </div>
          
          {importResult.errors.length > 0 && (
            <div className="mt-3">
              <details className="cursor-pointer">
                <summary className="text-sm font-medium text-red-600">
                  エラー詳細 ({importResult.errors.length}件)
                </summary>
                <div className="mt-2 p-3 bg-red-50 rounded text-sm">
                  <ul className="space-y-1">
                    {importResult.errors.slice(0, 10).map((error: string, index: number) => (
                      <li key={index} className="text-red-700">• {error}</li>
                    ))}
                    {importResult.errors.length > 10 && (
                      <li className="text-red-600 italic">...他 {importResult.errors.length - 10} 件</li>
                    )}
                  </ul>
                </div>
              </details>
            </div>
          )}
        </div>
      )}
    </div>
  );
}