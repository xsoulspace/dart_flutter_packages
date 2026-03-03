// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: synthesized from CrazyGames docs + runtime SDK script
// SDK version: 3.6.0
// Docs URLs:
//  - https://docs.crazygames.com/sdk/intro/
//  - https://docs.crazygames.com/sdk/video-ads/
//  - https://docs.crazygames.com/sdk/banners/
//  - https://docs.crazygames.com/sdk/game/
//  - https://docs.crazygames.com/sdk/user/
//  - https://docs.crazygames.com/sdk/data/
//  - https://docs.crazygames.com/sdk/in-game-purchases/

export type Environment = "crazygames" | "local" | "disabled";
export type AdType = "midgame" | "rewarded";
export type PaymentProvider = "xsolla";
export type AdblockPopupState = "open";
export type DeviceType = "desktop" | "tablet" | "mobile";
export type ApplicationType = "google_play_store" | "apple_store" | "pwa" | "web";

export interface SdkError {
  code: string;
  message: string;
  containerId?: string;
}

export interface User {
  id?: string;
  username: string;
  profilePictureUrl: string;
}

export interface BrowserInfo {
  name: string;
  version: string;
}

export interface OsInfo {
  name: string;
  version: string;
}

export interface DeviceInfo {
  type: DeviceType;
}

export interface SystemInfo {
  countryCode: string;
  locale: string;
  device: DeviceInfo;
  os: OsInfo;
  browser: BrowserInfo;
  applicationType: ApplicationType;
}

export interface Friend {
  id: string;
  username: string;
  profilePictureUrl: string;
}

export interface FriendsPage {
  friends: Friend[];
  page: number;
  size: number;
  hasMore: boolean;
  total: number;
}

export interface FriendsListOptions {
  page: number;
  size: number;
}

export interface AccountLinkResponse {
  response: "yes" | "no";
}

export interface GameSettings {
  disableChat: boolean;
  muteAudio: boolean;
}

export interface BannerRequest {
  id: string;
  width: number;
  height: number;
  x?: number;
  y?: number;
}

export interface OverlayBannerRequest {
  id: string;
  size: string;
  anchor: { x: number; y: number };
  position: { x: number; y: number };
  pivot?: { x: number; y: number };
}

export interface CrazyGamesAdCallbacks {
  adStarted?: () => void;
  adFinished?: () => void;
  adError?: (error: SdkError) => void;
}

export interface CrazyGamesAd {
  prefetchAd(adType: AdType): void;
  requestAd(adType: AdType, callbacks?: CrazyGamesAdCallbacks): Promise<void>;
  hasAdblock(): Promise<boolean>;
  addAdblockPopupListener(listener: (state: AdblockPopupState) => void): void;
  removeAdblockPopupListener(listener: (state: AdblockPopupState) => void): void;
  isAdPlaying: boolean;
}

export interface CrazyGamesBanner {
  prefetchBanner(request: BannerRequest): Promise<{ id: string; banner: BannerRequest; renderOptions: Record<string, unknown> }>;
  requestBanner(request: BannerRequest): Promise<void>;
  prefetchResponsiveBanner(request: { id: string; width: number; height: number }): Promise<{ id: string; banner: BannerRequest; renderOptions: Record<string, unknown> }>;
  requestResponsiveBanner(id: string): Promise<void>;
  renderPrefetchedBanner(request: { id: string; banner: BannerRequest; renderOptions: Record<string, unknown> }): Promise<void>;
  clearBanner(id: string): void;
  clearAllBanners(): void;
  requestOverlayBanners(banners: OverlayBannerRequest[], callback?: (id: string, event: string, value?: string) => void): void;
  activeBannersCount: number;
}

export interface CrazyGamesGame {
  link: string;
  id: string;
  settings: GameSettings;
  isInstantJoin: boolean;
  isInstantMultiplayer: boolean;
  inviteParams: Record<string, string> | null;
  happytime(): void;
  gameplayStart(): void;
  gameplayStop(): void;
  loadingStart(): void;
  loadingStop(): void;
  inviteLink(params: Record<string, string>): string;
  showInviteButton(params: Record<string, string>): string;
  hideInviteButton(): void;
  getInviteParam(key: string): string | null;
  addSettingsChangeListener(listener: (settings: GameSettings) => void): void;
  removeSettingsChangeListener(listener: (settings: GameSettings) => void): void;
  addJoinRoomListener(listener: (inviteParams: Record<string, string>) => void): void;
  removeJoinRoomListener(listener: (inviteParams: Record<string, string>) => void): void;
  /** Runtime-only permissive signature. */
  updateRoom(...args: any[]): any;
  /** Runtime-only permissive signature. */
  leftRoom(...args: any[]): any;
}

/** Experimental runtime-only surface from sdk/game-v2. */
export interface CrazyGamesGameV2 {
  updateRoom(options: { roomId: string; isJoinable?: boolean; inviteParams?: Record<string, string> | null }): void;
  leftRoom(): void;
}

export interface CrazyGamesUser {
  isUserAccountAvailable: boolean;
  systemInfo: SystemInfo;
  showAuthPrompt(): Promise<User | null>;
  showAccountLinkPrompt(): Promise<AccountLinkResponse>;
  getUser(): Promise<User | null>;
  addAuthListener(listener: (user: User | null) => void): void;
  removeAuthListener(listener: (user: User | null) => void): void;
  getUserToken(): Promise<string>;
  getXsollaUserToken(): Promise<string>;
  listFriends(options: FriendsListOptions): Promise<FriendsPage>;
  addScore(score: number): void;
  addScoreEncrypted(score: number, encryptedScore: string): void;
  submitScore(payload: { encryptedScore: string }): void;
}

export interface CrazyGamesData {
  clear(): void;
  getItem(key: string): string | null;
  removeItem(key: string): void;
  setItem(key: string, value: string | number | boolean | null): void;
  syncUnityGameData(): void;
}

export interface CrazyGamesAnalytics {
  trackOrder(provider: PaymentProvider, order: Record<string, unknown>): void;
}

export interface CrazyGamesSdk {
  init(): Promise<void>;
  ad: CrazyGamesAd;
  banner: CrazyGamesBanner;
  game: CrazyGamesGame;
  /** Experimental runtime-only surface from sdk/game-v2. */
  "game-v2"?: CrazyGamesGameV2;
  user: CrazyGamesUser;
  data: CrazyGamesData;
  analytics: CrazyGamesAnalytics;
  environment: Environment;
  isQaTool: boolean;
}

export interface CrazyGamesGlobal {
  SDK: CrazyGamesSdk;
}

declare global {
  interface Window {
    CrazyGames: CrazyGamesGlobal;
  }
  const CrazyGames: CrazyGamesGlobal;
}

export {};
