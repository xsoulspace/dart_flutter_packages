interface VkPlayLoginStatus {
  authorized: boolean;
  userId?: string;
}

interface VkPlayUserInfo {
  id: string;
  name?: string;
  displayName?: string;
  avatar?: string;
  avatarUrl?: string;
}

interface VkPlayUserProfile {
  id: string;
  name?: string;
  displayName?: string;
  nickname?: string;
  avatar?: string;
  avatarUrl?: string;
}

interface VkPlayFriend {
  id: string;
  name?: string;
  displayName?: string;
  nickname?: string;
  avatar?: string;
  avatarUrl?: string;
}

interface VkPlayApi {
  init(options?: { app_id?: string }): Promise<any>;
  getLoginStatus(): Promise<VkPlayLoginStatus>;
  userInfo(): Promise<VkPlayUserInfo>;
  userProfile(): Promise<VkPlayUserProfile>;
  userFriends(options?: { limit?: number; offset?: number }): Promise<VkPlayFriend[]>;
  userSocialFriends(options?: { limit?: number; offset?: number }): Promise<VkPlayFriend[]>;
  showInviteBox(payload: any): Promise<any>;
  postToFeed(payload: any): Promise<any>;
}

declare const iframeApi: VkPlayApi;
