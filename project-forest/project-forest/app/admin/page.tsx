'use client';

import { useState } from 'react';
import Navigation from './components/Navigation';
import CharacterManagement from './components/CharacterManagement';
import TagManagement from './components/TagManagement';
import ProperNounManagement from './components/ProperNounManagement';
import ForbiddenWordManagement from './components/ForbiddenWordManagement';
import StyleManagement from './components/StyleManagement';

type TabType = 'characters' | 'tags' | 'proper-nouns' | 'forbidden-words' | 'styles';

export default function AdminPage() {
  const [activeTab, setActiveTab] = useState<TabType>('characters');

  const renderContent = () => {
    switch (activeTab) {
      case 'characters':
        return <CharacterManagement />;
      case 'tags':
        return <TagManagement />;
      case 'proper-nouns':
        return <ProperNounManagement />;
      case 'forbidden-words':
        return <ForbiddenWordManagement />;
      case 'styles':
        return <StyleManagement />;
      default:
        return <CharacterManagement />;
    }
  };

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white shadow-sm border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center h-16">
            <h1 className="text-2xl font-bold text-gray-900">
              Project Forest - 管理画面
            </h1>
            <div className="text-sm text-gray-500">
              テキスト管理システム
            </div>
          </div>
        </div>
      </header>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <Navigation activeTab={activeTab} onTabChange={setActiveTab} />
        <div className="mt-6">
          {renderContent()}
        </div>
      </div>
    </div>
  );
}