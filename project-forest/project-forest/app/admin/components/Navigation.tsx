interface NavigationProps {
  activeTab: string;
  onTabChange: (tab: any) => void;
}

export default function Navigation({ activeTab, onTabChange }: NavigationProps) {
  const tabs = [
    { id: 'characters', name: 'キャラクター設定', icon: '👤' },
    { id: 'tags', name: 'タグ管理', icon: '🏷️' },
    { id: 'proper-nouns', name: '固有名詞管理', icon: '📝' },
    { id: 'forbidden-words', name: '禁止用語管理', icon: '🚫' },
    { id: 'styles', name: 'スタイル設定', icon: '🎨' },
  ];

  return (
    <div className="border-b border-gray-200">
      <nav className="-mb-px flex space-x-8">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => onTabChange(tab.id)}
            className={`
              flex items-center space-x-2 py-4 px-1 border-b-2 font-medium text-sm
              ${activeTab === tab.id
                ? 'border-blue-500 text-blue-600'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }
            `}
          >
            <span className="text-lg">{tab.icon}</span>
            <span>{tab.name}</span>
          </button>
        ))}
      </nav>
    </div>
  );
}