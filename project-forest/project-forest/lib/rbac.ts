export type Permission = 
  | 'read_texts'
  | 'write_texts' 
  | 'edit_original_texts'
  | 'translate_texts'
  | 'review_translations'
  | 'manage_characters'
  | 'manage_styles'
  | 'manage_tags'
  | 'manage_forbidden_words'
  | 'manage_proper_nouns'
  | 'import_export_files'
  | 'view_edit_history'
  | 'manage_users'
  | 'admin_access';

export type Role = 'admin' | 'scenario_writer' | 'translator' | 'reviewer';

const rolePermissions: Record<Role, Permission[]> = {
  admin: [
    'read_texts',
    'write_texts',
    'edit_original_texts',
    'translate_texts',
    'review_translations',
    'manage_characters',
    'manage_styles',
    'manage_tags',
    'manage_forbidden_words',
    'manage_proper_nouns',
    'import_export_files',
    'view_edit_history',
    'manage_users',
    'admin_access'
  ],
  scenario_writer: [
    'read_texts',
    'write_texts',
    'edit_original_texts',
    'manage_characters',
    'manage_styles',
    'manage_tags',
    'manage_proper_nouns',
    'view_edit_history'
  ],
  translator: [
    'read_texts',
    'translate_texts',
    'view_edit_history'
  ],
  reviewer: [
    'read_texts',
    'translate_texts',
    'review_translations',
    'view_edit_history'
  ]
};

export function hasPermission(userRole: Role, permission: Permission): boolean {
  return rolePermissions[userRole]?.includes(permission) || false;
}

export function hasAnyPermission(userRole: Role, permissions: Permission[]): boolean {
  return permissions.some(permission => hasPermission(userRole, permission));
}

export function hasAllPermissions(userRole: Role, permissions: Permission[]): boolean {
  return permissions.every(permission => hasPermission(userRole, permission));
}

export function getUserPermissions(userRole: Role): Permission[] {
  return rolePermissions[userRole] || [];
}

export function canAccessResource(userRole: Role, resourceType: string): boolean {
  const resourcePermissions: Record<string, Permission[]> = {
    'text-entries': ['read_texts'],
    'text-editing': ['write_texts', 'edit_original_texts'],
    'translations': ['translate_texts'],
    'translation-review': ['review_translations'],
    'characters': ['manage_characters'],
    'styles': ['manage_styles'],
    'tags': ['manage_tags'],
    'forbidden-words': ['manage_forbidden_words'],
    'proper-nouns': ['manage_proper_nouns'],
    'file-operations': ['import_export_files'],
    'edit-history': ['view_edit_history'],
    'user-management': ['manage_users'],
    'admin-panel': ['admin_access']
  };

  const requiredPermissions = resourcePermissions[resourceType];
  if (!requiredPermissions) {
    return false;
  }

  return hasAnyPermission(userRole, requiredPermissions);
}

export function validateTextOperation(
  userRole: Role, 
  operation: 'read' | 'create' | 'update' | 'delete',
  textType: 'original' | 'translation'
): boolean {
  switch (operation) {
    case 'read':
      return hasPermission(userRole, 'read_texts');
    
    case 'create':
      if (textType === 'original') {
        return hasPermission(userRole, 'edit_original_texts');
      } else {
        return hasPermission(userRole, 'translate_texts');
      }
    
    case 'update':
      if (textType === 'original') {
        return hasPermission(userRole, 'edit_original_texts');
      } else {
        return hasAnyPermission(userRole, ['translate_texts', 'review_translations']);
      }
    
    case 'delete':
      return hasPermission(userRole, 'admin_access');
    
    default:
      return false;
  }
}

export function canModifyUserRole(currentUserRole: Role, targetUserRole: Role): boolean {
  if (!hasPermission(currentUserRole, 'manage_users')) {
    return false;
  }

  const roleHierarchy: Record<Role, number> = {
    'admin': 4,
    'reviewer': 3,
    'scenario_writer': 2,
    'translator': 1
  };

  return roleHierarchy[currentUserRole] > roleHierarchy[targetUserRole];
}

export interface AccessControlContext {
  userRole: Role;
  userId: number;
  resourceOwnerId?: number;
}

export function checkAccess(
  context: AccessControlContext,
  permission: Permission,
  allowOwnerAccess: boolean = false
): boolean {
  const hasRolePermission = hasPermission(context.userRole, permission);
  
  if (hasRolePermission) {
    return true;
  }
  
  if (allowOwnerAccess && context.resourceOwnerId && context.userId === context.resourceOwnerId) {
    return true;
  }
  
  return false;
}