// GENERATED FILE - DO NOT EDIT.
// Source: @discord/embedded-app-sdk@2.4.0
// Flattened declarations for parser/emitter compatibility.

// ===== output/Constants.d.ts =====
export declare enum RPCCloseCodes {
    CLOSE_NORMAL = 1000,
    CLOSE_UNSUPPORTED = 1003,
    CLOSE_ABNORMAL = 1006,
    INVALID_CLIENTID = 4000,
    INVALID_ORIGIN = 4001,
    RATELIMITED = 4002,
    TOKEN_REVOKED = 4003,
    INVALID_VERSION = 4004,
    INVALID_ENCODING = 4005
}
export declare enum RPCErrorCodes {
    INVALID_PAYLOAD = 4000,
    INVALID_COMMAND = 4002,
    INVALID_GUILD = 4003,
    INVALID_EVENT = 4004,
    INVALID_CHANNEL = 4005,
    INVALID_PERMISSIONS = 4006,
    INVALID_CLIENTID = 4007,
    INVALID_ORIGIN = 4008,
    INVALID_TOKEN = 4009,
    INVALID_USER = 4010
}
/**
 * @deprecated use OrientationTypeObject instead
 */
export declare enum Orientation {
    LANDSCAPE = "landscape",
    PORTRAIT = "portrait"
}
export declare enum Platform {
    MOBILE = "mobile",
    DESKTOP = "desktop"
}
/** See https://discord.com/developers/docs/topics/permissions#permissions-bitwise-permission-flags for more Permissions details */
export declare const Permissions: Readonly<{
    CREATE_INSTANT_INVITE: import("./utils/BigFlagUtils").BigFlag;
    KICK_MEMBERS: import("./utils/BigFlagUtils").BigFlag;
    BAN_MEMBERS: import("./utils/BigFlagUtils").BigFlag;
    ADMINISTRATOR: import("./utils/BigFlagUtils").BigFlag;
    MANAGE_CHANNELS: import("./utils/BigFlagUtils").BigFlag;
    MANAGE_GUILD: import("./utils/BigFlagUtils").BigFlag;
    ADD_REACTIONS: import("./utils/BigFlagUtils").BigFlag;
    VIEW_AUDIT_LOG: import("./utils/BigFlagUtils").BigFlag;
    PRIORITY_SPEAKER: import("./utils/BigFlagUtils").BigFlag;
    STREAM: import("./utils/BigFlagUtils").BigFlag;
    VIEW_CHANNEL: import("./utils/BigFlagUtils").BigFlag;
    SEND_MESSAGES: import("./utils/BigFlagUtils").BigFlag;
    SEND_TTS_MESSAGES: import("./utils/BigFlagUtils").BigFlag;
    MANAGE_MESSAGES: import("./utils/BigFlagUtils").BigFlag;
    EMBED_LINKS: import("./utils/BigFlagUtils").BigFlag;
    ATTACH_FILES: import("./utils/BigFlagUtils").BigFlag;
    READ_MESSAGE_HISTORY: import("./utils/BigFlagUtils").BigFlag;
    MENTION_EVERYONE: import("./utils/BigFlagUtils").BigFlag;
    USE_EXTERNAL_EMOJIS: import("./utils/BigFlagUtils").BigFlag;
    VIEW_GUILD_INSIGHTS: import("./utils/BigFlagUtils").BigFlag;
    CONNECT: import("./utils/BigFlagUtils").BigFlag;
    SPEAK: import("./utils/BigFlagUtils").BigFlag;
    MUTE_MEMBERS: import("./utils/BigFlagUtils").BigFlag;
    DEAFEN_MEMBERS: import("./utils/BigFlagUtils").BigFlag;
    MOVE_MEMBERS: import("./utils/BigFlagUtils").BigFlag;
    USE_VAD: import("./utils/BigFlagUtils").BigFlag;
    CHANGE_NICKNAME: import("./utils/BigFlagUtils").BigFlag;
    MANAGE_NICKNAMES: import("./utils/BigFlagUtils").BigFlag;
    MANAGE_ROLES: import("./utils/BigFlagUtils").BigFlag;
    MANAGE_WEBHOOKS: import("./utils/BigFlagUtils").BigFlag;
    MANAGE_GUILD_EXPRESSIONS: import("./utils/BigFlagUtils").BigFlag;
    USE_APPLICATION_COMMANDS: import("./utils/BigFlagUtils").BigFlag;
    REQUEST_TO_SPEAK: import("./utils/BigFlagUtils").BigFlag;
    MANAGE_EVENTS: import("./utils/BigFlagUtils").BigFlag;
    MANAGE_THREADS: import("./utils/BigFlagUtils").BigFlag;
    CREATE_PUBLIC_THREADS: import("./utils/BigFlagUtils").BigFlag;
    CREATE_PRIVATE_THREADS: import("./utils/BigFlagUtils").BigFlag;
    USE_EXTERNAL_STICKERS: import("./utils/BigFlagUtils").BigFlag;
    SEND_MESSAGES_IN_THREADS: import("./utils/BigFlagUtils").BigFlag;
    USE_EMBEDDED_ACTIVITIES: import("./utils/BigFlagUtils").BigFlag;
    MODERATE_MEMBERS: import("./utils/BigFlagUtils").BigFlag;
    VIEW_CREATOR_MONETIZATION_ANALYTICS: import("./utils/BigFlagUtils").BigFlag;
    USE_SOUNDBOARD: import("./utils/BigFlagUtils").BigFlag;
    CREATE_GUILD_EXPRESSIONS: import("./utils/BigFlagUtils").BigFlag;
    CREATE_EVENTS: import("./utils/BigFlagUtils").BigFlag;
    USE_EXTERNAL_SOUNDS: import("./utils/BigFlagUtils").BigFlag;
    SEND_VOICE_MESSAGES: import("./utils/BigFlagUtils").BigFlag;
    SEND_POLLS: import("./utils/BigFlagUtils").BigFlag;
    USE_EXTERNAL_APPS: import("./utils/BigFlagUtils").BigFlag;
}>;
export declare const UNKNOWN_VERSION_NUMBER = -1;
export declare const HANDSHAKE_SDK_VERSION_MINIMUM_MOBILE_VERSION = 250;

// ===== output/Discord.d.ts =====
export declare enum Opcodes {
    HANDSHAKE = 0,
    FRAME = 1,
    CLOSE = 2,
    HELLO = 3
}
export declare class DiscordSDK implements IDiscordSDK {
    readonly clientId: string;
    readonly instanceId: string;
    readonly customId: string | null;
    readonly referrerId: string | null;
    readonly platform: Platform;
    readonly guildId: string | null;
    readonly channelId: string | null;
    readonly locationId: string | null;
    readonly sdkVersion: string;
    readonly mobileAppVersion: string | null;
    readonly configuration: SdkConfiguration;
    readonly source: Window | WindowProxy | null;
    readonly sourceOrigin: string;
    private frameId;
    private eventBus;
    private isReady;
    private pendingCommands;
    private getTransfer;
    private sendCommand;
    commands: {
        authorize: (args: import("./commands/authorize").AuthorizeInput) => Promise<{
            code: string;
        }>;
        captureLog: (args: import("./commands/captureLog").CaptureLogInput) => Promise<{} | null>;
        encourageHardwareAcceleration: (args: void) => Promise<{
            enabled: boolean;
        }>;
        getChannel: (args: import("./commands/getChannel").GetChannelInput) => Promise<{
            type: 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1;
            id: string;
            voice_states: {
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                };
                nick: string;
                mute: boolean;
                voice_state: {
                    deaf: boolean;
                    mute: boolean;
                    self_mute: boolean;
                    self_deaf: boolean;
                    suppress: boolean;
                };
                volume: number;
            }[];
            messages: {
                type: number;
                id: string;
                content: string;
                timestamp: string;
                channel_id: string;
                tts: boolean;
                mention_everyone: boolean;
                mentions: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                }[];
                mention_roles: string[];
                mention_channels: {
                    type: number;
                    id: string;
                    name: string;
                    guild_id: string;
                }[];
                attachments: {
                    id: string;
                    url: string;
                    size: number;
                    filename: string;
                    proxy_url: string;
                    height?: number | null | undefined;
                    width?: number | null | undefined;
                }[];
                embeds: {
                    type?: string | null | undefined;
                    description?: string | null | undefined;
                    url?: string | null | undefined;
                    color?: number | null | undefined;
                    title?: string | null | undefined;
                    timestamp?: string | null | undefined;
                    footer?: {
                        text: string;
                        icon_url?: string | null | undefined;
                        proxy_icon_url?: string | null | undefined;
                    } | null | undefined;
                    image?: {
                        height?: number | null | undefined;
                        url?: string | null | undefined;
                        width?: number | null | undefined;
                        proxy_url?: string | null | undefined;
                    } | null | undefined;
                    thumbnail?: {
                        height?: number | null | undefined;
                        url?: string | null | undefined;
                        width?: number | null | undefined;
                        proxy_url?: string | null | undefined;
                    } | null | undefined;
                    video?: {
                        height?: number | null | undefined;
                        url?: string | null | undefined;
                        width?: number | null | undefined;
                    } | null | undefined;
                    provider?: {
                        name?: string | null | undefined;
                        url?: string | null | undefined;
                    } | null | undefined;
                    author?: {
                        name?: string | null | undefined;
                        url?: string | null | undefined;
                        icon_url?: string | null | undefined;
                        proxy_icon_url?: string | null | undefined;
                    } | null | undefined;
                    fields?: {
                        value: string;
                        name: string;
                        inline: boolean;
                    }[] | null | undefined;
                }[];
                pinned: boolean;
                application?: {
                    id: string;
                    description: string;
                    name: string;
                    icon?: string | null | undefined;
                    cover_image?: string | null | undefined;
                } | null | undefined;
                flags?: number | null | undefined;
                activity?: {
                    type: number;
                    party_id?: string | null | undefined;
                } | null | undefined;
                nonce?: string | number | null | undefined;
                guild_id?: string | null | undefined;
                author?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                member?: {
                    user: {
                        username: string;
                        discriminator: string;
                        id: string;
                        bot: boolean;
                        avatar_decoration_data: {
                            asset: string;
                            sku_id?: string | undefined;
                        } | null;
                        avatar?: string | null | undefined;
                        global_name?: string | null | undefined;
                        flags?: number | null | undefined;
                        premium_type?: number | null | undefined;
                    };
                    roles: string[];
                    joined_at: string;
                    deaf: boolean;
                    mute: boolean;
                    nick?: string | null | undefined;
                } | null | undefined;
                edited_timestamp?: string | null | undefined;
                reactions?: {
                    emoji: {
                        id: string;
                        user?: {
                            username: string;
                            discriminator: string;
                            id: string;
                            bot: boolean;
                            avatar_decoration_data: {
                                asset: string;
                                sku_id?: string | undefined;
                            } | null;
                            avatar?: string | null | undefined;
                            global_name?: string | null | undefined;
                            flags?: number | null | undefined;
                            premium_type?: number | null | undefined;
                        } | null | undefined;
                        name?: string | null | undefined;
                        animated?: boolean | null | undefined;
                        roles?: string[] | null | undefined;
                        require_colons?: boolean | null | undefined;
                        managed?: boolean | null | undefined;
                        available?: boolean | null | undefined;
                    };
                    count: number;
                    me: boolean;
                }[] | null | undefined;
                webhook_id?: string | null | undefined;
                message_reference?: {
                    guild_id?: string | null | undefined;
                    message_id?: string | null | undefined;
                    channel_id?: string | null | undefined;
                } | null | undefined;
                stickers?: unknown[] | null | undefined;
                referenced_message?: unknown;
            }[];
            name?: string | null | undefined;
            guild_id?: string | null | undefined;
            position?: number | null | undefined;
            topic?: string | null | undefined;
            bitrate?: number | null | undefined;
            user_limit?: number | null | undefined;
        }>;
        getChannelPermissions: (args: void) => Promise<{
            permissions: string | bigint;
        }>;
        getEntitlements: (args: void) => Promise<{
            entitlements: {
                type: 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1;
                id: string;
                application_id: string;
                user_id: string;
                sku_id: string;
                gift_code_flags: number;
                parent_id?: string | null | undefined;
                gifter_user_id?: string | null | undefined;
                branches?: string[] | null | undefined;
                starts_at?: string | null | undefined;
                ends_at?: string | null | undefined;
                consumed?: boolean | null | undefined;
                deleted?: boolean | null | undefined;
                gift_code_batch_id?: string | null | undefined;
            }[];
        }>;
        getPlatformBehaviors: (args: void) => Promise<{
            iosKeyboardResizesView?: boolean | undefined;
        }>;
        getSkus: (args: void) => Promise<{
            skus: {
                type: 1 | 4 | 2 | 3 | 5 | -1;
                id: string;
                name: string;
                flags: number;
                application_id: string;
                price: {
                    amount: number;
                    currency: string;
                };
                release_date: string | null;
            }[];
        }>;
        openExternalLink: (args: import("./commands/openExternalLink").OpenExternalLinkInput) => Promise<{
            opened: boolean | null;
        }>;
        openInviteDialog: (args: void) => Promise<{} | null>;
        setActivity: (args: import("./commands/setActivity").SetActivityInput) => Promise<{
            type: number;
            name: string;
            flags?: number | null | undefined;
            url?: string | null | undefined;
            application_id?: string | null | undefined;
            state?: string | null | undefined;
            state_url?: string | null | undefined;
            details?: string | null | undefined;
            details_url?: string | null | undefined;
            emoji?: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            } | null | undefined;
            assets?: {
                large_image?: string | null | undefined;
                large_text?: string | null | undefined;
                large_url?: string | null | undefined;
                small_image?: string | null | undefined;
                small_text?: string | null | undefined;
                small_url?: string | null | undefined;
            } | null | undefined;
            timestamps?: {
                start?: number | undefined;
                end?: number | undefined;
            } | null | undefined;
            party?: {
                id?: string | null | undefined;
                size?: number[] | null | undefined;
            } | null | undefined;
            secrets?: {
                join?: string | undefined;
                match?: string | undefined;
            } | null | undefined;
            created_at?: number | null | undefined;
            instance?: boolean | null | undefined;
        }>;
        setConfig: (args: import("./commands/setConfig").SetConfigInput) => Promise<{
            use_interactive_pip: boolean;
        }>;
        setOrientationLockState: (args: import("./commands/setOrientationLockState").SetOrientationLockStateInput) => Promise<{} | null>;
        startPurchase: (args: import("./commands/startPurchase").StartPurchaseInput) => Promise<{
            type: 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1;
            id: string;
            application_id: string;
            user_id: string;
            sku_id: string;
            gift_code_flags: number;
            parent_id?: string | null | undefined;
            gifter_user_id?: string | null | undefined;
            branches?: string[] | null | undefined;
            starts_at?: string | null | undefined;
            ends_at?: string | null | undefined;
            consumed?: boolean | null | undefined;
            deleted?: boolean | null | undefined;
            gift_code_batch_id?: string | null | undefined;
        }[] | null>;
        userSettingsGetLocale: (args: void) => Promise<{
            locale: string;
        }>;
        getInstanceConnectedParticipants: (args: void) => Promise<{
            participants: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                flags: number;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                avatar_decoration_data?: {
                    asset: string;
                    skuId?: string | undefined;
                    expiresAt?: number | undefined;
                } | null | undefined;
                premium_type?: number | null | undefined;
                nickname?: string | undefined;
            }[];
        }>;
        authenticate: (args: {
            access_token?: string | null | undefined;
        }) => Promise<{
            access_token: string;
            user: {
                username: string;
                discriminator: string;
                id: string;
                public_flags: number;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
            };
            scopes: (-1 | "identify" | "email" | "connections" | "guilds" | "guilds.join" | "guilds.members.read" | "guilds.channels.read" | "gdm.join" | "bot" | "rpc" | "rpc.notifications.read" | "rpc.voice.read" | "rpc.voice.write" | "rpc.video.read" | "rpc.video.write" | "rpc.screenshare.read" | "rpc.screenshare.write" | "rpc.activities.write" | "webhook.incoming" | "messages.read" | "applications.builds.upload" | "applications.builds.read" | "applications.commands" | "applications.commands.permissions.update" | "applications.commands.update" | "applications.store.update" | "applications.entitlements" | "activities.read" | "activities.write" | "activities.invites.write" | "relationships.read" | "relationships.write" | "voice" | "dm_channels.read" | "role_connections.write" | "presences.read" | "presences.write" | "openid" | "dm_channels.messages.read" | "dm_channels.messages.write" | "gateway.connect" | "account.global_name.update" | "payment_sources.country_code" | "sdk.social_layer_presence" | "sdk.social_layer" | "lobbies.write" | "application_identities.write")[];
            expires: string;
            application: {
                id: string;
                description: string;
                name: string;
                icon?: string | null | undefined;
                rpc_origins?: string[] | undefined;
            };
        }>;
        getActivityInstanceConnectedParticipants: (args: void) => Promise<{
            participants: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                flags: number;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                avatar_decoration_data?: {
                    asset: string;
                    skuId?: string | undefined;
                    expiresAt?: number | undefined;
                } | null | undefined;
                premium_type?: number | null | undefined;
                nickname?: string | undefined;
            }[];
        }>;
        getQuestEnrollmentStatus: (args: {
            quest_id: string;
        }) => Promise<{
            quest_id: string;
            is_enrolled: boolean;
            enrolled_at?: string | null | undefined;
        }>;
        getRelationships: (args: void) => Promise<{
            relationships: {
                type: number;
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                };
                presence?: {
                    status: string;
                    activity?: {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    } | null | undefined;
                } | undefined;
            }[];
        }>;
        getUser: (args: {
            id: string;
        }) => Promise<{
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            flags: number;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            avatar_decoration_data?: {
                asset: string;
                skuId?: string | undefined;
                expiresAt?: number | undefined;
            } | null | undefined;
            premium_type?: number | null | undefined;
        } | null>;
        initiateImageUpload: (args: void) => Promise<{
            image_url: string;
        }>;
        inviteUserEmbedded: (args: {
            user_id: string;
            content?: string | undefined;
        }) => Promise<{} | null | undefined>;
        openShareMomentDialog: (args: {
            mediaUrl: string;
        }) => Promise<{} | null | undefined>;
        questStartTimer: (args: {
            quest_id: string;
        }) => Promise<{
            success: boolean;
        }>;
        shareInteraction: (args: {
            command: string;
            options?: {
                value: string;
                name: string;
            }[] | undefined;
            content?: string | undefined;
            require_launch_channel?: boolean | undefined;
            preview_image?: {
                height: number;
                url: string;
                width: number;
            } | undefined;
            components?: {
                type: 1;
                components?: {
                    type: 2;
                    style: number;
                    label?: string | undefined;
                    custom_id?: string | undefined;
                }[] | undefined;
            }[] | undefined;
            pid?: number | undefined;
        }) => Promise<{
            success: boolean;
        }>;
        shareLink: (args: {
            message: string;
            custom_id?: string | undefined;
            link_id?: string | undefined;
        }) => Promise<{
            success: boolean;
            didCopyLink: boolean;
            didSendMessage: boolean;
        }>;
    };
    constructor(clientId: string, configuration?: SdkConfiguration);
    close(code: RPCCloseCodes, message: string): void;
    subscribe<K extends keyof typeof EventSchema>(event: K, listener: (event: zod.infer<(typeof EventSchema)[K]['payload']>['data']) => unknown, ...rest: MaybeZodObjectArray<(typeof EventSchema)[K]>): Promise<EventEmitter<string | symbol, any>>;
    unsubscribe<K extends keyof typeof EventSchema>(event: K, listener: (event: zod.infer<(typeof EventSchema)[K]['payload']>['data']) => unknown, ...rest: MaybeZodObjectArray<(typeof EventSchema)[K]>): Promise<EventEmitter<string | symbol, any>>;
    ready(): Promise<void>;
    private parseMajorMobileVersion;
    private handshake;
    private addOnReadyListener;
    private overrideConsoleLogging;
    /**
     * WARNING - All "console" logs are emitted as messages to the Discord client
     *  If you write "console.log" anywhere in handleMessage or subsequent message handling
     * there is a good chance you will cause an infinite loop where you receive a message
     * which causes "console.log" which sends a message, which causes the discord client to
     * send a reply which causes handleMessage to fire again, and again to inifinity
     *
     * If you need to log within handleMessage, consider setting
     * config.disableConsoleLogOverride to true when initializing the SDK
     */
    private handleMessage;
    private handleClose;
    private handleHandshake;
    private handleFrame;
    _getSearch(): string;
}

// ===== output/commands/authenticate.d.ts =====
/**
 * Authenticate Activity
 */
export declare const authenticate: (sendCommand: import("../schema/types").TSendCommand) => (args: {
    access_token?: string | null | undefined;
}) => Promise<{
    access_token: string;
    user: {
        username: string;
        discriminator: string;
        id: string;
        public_flags: number;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
    };
    scopes: (-1 | "identify" | "email" | "connections" | "guilds" | "guilds.join" | "guilds.members.read" | "guilds.channels.read" | "gdm.join" | "bot" | "rpc" | "rpc.notifications.read" | "rpc.voice.read" | "rpc.voice.write" | "rpc.video.read" | "rpc.video.write" | "rpc.screenshare.read" | "rpc.screenshare.write" | "rpc.activities.write" | "webhook.incoming" | "messages.read" | "applications.builds.upload" | "applications.builds.read" | "applications.commands" | "applications.commands.permissions.update" | "applications.commands.update" | "applications.store.update" | "applications.entitlements" | "activities.read" | "activities.write" | "activities.invites.write" | "relationships.read" | "relationships.write" | "voice" | "dm_channels.read" | "role_connections.write" | "presences.read" | "presences.write" | "openid" | "dm_channels.messages.read" | "dm_channels.messages.write" | "gateway.connect" | "account.global_name.update" | "payment_sources.country_code" | "sdk.social_layer_presence" | "sdk.social_layer" | "lobbies.write" | "application_identities.write")[];
    expires: string;
    application: {
        id: string;
        description: string;
        name: string;
        icon?: string | null | undefined;
        rpc_origins?: string[] | undefined;
    };
}>;

// ===== output/commands/authorize.d.ts =====
export interface AuthorizeInput {
    client_id: string;
    scope: OAuthScopes[];
    response_type?: 'code';
    code_challenge?: string;
    state?: string;
    prompt?: 'none';
    code_challenge_method?: 'S256';
}
/**
 * Should be called directly after a `ready` payload is received from the
 * Discord client. It includes a list of all scopes that your activity would
 * like to be authorized to use. If the user does not yet have a valid token
 * for all scopes requested, this command will open an OAuth modal. Once an
 * authorized token is available, it will be returned in the command response.
 */
export declare const authorize: (sendCommand: TSendCommand) => (args: AuthorizeInput) => Promise<{
    code: string;
}>;

// ===== output/commands/captureLog.d.ts =====
export interface CaptureLogInput {
    level: ConsoleLevel;
    message: string;
}
/**
 *
 */
export declare const captureLog: (sendCommand: TSendCommand) => (args: CaptureLogInput) => Promise<{} | null>;

// ===== output/commands/encourageHardwareAcceleration.d.ts =====
/**
 *
 */
export declare const encourageHardwareAcceleration: (sendCommand: TSendCommand) => (args: void) => Promise<{
    enabled: boolean;
}>;

// ===== output/commands/getActivityInstanceConnectedParticipants.d.ts =====
export declare const getActivityInstanceConnectedParticipants: (sendCommand: import("../schema/types").TSendCommand) => (args: void) => Promise<{
    participants: {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        flags: number;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        avatar_decoration_data?: {
            asset: string;
            skuId?: string | undefined;
            expiresAt?: number | undefined;
        } | null | undefined;
        premium_type?: number | null | undefined;
        nickname?: string | undefined;
    }[];
}>;

// ===== output/commands/getChannel.d.ts =====
export interface GetChannelInput {
    channel_id: string;
}
/**
 *
 * @description
 * RPC documentation here: https://discord.com/developers/docs/topics/rpc#getchannel
 * Calling getChannel gets info about the requested channel such as the channel name.
 *
 * Supported Platforms
 * | Web | iOS | Android |
 * |-----|-----|---------|
 * | ✅  | ✅  | ✅      |
 *
 * Required scopes:
 * - [guilds] for guild channels
 * - [guilds, dm_channels.read] for GDM channels. dm_channels.read requires approval from Discord.
 *
 * @example
 * await discordSdk.commands.getActivity({
 *   channel_id: discordSdk.channelId,
 * });
 */
export declare const getChannel: (sendCommand: TSendCommand) => (args: GetChannelInput) => Promise<{
    type: 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1;
    id: string;
    voice_states: {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        nick: string;
        mute: boolean;
        voice_state: {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        };
        volume: number;
    }[];
    messages: {
        type: number;
        id: string;
        content: string;
        timestamp: string;
        channel_id: string;
        tts: boolean;
        mention_everyone: boolean;
        mentions: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[];
        mention_roles: string[];
        mention_channels: {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }[];
        attachments: {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }[];
        embeds: {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }[];
        pinned: boolean;
        application?: {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        } | null | undefined;
        flags?: number | null | undefined;
        activity?: {
            type: number;
            party_id?: string | null | undefined;
        } | null | undefined;
        nonce?: string | number | null | undefined;
        guild_id?: string | null | undefined;
        author?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        member?: {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        } | null | undefined;
        edited_timestamp?: string | null | undefined;
        reactions?: {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }[] | null | undefined;
        webhook_id?: string | null | undefined;
        message_reference?: {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        } | null | undefined;
        stickers?: unknown[] | null | undefined;
        referenced_message?: unknown;
    }[];
    name?: string | null | undefined;
    guild_id?: string | null | undefined;
    position?: number | null | undefined;
    topic?: string | null | undefined;
    bitrate?: number | null | undefined;
    user_limit?: number | null | undefined;
}>;

// ===== output/commands/getChannelPermissions.d.ts =====
/**
 * Returns a bigint representing Permissions for the current user in the currently connected channel. Use PermissionsUtils to calculate if a user has a particular permission.
 * Always returns `0n` (no valid permissions) in a (G)DM context, so is unnecessary to call when discordSdk.guildId == null.
 */
export declare const getChannelPermissions: (sendCommand: TSendCommand) => (args: void) => Promise<{
    permissions: string | bigint;
}>;

// ===== output/commands/getEntitlements.d.ts =====
/**
 *
 */
export declare const getEntitlements: (sendCommand: TSendCommand) => (args: void) => Promise<{
    entitlements: {
        type: 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1;
        id: string;
        application_id: string;
        user_id: string;
        sku_id: string;
        gift_code_flags: number;
        parent_id?: string | null | undefined;
        gifter_user_id?: string | null | undefined;
        branches?: string[] | null | undefined;
        starts_at?: string | null | undefined;
        ends_at?: string | null | undefined;
        consumed?: boolean | null | undefined;
        deleted?: boolean | null | undefined;
        gift_code_batch_id?: string | null | undefined;
    }[];
}>;

// ===== output/commands/getPlatformBehaviors.d.ts =====
/**
 * Returns an object with information about platform behaviors
 * This command can be utilized to inform and react to a breaking change in platform behavior
 *
 * @returns {GetPlatformBehaviorsPayload} payload - The command return value
 * @returns {boolean} payload.data.iosKeyboardResizesView - If on iOS the webview is resized when the keyboard is opened
 */
export declare const getPlatformBehaviors: (sendCommand: TSendCommand) => (args: void) => Promise<{
    iosKeyboardResizesView?: boolean | undefined;
}>;

// ===== output/commands/getQuestEnrollmentStatus.d.ts =====
export declare const getQuestEnrollmentStatus: (sendCommand: import("../schema/types").TSendCommand) => (args: {
    quest_id: string;
}) => Promise<{
    quest_id: string;
    is_enrolled: boolean;
    enrolled_at?: string | null | undefined;
}>;

// ===== output/commands/getRelationships.d.ts =====
export declare const getRelationships: (sendCommand: import("../schema/types").TSendCommand) => (args: void) => Promise<{
    relationships: {
        type: number;
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            flags: number;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            avatar_decoration_data?: {
                asset: string;
                skuId?: string | undefined;
                expiresAt?: number | undefined;
            } | null | undefined;
            premium_type?: number | null | undefined;
        };
        presence?: {
            status: string;
            activity?: {
                name: string;
                type?: number | undefined;
                flags?: number | undefined;
                url?: string | null | undefined;
                session_id?: string | undefined;
                application_id?: string | undefined;
                status_display_type?: number | undefined;
                state?: string | undefined;
                state_url?: string | undefined;
                details?: string | undefined;
                details_url?: string | undefined;
                emoji?: {
                    name: string;
                    id?: string | null | undefined;
                    animated?: boolean | null | undefined;
                } | null | undefined;
                assets?: {
                    large_image?: string | undefined;
                    large_text?: string | undefined;
                    large_url?: string | undefined;
                    small_image?: string | undefined;
                    small_text?: string | undefined;
                    small_url?: string | undefined;
                } | undefined;
                timestamps?: {
                    start?: number | undefined;
                    end?: number | undefined;
                } | undefined;
                party?: {
                    id?: string | undefined;
                    size?: number[] | undefined;
                    privacy?: number | undefined;
                } | undefined;
                secrets?: {
                    join?: string | undefined;
                    match?: string | undefined;
                } | undefined;
                sync_id?: string | undefined;
                created_at?: number | undefined;
                instance?: boolean | undefined;
                metadata?: {} | undefined;
                platform?: string | undefined;
                supported_platforms?: string[] | undefined;
                buttons?: string[] | undefined;
                hangStatus?: string | undefined;
            } | null | undefined;
        } | undefined;
    }[];
}>;

// ===== output/commands/getSkus.d.ts =====
export declare const getSkus: (sendCommand: TSendCommand) => (args: void) => Promise<{
    skus: {
        type: 1 | 4 | 2 | 3 | 5 | -1;
        id: string;
        name: string;
        flags: number;
        application_id: string;
        price: {
            amount: number;
            currency: string;
        };
        release_date: string | null;
    }[];
}>;

// ===== output/commands/getUser.d.ts =====
export declare const getUser: (sendCommand: import("../schema/types").TSendCommand) => (args: {
    id: string;
}) => Promise<{
    username: string;
    discriminator: string;
    id: string;
    bot: boolean;
    flags: number;
    avatar?: string | null | undefined;
    global_name?: string | null | undefined;
    avatar_decoration_data?: {
        asset: string;
        skuId?: string | undefined;
        expiresAt?: number | undefined;
    } | null | undefined;
    premium_type?: number | null | undefined;
} | null>;

// ===== output/commands/index.d.ts =====
$1export declare function commands(sendCommand: TSendCommand): {
    authorize: (args: import("./authorize").AuthorizeInput) => Promise<{
        code: string;
    }>;
    captureLog: (args: import("./captureLog").CaptureLogInput) => Promise<{} | null>;
    encourageHardwareAcceleration: (args: void) => Promise<{
        enabled: boolean;
    }>;
    getChannel: (args: import("./getChannel").GetChannelInput) => Promise<{
        type: 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1;
        id: string;
        voice_states: {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            nick: string;
            mute: boolean;
            voice_state: {
                deaf: boolean;
                mute: boolean;
                self_mute: boolean;
                self_deaf: boolean;
                suppress: boolean;
            };
            volume: number;
        }[];
        messages: {
            type: number;
            id: string;
            content: string;
            timestamp: string;
            channel_id: string;
            tts: boolean;
            mention_everyone: boolean;
            mentions: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            }[];
            mention_roles: string[];
            mention_channels: {
                type: number;
                id: string;
                name: string;
                guild_id: string;
            }[];
            attachments: {
                id: string;
                url: string;
                size: number;
                filename: string;
                proxy_url: string;
                height?: number | null | undefined;
                width?: number | null | undefined;
            }[];
            embeds: {
                type?: string | null | undefined;
                description?: string | null | undefined;
                url?: string | null | undefined;
                color?: number | null | undefined;
                title?: string | null | undefined;
                timestamp?: string | null | undefined;
                footer?: {
                    text: string;
                    icon_url?: string | null | undefined;
                    proxy_icon_url?: string | null | undefined;
                } | null | undefined;
                image?: {
                    height?: number | null | undefined;
                    url?: string | null | undefined;
                    width?: number | null | undefined;
                    proxy_url?: string | null | undefined;
                } | null | undefined;
                thumbnail?: {
                    height?: number | null | undefined;
                    url?: string | null | undefined;
                    width?: number | null | undefined;
                    proxy_url?: string | null | undefined;
                } | null | undefined;
                video?: {
                    height?: number | null | undefined;
                    url?: string | null | undefined;
                    width?: number | null | undefined;
                } | null | undefined;
                provider?: {
                    name?: string | null | undefined;
                    url?: string | null | undefined;
                } | null | undefined;
                author?: {
                    name?: string | null | undefined;
                    url?: string | null | undefined;
                    icon_url?: string | null | undefined;
                    proxy_icon_url?: string | null | undefined;
                } | null | undefined;
                fields?: {
                    value: string;
                    name: string;
                    inline: boolean;
                }[] | null | undefined;
            }[];
            pinned: boolean;
            application?: {
                id: string;
                description: string;
                name: string;
                icon?: string | null | undefined;
                cover_image?: string | null | undefined;
            } | null | undefined;
            flags?: number | null | undefined;
            activity?: {
                type: number;
                party_id?: string | null | undefined;
            } | null | undefined;
            nonce?: string | number | null | undefined;
            guild_id?: string | null | undefined;
            author?: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            } | null | undefined;
            member?: {
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                };
                roles: string[];
                joined_at: string;
                deaf: boolean;
                mute: boolean;
                nick?: string | null | undefined;
            } | null | undefined;
            edited_timestamp?: string | null | undefined;
            reactions?: {
                emoji: {
                    id: string;
                    user?: {
                        username: string;
                        discriminator: string;
                        id: string;
                        bot: boolean;
                        avatar_decoration_data: {
                            asset: string;
                            sku_id?: string | undefined;
                        } | null;
                        avatar?: string | null | undefined;
                        global_name?: string | null | undefined;
                        flags?: number | null | undefined;
                        premium_type?: number | null | undefined;
                    } | null | undefined;
                    name?: string | null | undefined;
                    animated?: boolean | null | undefined;
                    roles?: string[] | null | undefined;
                    require_colons?: boolean | null | undefined;
                    managed?: boolean | null | undefined;
                    available?: boolean | null | undefined;
                };
                count: number;
                me: boolean;
            }[] | null | undefined;
            webhook_id?: string | null | undefined;
            message_reference?: {
                guild_id?: string | null | undefined;
                message_id?: string | null | undefined;
                channel_id?: string | null | undefined;
            } | null | undefined;
            stickers?: unknown[] | null | undefined;
            referenced_message?: unknown;
        }[];
        name?: string | null | undefined;
        guild_id?: string | null | undefined;
        position?: number | null | undefined;
        topic?: string | null | undefined;
        bitrate?: number | null | undefined;
        user_limit?: number | null | undefined;
    }>;
    getChannelPermissions: (args: void) => Promise<{
        permissions: string | bigint;
    }>;
    getEntitlements: (args: void) => Promise<{
        entitlements: {
            type: 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1;
            id: string;
            application_id: string;
            user_id: string;
            sku_id: string;
            gift_code_flags: number;
            parent_id?: string | null | undefined;
            gifter_user_id?: string | null | undefined;
            branches?: string[] | null | undefined;
            starts_at?: string | null | undefined;
            ends_at?: string | null | undefined;
            consumed?: boolean | null | undefined;
            deleted?: boolean | null | undefined;
            gift_code_batch_id?: string | null | undefined;
        }[];
    }>;
    getPlatformBehaviors: (args: void) => Promise<{
        iosKeyboardResizesView?: boolean | undefined;
    }>;
    getSkus: (args: void) => Promise<{
        skus: {
            type: 1 | 4 | 2 | 3 | 5 | -1;
            id: string;
            name: string;
            flags: number;
            application_id: string;
            price: {
                amount: number;
                currency: string;
            };
            release_date: string | null;
        }[];
    }>;
    openExternalLink: (args: import("./openExternalLink").OpenExternalLinkInput) => Promise<{
        opened: boolean | null;
    }>;
    openInviteDialog: (args: void) => Promise<{} | null>;
    setActivity: (args: import("./setActivity").SetActivityInput) => Promise<{
        type: number;
        name: string;
        flags?: number | null | undefined;
        url?: string | null | undefined;
        application_id?: string | null | undefined;
        state?: string | null | undefined;
        state_url?: string | null | undefined;
        details?: string | null | undefined;
        details_url?: string | null | undefined;
        emoji?: {
            id: string;
            user?: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            } | null | undefined;
            name?: string | null | undefined;
            animated?: boolean | null | undefined;
            roles?: string[] | null | undefined;
            require_colons?: boolean | null | undefined;
            managed?: boolean | null | undefined;
            available?: boolean | null | undefined;
        } | null | undefined;
        assets?: {
            large_image?: string | null | undefined;
            large_text?: string | null | undefined;
            large_url?: string | null | undefined;
            small_image?: string | null | undefined;
            small_text?: string | null | undefined;
            small_url?: string | null | undefined;
        } | null | undefined;
        timestamps?: {
            start?: number | undefined;
            end?: number | undefined;
        } | null | undefined;
        party?: {
            id?: string | null | undefined;
            size?: number[] | null | undefined;
        } | null | undefined;
        secrets?: {
            join?: string | undefined;
            match?: string | undefined;
        } | null | undefined;
        created_at?: number | null | undefined;
        instance?: boolean | null | undefined;
    }>;
    setConfig: (args: import("./setConfig").SetConfigInput) => Promise<{
        use_interactive_pip: boolean;
    }>;
    setOrientationLockState: (args: import("./setOrientationLockState").SetOrientationLockStateInput) => Promise<{} | null>;
    startPurchase: (args: import("./startPurchase").StartPurchaseInput) => Promise<{
        type: 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1;
        id: string;
        application_id: string;
        user_id: string;
        sku_id: string;
        gift_code_flags: number;
        parent_id?: string | null | undefined;
        gifter_user_id?: string | null | undefined;
        branches?: string[] | null | undefined;
        starts_at?: string | null | undefined;
        ends_at?: string | null | undefined;
        consumed?: boolean | null | undefined;
        deleted?: boolean | null | undefined;
        gift_code_batch_id?: string | null | undefined;
    }[] | null>;
    userSettingsGetLocale: (args: void) => Promise<{
        locale: string;
    }>;
    getInstanceConnectedParticipants: (args: void) => Promise<{
        participants: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            flags: number;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            avatar_decoration_data?: {
                asset: string;
                skuId?: string | undefined;
                expiresAt?: number | undefined;
            } | null | undefined;
            premium_type?: number | null | undefined;
            nickname?: string | undefined;
        }[];
    }>;
    authenticate: (args: {
        access_token?: string | null | undefined;
    }) => Promise<{
        access_token: string;
        user: {
            username: string;
            discriminator: string;
            id: string;
            public_flags: number;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
        };
        scopes: (-1 | "identify" | "email" | "connections" | "guilds" | "guilds.join" | "guilds.members.read" | "guilds.channels.read" | "gdm.join" | "bot" | "rpc" | "rpc.notifications.read" | "rpc.voice.read" | "rpc.voice.write" | "rpc.video.read" | "rpc.video.write" | "rpc.screenshare.read" | "rpc.screenshare.write" | "rpc.activities.write" | "webhook.incoming" | "messages.read" | "applications.builds.upload" | "applications.builds.read" | "applications.commands" | "applications.commands.permissions.update" | "applications.commands.update" | "applications.store.update" | "applications.entitlements" | "activities.read" | "activities.write" | "activities.invites.write" | "relationships.read" | "relationships.write" | "voice" | "dm_channels.read" | "role_connections.write" | "presences.read" | "presences.write" | "openid" | "dm_channels.messages.read" | "dm_channels.messages.write" | "gateway.connect" | "account.global_name.update" | "payment_sources.country_code" | "sdk.social_layer_presence" | "sdk.social_layer" | "lobbies.write" | "application_identities.write")[];
        expires: string;
        application: {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            rpc_origins?: string[] | undefined;
        };
    }>;
    getActivityInstanceConnectedParticipants: (args: void) => Promise<{
        participants: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            flags: number;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            avatar_decoration_data?: {
                asset: string;
                skuId?: string | undefined;
                expiresAt?: number | undefined;
            } | null | undefined;
            premium_type?: number | null | undefined;
            nickname?: string | undefined;
        }[];
    }>;
    getQuestEnrollmentStatus: (args: {
        quest_id: string;
    }) => Promise<{
        quest_id: string;
        is_enrolled: boolean;
        enrolled_at?: string | null | undefined;
    }>;
    getRelationships: (args: void) => Promise<{
        relationships: {
            type: number;
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                flags: number;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                avatar_decoration_data?: {
                    asset: string;
                    skuId?: string | undefined;
                    expiresAt?: number | undefined;
                } | null | undefined;
                premium_type?: number | null | undefined;
            };
            presence?: {
                status: string;
                activity?: {
                    name: string;
                    type?: number | undefined;
                    flags?: number | undefined;
                    url?: string | null | undefined;
                    session_id?: string | undefined;
                    application_id?: string | undefined;
                    status_display_type?: number | undefined;
                    state?: string | undefined;
                    state_url?: string | undefined;
                    details?: string | undefined;
                    details_url?: string | undefined;
                    emoji?: {
                        name: string;
                        id?: string | null | undefined;
                        animated?: boolean | null | undefined;
                    } | null | undefined;
                    assets?: {
                        large_image?: string | undefined;
                        large_text?: string | undefined;
                        large_url?: string | undefined;
                        small_image?: string | undefined;
                        small_text?: string | undefined;
                        small_url?: string | undefined;
                    } | undefined;
                    timestamps?: {
                        start?: number | undefined;
                        end?: number | undefined;
                    } | undefined;
                    party?: {
                        id?: string | undefined;
                        size?: number[] | undefined;
                        privacy?: number | undefined;
                    } | undefined;
                    secrets?: {
                        join?: string | undefined;
                        match?: string | undefined;
                    } | undefined;
                    sync_id?: string | undefined;
                    created_at?: number | undefined;
                    instance?: boolean | undefined;
                    metadata?: {} | undefined;
                    platform?: string | undefined;
                    supported_platforms?: string[] | undefined;
                    buttons?: string[] | undefined;
                    hangStatus?: string | undefined;
                } | null | undefined;
            } | undefined;
        }[];
    }>;
    getUser: (args: {
        id: string;
    }) => Promise<{
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        flags: number;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        avatar_decoration_data?: {
            asset: string;
            skuId?: string | undefined;
            expiresAt?: number | undefined;
        } | null | undefined;
        premium_type?: number | null | undefined;
    } | null>;
    initiateImageUpload: (args: void) => Promise<{
        image_url: string;
    }>;
    inviteUserEmbedded: (args: {
        user_id: string;
        content?: string | undefined;
    }) => Promise<{} | null | undefined>;
    openShareMomentDialog: (args: {
        mediaUrl: string;
    }) => Promise<{} | null | undefined>;
    questStartTimer: (args: {
        quest_id: string;
    }) => Promise<{
        success: boolean;
    }>;
    shareInteraction: (args: {
        command: string;
        options?: {
            value: string;
            name: string;
        }[] | undefined;
        content?: string | undefined;
        require_launch_channel?: boolean | undefined;
        preview_image?: {
            height: number;
            url: string;
            width: number;
        } | undefined;
        components?: {
            type: 1;
            components?: {
                type: 2;
                style: number;
                label?: string | undefined;
                custom_id?: string | undefined;
            }[] | undefined;
        }[] | undefined;
        pid?: number | undefined;
    }) => Promise<{
        success: boolean;
    }>;
    shareLink: (args: {
        message: string;
        custom_id?: string | undefined;
        link_id?: string | undefined;
    }) => Promise<{
        success: boolean;
        didCopyLink: boolean;
        didSendMessage: boolean;
    }>;
};
export commands;
type Awaited<T> = T extends Promise<infer U> ? U : never;
export type CommandTypes = ReturnType<typeof commands>;
export type CommandResponseTypes = {
    [Name in keyof CommandTypes]: Awaited<ReturnType<CommandTypes[Name]>>;
};
export type CommandResponse<K extends keyof CommandTypes> = Awaited<ReturnType<CommandTypes[K]>>;
export type CommandInputTypes = {
    [Name in keyof CommandTypes]: Parameters<CommandTypes[Name]>;
};
export type CommandInput<K extends keyof CommandTypes> = Parameters<CommandTypes[K]>;

// ===== output/commands/initiateImageUpload.d.ts =====
/**
 * Triggers the file upload flow in the Discord app. The user will be prompted to select a valid image file
 * and then it will be uploaded on the app side to the Discord CDN.
 *
 * NOTE: The URL provided by the API is an ephemeral attachment URL, so the image will not be permanently
 * accessible at the link provided.
 *
 * @returns {Promise<{image_url: string}>}
 */
export declare const initiateImageUpload: (sendCommand: import("../schema/types").TSendCommand) => (args: void) => Promise<{
    image_url: string;
}>;

// ===== output/commands/inviteUserEmbedded.d.ts =====
export declare const inviteUserEmbedded: (sendCommand: import("../schema/types").TSendCommand) => (args: {
    user_id: string;
    content?: string | undefined;
}) => Promise<{} | null | undefined>;

// ===== output/commands/openExternalLink.d.ts =====
export interface OpenExternalLinkInput {
    url: string;
}
/**
 *
 */
export declare const openExternalLink: (sendCommand: TSendCommand) => (args: OpenExternalLinkInput) => Promise<{
    opened: boolean | null;
}>;

// ===== output/commands/openInviteDialog.d.ts =====
/**
 * Opens the invite dialog within the discord client, allowing users to share invite links to friends.
 * Does not work in (G)DM contexts (throws RPCError.INVALID_CHANNEL), so should not be called if discordSdk.guildId == null
 * Similarly, if the user does not have Permissions.CREATE_INSTANT_INVITE this command throws RPCErrors.INVALID_PERMISSIONS, so checking the user's permissions via getChannelPermissions is highly recommended.
 */
export declare const openInviteDialog: (sendCommand: TSendCommand) => (args: void) => Promise<{} | null>;

// ===== output/commands/openShareMomentDialog.d.ts =====
/**
 * Opens the Share Moment Dialog in the user's client, allowing them to share the media at mediaUrl as a message.
 *
 * @param {string} mediaUrl - a Discord CDN URL for the piece of media to be shared.
 * @returns {Promise<void>}
 */
export declare const openShareMomentDialog: (sendCommand: import("../schema/types").TSendCommand) => (args: {
    mediaUrl: string;
}) => Promise<{} | null | undefined>;

// ===== output/commands/questStartTimer.d.ts =====
export declare const questStartTimer: (sendCommand: import("../schema/types").TSendCommand) => (args: {
    quest_id: string;
}) => Promise<{
    success: boolean;
}>;

// ===== output/commands/setActivity.d.ts =====
export declare const SetActivity: zod.ZodNullable<zod.ZodObject<zod.objectUtil.extendShape<Pick<{
    name: zod.ZodString;
    type: zod.ZodNumber;
    url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    created_at: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    timestamps: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        start: zod.ZodOptional<zod.ZodNumber>;
        end: zod.ZodOptional<zod.ZodNumber>;
    }, "strip", zod.ZodTypeAny, {
        start?: number | undefined;
        end?: number | undefined;
    }, {
        start?: number | undefined;
        end?: number | undefined;
    }>>>;
    application_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    details: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    details_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    state: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    state_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    emoji: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        id: zod.ZodString;
        name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        roles: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>>;
        user: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>>>;
        require_colons: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        managed: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        animated: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        available: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    }, "strip", zod.ZodTypeAny, {
        id: string;
        user?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        name?: string | null | undefined;
        animated?: boolean | null | undefined;
        roles?: string[] | null | undefined;
        require_colons?: boolean | null | undefined;
        managed?: boolean | null | undefined;
        available?: boolean | null | undefined;
    }, {
        id: string;
        user?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        name?: string | null | undefined;
        animated?: boolean | null | undefined;
        roles?: string[] | null | undefined;
        require_colons?: boolean | null | undefined;
        managed?: boolean | null | undefined;
        available?: boolean | null | undefined;
    }>>>;
    party: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        size: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodNumber, "many">>>;
    }, "strip", zod.ZodTypeAny, {
        id?: string | null | undefined;
        size?: number[] | null | undefined;
    }, {
        id?: string | null | undefined;
        size?: number[] | null | undefined;
    }>>>;
    assets: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        large_image: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
        large_text: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
        large_url: zod.ZodOptional<zod.ZodNullable<zod.ZodOptional<zod.ZodString>>>;
        small_image: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
        small_text: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
        small_url: zod.ZodOptional<zod.ZodNullable<zod.ZodOptional<zod.ZodString>>>;
    }, "strip", zod.ZodTypeAny, {
        large_image?: string | null | undefined;
        large_text?: string | null | undefined;
        large_url?: string | null | undefined;
        small_image?: string | null | undefined;
        small_text?: string | null | undefined;
        small_url?: string | null | undefined;
    }, {
        large_image?: string | null | undefined;
        large_text?: string | null | undefined;
        large_url?: string | null | undefined;
        small_image?: string | null | undefined;
        small_text?: string | null | undefined;
        small_url?: string | null | undefined;
    }>>>;
    secrets: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        join: zod.ZodOptional<zod.ZodString>;
        match: zod.ZodOptional<zod.ZodString>;
    }, "strip", zod.ZodTypeAny, {
        join?: string | undefined;
        match?: string | undefined;
    }, {
        join?: string | undefined;
        match?: string | undefined;
    }>>>;
    instance: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
}, "type" | "state" | "state_url" | "details" | "details_url" | "assets" | "timestamps" | "party" | "secrets" | "instance">, {
    type: zod.ZodOptional<zod.ZodNumber>;
    instance: zod.ZodOptional<zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>>;
}>, "strip", zod.ZodTypeAny, {
    type?: number | undefined;
    state?: string | null | undefined;
    state_url?: string | null | undefined;
    details?: string | null | undefined;
    details_url?: string | null | undefined;
    assets?: {
        large_image?: string | null | undefined;
        large_text?: string | null | undefined;
        large_url?: string | null | undefined;
        small_image?: string | null | undefined;
        small_text?: string | null | undefined;
        small_url?: string | null | undefined;
    } | null | undefined;
    timestamps?: {
        start?: number | undefined;
        end?: number | undefined;
    } | null | undefined;
    party?: {
        id?: string | null | undefined;
        size?: number[] | null | undefined;
    } | null | undefined;
    secrets?: {
        join?: string | undefined;
        match?: string | undefined;
    } | null | undefined;
    instance?: boolean | null | undefined;
}, {
    type?: number | undefined;
    state?: string | null | undefined;
    state_url?: string | null | undefined;
    details?: string | null | undefined;
    details_url?: string | null | undefined;
    assets?: {
        large_image?: string | null | undefined;
        large_text?: string | null | undefined;
        large_url?: string | null | undefined;
        small_image?: string | null | undefined;
        small_text?: string | null | undefined;
        small_url?: string | null | undefined;
    } | null | undefined;
    timestamps?: {
        start?: number | undefined;
        end?: number | undefined;
    } | null | undefined;
    party?: {
        id?: string | null | undefined;
        size?: number[] | null | undefined;
    } | null | undefined;
    secrets?: {
        join?: string | undefined;
        match?: string | undefined;
    } | null | undefined;
    instance?: boolean | null | undefined;
}>>;
export interface SetActivityInput {
    activity: zod.infer<typeof SetActivity>;
}
/**
 *
 * @description
 * RPC documentation here: https://discord.com/developers/docs/topics/rpc#setactivity
 * Calling setActivity allows modifying how your activity's rich presence is displayed in the Discord App
 *
 * Supported Platforms
 * | Web | iOS | Android |
 * |-----|-----|---------|
 * | ✅  | ✅  | ✅      |
 *
 * Required scopes: [rpc.activities.write]
 *
 * @example
 * await discordSdk.commands.setActivity({
 *   activity: {
 *     type: 0,
 *     details: 'Details',
 *     state: 'Playing',
 *   },
 * });
 */
export declare const setActivity: (sendCommand: TSendCommand) => (args: SetActivityInput) => Promise<{
    type: number;
    name: string;
    flags?: number | null | undefined;
    url?: string | null | undefined;
    application_id?: string | null | undefined;
    state?: string | null | undefined;
    state_url?: string | null | undefined;
    details?: string | null | undefined;
    details_url?: string | null | undefined;
    emoji?: {
        id: string;
        user?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        name?: string | null | undefined;
        animated?: boolean | null | undefined;
        roles?: string[] | null | undefined;
        require_colons?: boolean | null | undefined;
        managed?: boolean | null | undefined;
        available?: boolean | null | undefined;
    } | null | undefined;
    assets?: {
        large_image?: string | null | undefined;
        large_text?: string | null | undefined;
        large_url?: string | null | undefined;
        small_image?: string | null | undefined;
        small_text?: string | null | undefined;
        small_url?: string | null | undefined;
    } | null | undefined;
    timestamps?: {
        start?: number | undefined;
        end?: number | undefined;
    } | null | undefined;
    party?: {
        id?: string | null | undefined;
        size?: number[] | null | undefined;
    } | null | undefined;
    secrets?: {
        join?: string | undefined;
        match?: string | undefined;
    } | null | undefined;
    created_at?: number | null | undefined;
    instance?: boolean | null | undefined;
}>;

// ===== output/commands/setConfig.d.ts =====
export interface SetConfigInput {
    use_interactive_pip: boolean;
}
/**
 *
 */
export declare const setConfig: (sendCommand: TSendCommand) => (args: SetConfigInput) => Promise<{
    use_interactive_pip: boolean;
}>;

// ===== output/commands/setOrientationLockState.d.ts =====
export interface SetOrientationLockStateInputFallback {
    lock_state: zod.infer<typeof OrientationLockState>;
    picture_in_picture_lock_state?: zod.infer<typeof OrientationLockState> | null;
}
export interface SetOrientationLockStateInput extends SetOrientationLockStateInputFallback {
    grid_lock_state?: zod.infer<typeof OrientationLockState> | null;
}
export declare const setOrientationLockState: (sendCommand: TSendCommand) => (args: SetOrientationLockStateInput) => Promise<{} | null>;

// ===== output/commands/shareInteraction.d.ts =====
export declare const shareInteraction: (sendCommand: import("../schema/types").TSendCommand) => (args: {
    command: string;
    options?: {
        value: string;
        name: string;
    }[] | undefined;
    content?: string | undefined;
    require_launch_channel?: boolean | undefined;
    preview_image?: {
        height: number;
        url: string;
        width: number;
    } | undefined;
    components?: {
        type: 1;
        components?: {
            type: 2;
            style: number;
            label?: string | undefined;
            custom_id?: string | undefined;
        }[] | undefined;
    }[] | undefined;
    pid?: number | undefined;
}) => Promise<{
    success: boolean;
}>;

// ===== output/commands/shareLink.d.ts =====
/**
 * Opens a modal in the user's client to share the Activity link.
 *
 * @param {string} referrer_id
 * @param {string} custom_id
 * @param {string} message - message sent alongside link when shared.
 * @returns {Promise<{success: boolean>} whether or not the user shared the link to someone
 */
export declare const shareLink: (sendCommand: import("../schema/types").TSendCommand) => (args: {
    message: string;
    custom_id?: string | undefined;
    link_id?: string | undefined;
}) => Promise<{
    success: boolean;
    didCopyLink: boolean;
    didSendMessage: boolean;
}>;

// ===== output/commands/startPurchase.d.ts =====
export interface StartPurchaseInput {
    sku_id: string;
    pid?: number;
}
/**
 *
 */
export declare const startPurchase: (sendCommand: TSendCommand) => (args: StartPurchaseInput) => Promise<{
    type: 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1;
    id: string;
    application_id: string;
    user_id: string;
    sku_id: string;
    gift_code_flags: number;
    parent_id?: string | null | undefined;
    gifter_user_id?: string | null | undefined;
    branches?: string[] | null | undefined;
    starts_at?: string | null | undefined;
    ends_at?: string | null | undefined;
    consumed?: boolean | null | undefined;
    deleted?: boolean | null | undefined;
    gift_code_batch_id?: string | null | undefined;
}[] | null>;

// ===== output/commands/userSettingsGetLocale.d.ts =====
/**
 *
 */
export declare const userSettingsGetLocale: (sendCommand: TSendCommand) => (args: void) => Promise<{
    locale: string;
}>;

// ===== output/error.d.ts =====
export interface ISDKError {
    code: number;
    message: string;
}
export declare class SDKError extends Error implements ISDKError {
    code: number;
    message: string;
    name: string;
    constructor(code: number, message?: string);
}

// ===== output/generated/schemas.d.ts =====
/**
 * This file is generated.
 * Run "npm run sync" to regenerate file.
 * @generated
 */
export declare const InitiateImageUploadResponseSchema: z.ZodObject<{
    image_url: z.ZodString;
}, "strip", z.ZodTypeAny, {
    image_url: string;
}, {
    image_url: string;
}>;
export type InitiateImageUploadResponse = zInfer<typeof InitiateImageUploadResponseSchema>;
export declare const OpenShareMomentDialogRequestSchema: z.ZodObject<{
    mediaUrl: z.ZodString;
}, "strip", z.ZodTypeAny, {
    mediaUrl: string;
}, {
    mediaUrl: string;
}>;
export type OpenShareMomentDialogRequest = zInfer<typeof OpenShareMomentDialogRequestSchema>;
export declare const AuthenticateRequestSchema: z.ZodObject<{
    access_token: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
}, "strip", z.ZodTypeAny, {
    access_token?: string | null | undefined;
}, {
    access_token?: string | null | undefined;
}>;
export type AuthenticateRequest = zInfer<typeof AuthenticateRequestSchema>;
export declare const AuthenticateResponseSchema: z.ZodObject<{
    access_token: z.ZodString;
    user: z.ZodObject<{
        username: z.ZodString;
        discriminator: z.ZodString;
        id: z.ZodString;
        avatar: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
        public_flags: z.ZodNumber;
        global_name: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
    }, "strip", z.ZodTypeAny, {
        username: string;
        discriminator: string;
        id: string;
        public_flags: number;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
    }, {
        username: string;
        discriminator: string;
        id: string;
        public_flags: number;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
    }>;
    scopes: z.ZodArray<import("../utils/zodUtils").ZodEffectOverlayType<z.ZodDefault<z.ZodUnion<[z.ZodEnum<["identify", "email", "connections", "guilds", "guilds.join", "guilds.members.read", "guilds.channels.read", "gdm.join", "bot", "rpc", "rpc.notifications.read", "rpc.voice.read", "rpc.voice.write", "rpc.video.read", "rpc.video.write", "rpc.screenshare.read", "rpc.screenshare.write", "rpc.activities.write", "webhook.incoming", "messages.read", "applications.builds.upload", "applications.builds.read", "applications.commands", "applications.commands.permissions.update", "applications.commands.update", "applications.store.update", "applications.entitlements", "activities.read", "activities.write", "activities.invites.write", "relationships.read", "relationships.write", "voice", "dm_channels.read", "role_connections.write", "presences.read", "presences.write", "openid", "dm_channels.messages.read", "dm_channels.messages.write", "gateway.connect", "account.global_name.update", "payment_sources.country_code", "sdk.social_layer_presence", "sdk.social_layer", "lobbies.write", "application_identities.write"]>, z.ZodLiteral<-1>]>>>, "many">;
    expires: z.ZodString;
    application: z.ZodObject<{
        description: z.ZodString;
        icon: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
        id: z.ZodString;
        rpc_origins: z.ZodOptional<z.ZodArray<z.ZodString, "many">>;
        name: z.ZodString;
    }, "strip", z.ZodTypeAny, {
        id: string;
        description: string;
        name: string;
        icon?: string | null | undefined;
        rpc_origins?: string[] | undefined;
    }, {
        id: string;
        description: string;
        name: string;
        icon?: string | null | undefined;
        rpc_origins?: string[] | undefined;
    }>;
}, "strip", z.ZodTypeAny, {
    access_token: string;
    user: {
        username: string;
        discriminator: string;
        id: string;
        public_flags: number;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
    };
    scopes: (-1 | "identify" | "email" | "connections" | "guilds" | "guilds.join" | "guilds.members.read" | "guilds.channels.read" | "gdm.join" | "bot" | "rpc" | "rpc.notifications.read" | "rpc.voice.read" | "rpc.voice.write" | "rpc.video.read" | "rpc.video.write" | "rpc.screenshare.read" | "rpc.screenshare.write" | "rpc.activities.write" | "webhook.incoming" | "messages.read" | "applications.builds.upload" | "applications.builds.read" | "applications.commands" | "applications.commands.permissions.update" | "applications.commands.update" | "applications.store.update" | "applications.entitlements" | "activities.read" | "activities.write" | "activities.invites.write" | "relationships.read" | "relationships.write" | "voice" | "dm_channels.read" | "role_connections.write" | "presences.read" | "presences.write" | "openid" | "dm_channels.messages.read" | "dm_channels.messages.write" | "gateway.connect" | "account.global_name.update" | "payment_sources.country_code" | "sdk.social_layer_presence" | "sdk.social_layer" | "lobbies.write" | "application_identities.write")[];
    expires: string;
    application: {
        id: string;
        description: string;
        name: string;
        icon?: string | null | undefined;
        rpc_origins?: string[] | undefined;
    };
}, {
    access_token: string;
    user: {
        username: string;
        discriminator: string;
        id: string;
        public_flags: number;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
    };
    scopes: (-1 | "identify" | "email" | "connections" | "guilds" | "guilds.join" | "guilds.members.read" | "guilds.channels.read" | "gdm.join" | "bot" | "rpc" | "rpc.notifications.read" | "rpc.voice.read" | "rpc.voice.write" | "rpc.video.read" | "rpc.video.write" | "rpc.screenshare.read" | "rpc.screenshare.write" | "rpc.activities.write" | "webhook.incoming" | "messages.read" | "applications.builds.upload" | "applications.builds.read" | "applications.commands" | "applications.commands.permissions.update" | "applications.commands.update" | "applications.store.update" | "applications.entitlements" | "activities.read" | "activities.write" | "activities.invites.write" | "relationships.read" | "relationships.write" | "voice" | "dm_channels.read" | "role_connections.write" | "presences.read" | "presences.write" | "openid" | "dm_channels.messages.read" | "dm_channels.messages.write" | "gateway.connect" | "account.global_name.update" | "payment_sources.country_code" | "sdk.social_layer_presence" | "sdk.social_layer" | "lobbies.write" | "application_identities.write" | undefined)[];
    expires: string;
    application: {
        id: string;
        description: string;
        name: string;
        icon?: string | null | undefined;
        rpc_origins?: string[] | undefined;
    };
}>;
export type AuthenticateResponse = zInfer<typeof AuthenticateResponseSchema>;
export declare const GetActivityInstanceConnectedParticipantsResponseSchema: z.ZodObject<{
    participants: z.ZodArray<z.ZodObject<{
        id: z.ZodString;
        username: z.ZodString;
        global_name: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
        discriminator: z.ZodString;
        avatar: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
        flags: z.ZodNumber;
        bot: z.ZodBoolean;
        avatar_decoration_data: z.ZodOptional<z.ZodUnion<[z.ZodObject<{
            asset: z.ZodString;
            skuId: z.ZodOptional<z.ZodString>;
            expiresAt: z.ZodOptional<z.ZodNumber>;
        }, "strip", z.ZodTypeAny, {
            asset: string;
            skuId?: string | undefined;
            expiresAt?: number | undefined;
        }, {
            asset: string;
            skuId?: string | undefined;
            expiresAt?: number | undefined;
        }>, z.ZodNull]>>;
        premium_type: z.ZodOptional<z.ZodUnion<[z.ZodNumber, z.ZodNull]>>;
        nickname: z.ZodOptional<z.ZodString>;
    }, "strip", z.ZodTypeAny, {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        flags: number;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        avatar_decoration_data?: {
            asset: string;
            skuId?: string | undefined;
            expiresAt?: number | undefined;
        } | null | undefined;
        premium_type?: number | null | undefined;
        nickname?: string | undefined;
    }, {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        flags: number;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        avatar_decoration_data?: {
            asset: string;
            skuId?: string | undefined;
            expiresAt?: number | undefined;
        } | null | undefined;
        premium_type?: number | null | undefined;
        nickname?: string | undefined;
    }>, "many">;
}, "strip", z.ZodTypeAny, {
    participants: {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        flags: number;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        avatar_decoration_data?: {
            asset: string;
            skuId?: string | undefined;
            expiresAt?: number | undefined;
        } | null | undefined;
        premium_type?: number | null | undefined;
        nickname?: string | undefined;
    }[];
}, {
    participants: {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        flags: number;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        avatar_decoration_data?: {
            asset: string;
            skuId?: string | undefined;
            expiresAt?: number | undefined;
        } | null | undefined;
        premium_type?: number | null | undefined;
        nickname?: string | undefined;
    }[];
}>;
export type GetActivityInstanceConnectedParticipantsResponse = zInfer<typeof GetActivityInstanceConnectedParticipantsResponseSchema>;
export declare const ShareInteractionRequestSchema: z.ZodObject<{
    command: z.ZodString;
    options: z.ZodOptional<z.ZodArray<z.ZodObject<{
        name: z.ZodString;
        value: z.ZodString;
    }, "strip", z.ZodTypeAny, {
        value: string;
        name: string;
    }, {
        value: string;
        name: string;
    }>, "many">>;
    content: z.ZodOptional<z.ZodString>;
    require_launch_channel: z.ZodOptional<z.ZodBoolean>;
    preview_image: z.ZodOptional<z.ZodObject<{
        height: z.ZodNumber;
        url: z.ZodString;
        width: z.ZodNumber;
    }, "strip", z.ZodTypeAny, {
        height: number;
        url: string;
        width: number;
    }, {
        height: number;
        url: string;
        width: number;
    }>>;
    components: z.ZodOptional<z.ZodArray<z.ZodObject<{
        type: z.ZodLiteral<1>;
        components: z.ZodOptional<z.ZodArray<z.ZodObject<{
            type: z.ZodLiteral<2>;
            style: z.ZodNumber;
            label: z.ZodOptional<z.ZodString>;
            custom_id: z.ZodOptional<z.ZodString>;
        }, "strip", z.ZodTypeAny, {
            type: 2;
            style: number;
            label?: string | undefined;
            custom_id?: string | undefined;
        }, {
            type: 2;
            style: number;
            label?: string | undefined;
            custom_id?: string | undefined;
        }>, "many">>;
    }, "strip", z.ZodTypeAny, {
        type: 1;
        components?: {
            type: 2;
            style: number;
            label?: string | undefined;
            custom_id?: string | undefined;
        }[] | undefined;
    }, {
        type: 1;
        components?: {
            type: 2;
            style: number;
            label?: string | undefined;
            custom_id?: string | undefined;
        }[] | undefined;
    }>, "many">>;
    pid: z.ZodOptional<z.ZodNumber>;
}, "strip", z.ZodTypeAny, {
    command: string;
    options?: {
        value: string;
        name: string;
    }[] | undefined;
    content?: string | undefined;
    require_launch_channel?: boolean | undefined;
    preview_image?: {
        height: number;
        url: string;
        width: number;
    } | undefined;
    components?: {
        type: 1;
        components?: {
            type: 2;
            style: number;
            label?: string | undefined;
            custom_id?: string | undefined;
        }[] | undefined;
    }[] | undefined;
    pid?: number | undefined;
}, {
    command: string;
    options?: {
        value: string;
        name: string;
    }[] | undefined;
    content?: string | undefined;
    require_launch_channel?: boolean | undefined;
    preview_image?: {
        height: number;
        url: string;
        width: number;
    } | undefined;
    components?: {
        type: 1;
        components?: {
            type: 2;
            style: number;
            label?: string | undefined;
            custom_id?: string | undefined;
        }[] | undefined;
    }[] | undefined;
    pid?: number | undefined;
}>;
export type ShareInteractionRequest = zInfer<typeof ShareInteractionRequestSchema>;
export declare const ShareInteractionResponseSchema: z.ZodObject<{
    success: z.ZodBoolean;
}, "strip", z.ZodTypeAny, {
    success: boolean;
}, {
    success: boolean;
}>;
export type ShareInteractionResponse = zInfer<typeof ShareInteractionResponseSchema>;
export declare const ShareLinkRequestSchema: z.ZodObject<{
    custom_id: z.ZodOptional<z.ZodString>;
    message: z.ZodString;
    link_id: z.ZodOptional<z.ZodString>;
}, "strip", z.ZodTypeAny, {
    message: string;
    custom_id?: string | undefined;
    link_id?: string | undefined;
}, {
    message: string;
    custom_id?: string | undefined;
    link_id?: string | undefined;
}>;
export type ShareLinkRequest = zInfer<typeof ShareLinkRequestSchema>;
export declare const ShareLinkResponseSchema: z.ZodObject<{
    success: z.ZodBoolean;
    didCopyLink: z.ZodBoolean;
    didSendMessage: z.ZodBoolean;
}, "strip", z.ZodTypeAny, {
    success: boolean;
    didCopyLink: boolean;
    didSendMessage: boolean;
}, {
    success: boolean;
    didCopyLink: boolean;
    didSendMessage: boolean;
}>;
export type ShareLinkResponse = zInfer<typeof ShareLinkResponseSchema>;
export declare const GetRelationshipsResponseSchema: z.ZodObject<{
    relationships: z.ZodArray<z.ZodObject<{
        type: z.ZodNumber;
        user: z.ZodObject<{
            id: z.ZodString;
            username: z.ZodString;
            global_name: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
            discriminator: z.ZodString;
            avatar: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
            flags: z.ZodNumber;
            bot: z.ZodBoolean;
            avatar_decoration_data: z.ZodOptional<z.ZodUnion<[z.ZodObject<{
                asset: z.ZodString;
                skuId: z.ZodOptional<z.ZodString>;
                expiresAt: z.ZodOptional<z.ZodNumber>;
            }, "strip", z.ZodTypeAny, {
                asset: string;
                skuId?: string | undefined;
                expiresAt?: number | undefined;
            }, {
                asset: string;
                skuId?: string | undefined;
                expiresAt?: number | undefined;
            }>, z.ZodNull]>>;
            premium_type: z.ZodOptional<z.ZodUnion<[z.ZodNumber, z.ZodNull]>>;
        }, "strip", z.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            flags: number;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            avatar_decoration_data?: {
                asset: string;
                skuId?: string | undefined;
                expiresAt?: number | undefined;
            } | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            flags: number;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            avatar_decoration_data?: {
                asset: string;
                skuId?: string | undefined;
                expiresAt?: number | undefined;
            } | null | undefined;
            premium_type?: number | null | undefined;
        }>;
        presence: z.ZodOptional<z.ZodObject<{
            status: z.ZodString;
            activity: z.ZodOptional<z.ZodUnion<[z.ZodObject<{
                session_id: z.ZodOptional<z.ZodString>;
                type: z.ZodOptional<z.ZodNumber>;
                name: z.ZodString;
                url: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
                application_id: z.ZodOptional<z.ZodString>;
                status_display_type: z.ZodOptional<z.ZodNumber>;
                state: z.ZodOptional<z.ZodString>;
                state_url: z.ZodOptional<z.ZodString>;
                details: z.ZodOptional<z.ZodString>;
                details_url: z.ZodOptional<z.ZodString>;
                emoji: z.ZodOptional<z.ZodUnion<[z.ZodObject<{
                    name: z.ZodString;
                    id: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
                    animated: z.ZodOptional<z.ZodUnion<[z.ZodBoolean, z.ZodNull]>>;
                }, "strip", z.ZodTypeAny, {
                    name: string;
                    id?: string | null | undefined;
                    animated?: boolean | null | undefined;
                }, {
                    name: string;
                    id?: string | null | undefined;
                    animated?: boolean | null | undefined;
                }>, z.ZodNull]>>;
                assets: z.ZodOptional<z.ZodObject<{
                    large_image: z.ZodOptional<z.ZodString>;
                    large_text: z.ZodOptional<z.ZodString>;
                    large_url: z.ZodOptional<z.ZodString>;
                    small_image: z.ZodOptional<z.ZodString>;
                    small_text: z.ZodOptional<z.ZodString>;
                    small_url: z.ZodOptional<z.ZodString>;
                }, "strip", z.ZodTypeAny, {
                    large_image?: string | undefined;
                    large_text?: string | undefined;
                    large_url?: string | undefined;
                    small_image?: string | undefined;
                    small_text?: string | undefined;
                    small_url?: string | undefined;
                }, {
                    large_image?: string | undefined;
                    large_text?: string | undefined;
                    large_url?: string | undefined;
                    small_image?: string | undefined;
                    small_text?: string | undefined;
                    small_url?: string | undefined;
                }>>;
                timestamps: z.ZodOptional<z.ZodObject<{
                    start: z.ZodOptional<z.ZodNumber>;
                    end: z.ZodOptional<z.ZodNumber>;
                }, "strip", z.ZodTypeAny, {
                    start?: number | undefined;
                    end?: number | undefined;
                }, {
                    start?: number | undefined;
                    end?: number | undefined;
                }>>;
                party: z.ZodOptional<z.ZodObject<{
                    id: z.ZodOptional<z.ZodString>;
                    size: z.ZodOptional<z.ZodArray<z.ZodNumber, "many">>;
                    privacy: z.ZodOptional<z.ZodNumber>;
                }, "strip", z.ZodTypeAny, {
                    id?: string | undefined;
                    size?: number[] | undefined;
                    privacy?: number | undefined;
                }, {
                    id?: string | undefined;
                    size?: number[] | undefined;
                    privacy?: number | undefined;
                }>>;
                secrets: z.ZodOptional<z.ZodObject<{
                    match: z.ZodOptional<z.ZodString>;
                    join: z.ZodOptional<z.ZodString>;
                }, "strip", z.ZodTypeAny, {
                    join?: string | undefined;
                    match?: string | undefined;
                }, {
                    join?: string | undefined;
                    match?: string | undefined;
                }>>;
                sync_id: z.ZodOptional<z.ZodString>;
                created_at: z.ZodOptional<z.ZodNumber>;
                instance: z.ZodOptional<z.ZodBoolean>;
                flags: z.ZodOptional<z.ZodNumber>;
                metadata: z.ZodOptional<z.ZodObject<{}, "strip", z.ZodTypeAny, {}, {}>>;
                platform: z.ZodOptional<z.ZodString>;
                supported_platforms: z.ZodOptional<z.ZodArray<z.ZodString, "many">>;
                buttons: z.ZodOptional<z.ZodArray<z.ZodString, "many">>;
                hangStatus: z.ZodOptional<z.ZodString>;
            }, "strip", z.ZodTypeAny, {
                name: string;
                type?: number | undefined;
                flags?: number | undefined;
                url?: string | null | undefined;
                session_id?: string | undefined;
                application_id?: string | undefined;
                status_display_type?: number | undefined;
                state?: string | undefined;
                state_url?: string | undefined;
                details?: string | undefined;
                details_url?: string | undefined;
                emoji?: {
                    name: string;
                    id?: string | null | undefined;
                    animated?: boolean | null | undefined;
                } | null | undefined;
                assets?: {
                    large_image?: string | undefined;
                    large_text?: string | undefined;
                    large_url?: string | undefined;
                    small_image?: string | undefined;
                    small_text?: string | undefined;
                    small_url?: string | undefined;
                } | undefined;
                timestamps?: {
                    start?: number | undefined;
                    end?: number | undefined;
                } | undefined;
                party?: {
                    id?: string | undefined;
                    size?: number[] | undefined;
                    privacy?: number | undefined;
                } | undefined;
                secrets?: {
                    join?: string | undefined;
                    match?: string | undefined;
                } | undefined;
                sync_id?: string | undefined;
                created_at?: number | undefined;
                instance?: boolean | undefined;
                metadata?: {} | undefined;
                platform?: string | undefined;
                supported_platforms?: string[] | undefined;
                buttons?: string[] | undefined;
                hangStatus?: string | undefined;
            }, {
                name: string;
                type?: number | undefined;
                flags?: number | undefined;
                url?: string | null | undefined;
                session_id?: string | undefined;
                application_id?: string | undefined;
                status_display_type?: number | undefined;
                state?: string | undefined;
                state_url?: string | undefined;
                details?: string | undefined;
                details_url?: string | undefined;
                emoji?: {
                    name: string;
                    id?: string | null | undefined;
                    animated?: boolean | null | undefined;
                } | null | undefined;
                assets?: {
                    large_image?: string | undefined;
                    large_text?: string | undefined;
                    large_url?: string | undefined;
                    small_image?: string | undefined;
                    small_text?: string | undefined;
                    small_url?: string | undefined;
                } | undefined;
                timestamps?: {
                    start?: number | undefined;
                    end?: number | undefined;
                } | undefined;
                party?: {
                    id?: string | undefined;
                    size?: number[] | undefined;
                    privacy?: number | undefined;
                } | undefined;
                secrets?: {
                    join?: string | undefined;
                    match?: string | undefined;
                } | undefined;
                sync_id?: string | undefined;
                created_at?: number | undefined;
                instance?: boolean | undefined;
                metadata?: {} | undefined;
                platform?: string | undefined;
                supported_platforms?: string[] | undefined;
                buttons?: string[] | undefined;
                hangStatus?: string | undefined;
            }>, z.ZodNull]>>;
        }, "strip", z.ZodTypeAny, {
            status: string;
            activity?: {
                name: string;
                type?: number | undefined;
                flags?: number | undefined;
                url?: string | null | undefined;
                session_id?: string | undefined;
                application_id?: string | undefined;
                status_display_type?: number | undefined;
                state?: string | undefined;
                state_url?: string | undefined;
                details?: string | undefined;
                details_url?: string | undefined;
                emoji?: {
                    name: string;
                    id?: string | null | undefined;
                    animated?: boolean | null | undefined;
                } | null | undefined;
                assets?: {
                    large_image?: string | undefined;
                    large_text?: string | undefined;
                    large_url?: string | undefined;
                    small_image?: string | undefined;
                    small_text?: string | undefined;
                    small_url?: string | undefined;
                } | undefined;
                timestamps?: {
                    start?: number | undefined;
                    end?: number | undefined;
                } | undefined;
                party?: {
                    id?: string | undefined;
                    size?: number[] | undefined;
                    privacy?: number | undefined;
                } | undefined;
                secrets?: {
                    join?: string | undefined;
                    match?: string | undefined;
                } | undefined;
                sync_id?: string | undefined;
                created_at?: number | undefined;
                instance?: boolean | undefined;
                metadata?: {} | undefined;
                platform?: string | undefined;
                supported_platforms?: string[] | undefined;
                buttons?: string[] | undefined;
                hangStatus?: string | undefined;
            } | null | undefined;
        }, {
            status: string;
            activity?: {
                name: string;
                type?: number | undefined;
                flags?: number | undefined;
                url?: string | null | undefined;
                session_id?: string | undefined;
                application_id?: string | undefined;
                status_display_type?: number | undefined;
                state?: string | undefined;
                state_url?: string | undefined;
                details?: string | undefined;
                details_url?: string | undefined;
                emoji?: {
                    name: string;
                    id?: string | null | undefined;
                    animated?: boolean | null | undefined;
                } | null | undefined;
                assets?: {
                    large_image?: string | undefined;
                    large_text?: string | undefined;
                    large_url?: string | undefined;
                    small_image?: string | undefined;
                    small_text?: string | undefined;
                    small_url?: string | undefined;
                } | undefined;
                timestamps?: {
                    start?: number | undefined;
                    end?: number | undefined;
                } | undefined;
                party?: {
                    id?: string | undefined;
                    size?: number[] | undefined;
                    privacy?: number | undefined;
                } | undefined;
                secrets?: {
                    join?: string | undefined;
                    match?: string | undefined;
                } | undefined;
                sync_id?: string | undefined;
                created_at?: number | undefined;
                instance?: boolean | undefined;
                metadata?: {} | undefined;
                platform?: string | undefined;
                supported_platforms?: string[] | undefined;
                buttons?: string[] | undefined;
                hangStatus?: string | undefined;
            } | null | undefined;
        }>>;
    }, "strip", z.ZodTypeAny, {
        type: number;
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            flags: number;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            avatar_decoration_data?: {
                asset: string;
                skuId?: string | undefined;
                expiresAt?: number | undefined;
            } | null | undefined;
            premium_type?: number | null | undefined;
        };
        presence?: {
            status: string;
            activity?: {
                name: string;
                type?: number | undefined;
                flags?: number | undefined;
                url?: string | null | undefined;
                session_id?: string | undefined;
                application_id?: string | undefined;
                status_display_type?: number | undefined;
                state?: string | undefined;
                state_url?: string | undefined;
                details?: string | undefined;
                details_url?: string | undefined;
                emoji?: {
                    name: string;
                    id?: string | null | undefined;
                    animated?: boolean | null | undefined;
                } | null | undefined;
                assets?: {
                    large_image?: string | undefined;
                    large_text?: string | undefined;
                    large_url?: string | undefined;
                    small_image?: string | undefined;
                    small_text?: string | undefined;
                    small_url?: string | undefined;
                } | undefined;
                timestamps?: {
                    start?: number | undefined;
                    end?: number | undefined;
                } | undefined;
                party?: {
                    id?: string | undefined;
                    size?: number[] | undefined;
                    privacy?: number | undefined;
                } | undefined;
                secrets?: {
                    join?: string | undefined;
                    match?: string | undefined;
                } | undefined;
                sync_id?: string | undefined;
                created_at?: number | undefined;
                instance?: boolean | undefined;
                metadata?: {} | undefined;
                platform?: string | undefined;
                supported_platforms?: string[] | undefined;
                buttons?: string[] | undefined;
                hangStatus?: string | undefined;
            } | null | undefined;
        } | undefined;
    }, {
        type: number;
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            flags: number;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            avatar_decoration_data?: {
                asset: string;
                skuId?: string | undefined;
                expiresAt?: number | undefined;
            } | null | undefined;
            premium_type?: number | null | undefined;
        };
        presence?: {
            status: string;
            activity?: {
                name: string;
                type?: number | undefined;
                flags?: number | undefined;
                url?: string | null | undefined;
                session_id?: string | undefined;
                application_id?: string | undefined;
                status_display_type?: number | undefined;
                state?: string | undefined;
                state_url?: string | undefined;
                details?: string | undefined;
                details_url?: string | undefined;
                emoji?: {
                    name: string;
                    id?: string | null | undefined;
                    animated?: boolean | null | undefined;
                } | null | undefined;
                assets?: {
                    large_image?: string | undefined;
                    large_text?: string | undefined;
                    large_url?: string | undefined;
                    small_image?: string | undefined;
                    small_text?: string | undefined;
                    small_url?: string | undefined;
                } | undefined;
                timestamps?: {
                    start?: number | undefined;
                    end?: number | undefined;
                } | undefined;
                party?: {
                    id?: string | undefined;
                    size?: number[] | undefined;
                    privacy?: number | undefined;
                } | undefined;
                secrets?: {
                    join?: string | undefined;
                    match?: string | undefined;
                } | undefined;
                sync_id?: string | undefined;
                created_at?: number | undefined;
                instance?: boolean | undefined;
                metadata?: {} | undefined;
                platform?: string | undefined;
                supported_platforms?: string[] | undefined;
                buttons?: string[] | undefined;
                hangStatus?: string | undefined;
            } | null | undefined;
        } | undefined;
    }>, "many">;
}, "strip", z.ZodTypeAny, {
    relationships: {
        type: number;
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            flags: number;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            avatar_decoration_data?: {
                asset: string;
                skuId?: string | undefined;
                expiresAt?: number | undefined;
            } | null | undefined;
            premium_type?: number | null | undefined;
        };
        presence?: {
            status: string;
            activity?: {
                name: string;
                type?: number | undefined;
                flags?: number | undefined;
                url?: string | null | undefined;
                session_id?: string | undefined;
                application_id?: string | undefined;
                status_display_type?: number | undefined;
                state?: string | undefined;
                state_url?: string | undefined;
                details?: string | undefined;
                details_url?: string | undefined;
                emoji?: {
                    name: string;
                    id?: string | null | undefined;
                    animated?: boolean | null | undefined;
                } | null | undefined;
                assets?: {
                    large_image?: string | undefined;
                    large_text?: string | undefined;
                    large_url?: string | undefined;
                    small_image?: string | undefined;
                    small_text?: string | undefined;
                    small_url?: string | undefined;
                } | undefined;
                timestamps?: {
                    start?: number | undefined;
                    end?: number | undefined;
                } | undefined;
                party?: {
                    id?: string | undefined;
                    size?: number[] | undefined;
                    privacy?: number | undefined;
                } | undefined;
                secrets?: {
                    join?: string | undefined;
                    match?: string | undefined;
                } | undefined;
                sync_id?: string | undefined;
                created_at?: number | undefined;
                instance?: boolean | undefined;
                metadata?: {} | undefined;
                platform?: string | undefined;
                supported_platforms?: string[] | undefined;
                buttons?: string[] | undefined;
                hangStatus?: string | undefined;
            } | null | undefined;
        } | undefined;
    }[];
}, {
    relationships: {
        type: number;
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            flags: number;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            avatar_decoration_data?: {
                asset: string;
                skuId?: string | undefined;
                expiresAt?: number | undefined;
            } | null | undefined;
            premium_type?: number | null | undefined;
        };
        presence?: {
            status: string;
            activity?: {
                name: string;
                type?: number | undefined;
                flags?: number | undefined;
                url?: string | null | undefined;
                session_id?: string | undefined;
                application_id?: string | undefined;
                status_display_type?: number | undefined;
                state?: string | undefined;
                state_url?: string | undefined;
                details?: string | undefined;
                details_url?: string | undefined;
                emoji?: {
                    name: string;
                    id?: string | null | undefined;
                    animated?: boolean | null | undefined;
                } | null | undefined;
                assets?: {
                    large_image?: string | undefined;
                    large_text?: string | undefined;
                    large_url?: string | undefined;
                    small_image?: string | undefined;
                    small_text?: string | undefined;
                    small_url?: string | undefined;
                } | undefined;
                timestamps?: {
                    start?: number | undefined;
                    end?: number | undefined;
                } | undefined;
                party?: {
                    id?: string | undefined;
                    size?: number[] | undefined;
                    privacy?: number | undefined;
                } | undefined;
                secrets?: {
                    join?: string | undefined;
                    match?: string | undefined;
                } | undefined;
                sync_id?: string | undefined;
                created_at?: number | undefined;
                instance?: boolean | undefined;
                metadata?: {} | undefined;
                platform?: string | undefined;
                supported_platforms?: string[] | undefined;
                buttons?: string[] | undefined;
                hangStatus?: string | undefined;
            } | null | undefined;
        } | undefined;
    }[];
}>;
export type GetRelationshipsResponse = zInfer<typeof GetRelationshipsResponseSchema>;
export declare const InviteUserEmbeddedRequestSchema: z.ZodObject<{
    user_id: z.ZodString;
    content: z.ZodOptional<z.ZodString>;
}, "strip", z.ZodTypeAny, {
    user_id: string;
    content?: string | undefined;
}, {
    user_id: string;
    content?: string | undefined;
}>;
export type InviteUserEmbeddedRequest = zInfer<typeof InviteUserEmbeddedRequestSchema>;
export declare const GetUserRequestSchema: z.ZodObject<{
    id: z.ZodString;
}, "strip", z.ZodTypeAny, {
    id: string;
}, {
    id: string;
}>;
export type GetUserRequest = zInfer<typeof GetUserRequestSchema>;
export declare const GetUserResponseSchema: z.ZodUnion<[z.ZodObject<{
    id: z.ZodString;
    username: z.ZodString;
    global_name: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
    discriminator: z.ZodString;
    avatar: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
    flags: z.ZodNumber;
    bot: z.ZodBoolean;
    avatar_decoration_data: z.ZodOptional<z.ZodUnion<[z.ZodObject<{
        asset: z.ZodString;
        skuId: z.ZodOptional<z.ZodString>;
        expiresAt: z.ZodOptional<z.ZodNumber>;
    }, "strip", z.ZodTypeAny, {
        asset: string;
        skuId?: string | undefined;
        expiresAt?: number | undefined;
    }, {
        asset: string;
        skuId?: string | undefined;
        expiresAt?: number | undefined;
    }>, z.ZodNull]>>;
    premium_type: z.ZodOptional<z.ZodUnion<[z.ZodNumber, z.ZodNull]>>;
}, "strip", z.ZodTypeAny, {
    username: string;
    discriminator: string;
    id: string;
    bot: boolean;
    flags: number;
    avatar?: string | null | undefined;
    global_name?: string | null | undefined;
    avatar_decoration_data?: {
        asset: string;
        skuId?: string | undefined;
        expiresAt?: number | undefined;
    } | null | undefined;
    premium_type?: number | null | undefined;
}, {
    username: string;
    discriminator: string;
    id: string;
    bot: boolean;
    flags: number;
    avatar?: string | null | undefined;
    global_name?: string | null | undefined;
    avatar_decoration_data?: {
        asset: string;
        skuId?: string | undefined;
        expiresAt?: number | undefined;
    } | null | undefined;
    premium_type?: number | null | undefined;
}>, z.ZodNull]>;
export type GetUserResponse = zInfer<typeof GetUserResponseSchema>;
export declare const GetQuestEnrollmentStatusRequestSchema: z.ZodObject<{
    quest_id: z.ZodString;
}, "strip", z.ZodTypeAny, {
    quest_id: string;
}, {
    quest_id: string;
}>;
export type GetQuestEnrollmentStatusRequest = zInfer<typeof GetQuestEnrollmentStatusRequestSchema>;
export declare const GetQuestEnrollmentStatusResponseSchema: z.ZodObject<{
    quest_id: z.ZodString;
    is_enrolled: z.ZodBoolean;
    enrolled_at: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
}, "strip", z.ZodTypeAny, {
    quest_id: string;
    is_enrolled: boolean;
    enrolled_at?: string | null | undefined;
}, {
    quest_id: string;
    is_enrolled: boolean;
    enrolled_at?: string | null | undefined;
}>;
export type GetQuestEnrollmentStatusResponse = zInfer<typeof GetQuestEnrollmentStatusResponseSchema>;
export declare const QuestStartTimerRequestSchema: z.ZodObject<{
    quest_id: z.ZodString;
}, "strip", z.ZodTypeAny, {
    quest_id: string;
}, {
    quest_id: string;
}>;
export type QuestStartTimerRequest = zInfer<typeof QuestStartTimerRequestSchema>;
export declare const QuestStartTimerResponseSchema: z.ZodObject<{
    success: z.ZodBoolean;
}, "strip", z.ZodTypeAny, {
    success: boolean;
}, {
    success: boolean;
}>;
export type QuestStartTimerResponse = zInfer<typeof QuestStartTimerResponseSchema>;
/**
 * RPC Commands which support schemas.
 */
export declare enum Command {
    INITIATE_IMAGE_UPLOAD = "INITIATE_IMAGE_UPLOAD",
    OPEN_SHARE_MOMENT_DIALOG = "OPEN_SHARE_MOMENT_DIALOG",
    AUTHENTICATE = "AUTHENTICATE",
    GET_ACTIVITY_INSTANCE_CONNECTED_PARTICIPANTS = "GET_ACTIVITY_INSTANCE_CONNECTED_PARTICIPANTS",
    SHARE_INTERACTION = "SHARE_INTERACTION",
    SHARE_LINK = "SHARE_LINK",
    GET_RELATIONSHIPS = "GET_RELATIONSHIPS",
    INVITE_USER_EMBEDDED = "INVITE_USER_EMBEDDED",
    GET_USER = "GET_USER",
    GET_QUEST_ENROLLMENT_STATUS = "GET_QUEST_ENROLLMENT_STATUS",
    QUEST_START_TIMER = "QUEST_START_TIMER"
}
/**
 * Request & Response schemas for each supported RPC Command.
 */
export declare const Schemas: {
    readonly INITIATE_IMAGE_UPLOAD: {
        readonly request: z.ZodVoid;
        readonly response: z.ZodObject<{
            image_url: z.ZodString;
        }, "strip", z.ZodTypeAny, {
            image_url: string;
        }, {
            image_url: string;
        }>;
    };
    readonly OPEN_SHARE_MOMENT_DIALOG: {
        readonly request: z.ZodObject<{
            mediaUrl: z.ZodString;
        }, "strip", z.ZodTypeAny, {
            mediaUrl: string;
        }, {
            mediaUrl: string;
        }>;
        readonly response: z.ZodNullable<z.ZodOptional<z.ZodObject<{}, "strip", z.ZodTypeAny, {}, {}>>>;
    };
    readonly AUTHENTICATE: {
        readonly request: z.ZodObject<{
            access_token: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
        }, "strip", z.ZodTypeAny, {
            access_token?: string | null | undefined;
        }, {
            access_token?: string | null | undefined;
        }>;
        readonly response: z.ZodObject<{
            access_token: z.ZodString;
            user: z.ZodObject<{
                username: z.ZodString;
                discriminator: z.ZodString;
                id: z.ZodString;
                avatar: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
                public_flags: z.ZodNumber;
                global_name: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
            }, "strip", z.ZodTypeAny, {
                username: string;
                discriminator: string;
                id: string;
                public_flags: number;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
            }, {
                username: string;
                discriminator: string;
                id: string;
                public_flags: number;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
            }>;
            scopes: z.ZodArray<import("../utils/zodUtils").ZodEffectOverlayType<z.ZodDefault<z.ZodUnion<[z.ZodEnum<["identify", "email", "connections", "guilds", "guilds.join", "guilds.members.read", "guilds.channels.read", "gdm.join", "bot", "rpc", "rpc.notifications.read", "rpc.voice.read", "rpc.voice.write", "rpc.video.read", "rpc.video.write", "rpc.screenshare.read", "rpc.screenshare.write", "rpc.activities.write", "webhook.incoming", "messages.read", "applications.builds.upload", "applications.builds.read", "applications.commands", "applications.commands.permissions.update", "applications.commands.update", "applications.store.update", "applications.entitlements", "activities.read", "activities.write", "activities.invites.write", "relationships.read", "relationships.write", "voice", "dm_channels.read", "role_connections.write", "presences.read", "presences.write", "openid", "dm_channels.messages.read", "dm_channels.messages.write", "gateway.connect", "account.global_name.update", "payment_sources.country_code", "sdk.social_layer_presence", "sdk.social_layer", "lobbies.write", "application_identities.write"]>, z.ZodLiteral<-1>]>>>, "many">;
            expires: z.ZodString;
            application: z.ZodObject<{
                description: z.ZodString;
                icon: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
                id: z.ZodString;
                rpc_origins: z.ZodOptional<z.ZodArray<z.ZodString, "many">>;
                name: z.ZodString;
            }, "strip", z.ZodTypeAny, {
                id: string;
                description: string;
                name: string;
                icon?: string | null | undefined;
                rpc_origins?: string[] | undefined;
            }, {
                id: string;
                description: string;
                name: string;
                icon?: string | null | undefined;
                rpc_origins?: string[] | undefined;
            }>;
        }, "strip", z.ZodTypeAny, {
            access_token: string;
            user: {
                username: string;
                discriminator: string;
                id: string;
                public_flags: number;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
            };
            scopes: (-1 | "identify" | "email" | "connections" | "guilds" | "guilds.join" | "guilds.members.read" | "guilds.channels.read" | "gdm.join" | "bot" | "rpc" | "rpc.notifications.read" | "rpc.voice.read" | "rpc.voice.write" | "rpc.video.read" | "rpc.video.write" | "rpc.screenshare.read" | "rpc.screenshare.write" | "rpc.activities.write" | "webhook.incoming" | "messages.read" | "applications.builds.upload" | "applications.builds.read" | "applications.commands" | "applications.commands.permissions.update" | "applications.commands.update" | "applications.store.update" | "applications.entitlements" | "activities.read" | "activities.write" | "activities.invites.write" | "relationships.read" | "relationships.write" | "voice" | "dm_channels.read" | "role_connections.write" | "presences.read" | "presences.write" | "openid" | "dm_channels.messages.read" | "dm_channels.messages.write" | "gateway.connect" | "account.global_name.update" | "payment_sources.country_code" | "sdk.social_layer_presence" | "sdk.social_layer" | "lobbies.write" | "application_identities.write")[];
            expires: string;
            application: {
                id: string;
                description: string;
                name: string;
                icon?: string | null | undefined;
                rpc_origins?: string[] | undefined;
            };
        }, {
            access_token: string;
            user: {
                username: string;
                discriminator: string;
                id: string;
                public_flags: number;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
            };
            scopes: (-1 | "identify" | "email" | "connections" | "guilds" | "guilds.join" | "guilds.members.read" | "guilds.channels.read" | "gdm.join" | "bot" | "rpc" | "rpc.notifications.read" | "rpc.voice.read" | "rpc.voice.write" | "rpc.video.read" | "rpc.video.write" | "rpc.screenshare.read" | "rpc.screenshare.write" | "rpc.activities.write" | "webhook.incoming" | "messages.read" | "applications.builds.upload" | "applications.builds.read" | "applications.commands" | "applications.commands.permissions.update" | "applications.commands.update" | "applications.store.update" | "applications.entitlements" | "activities.read" | "activities.write" | "activities.invites.write" | "relationships.read" | "relationships.write" | "voice" | "dm_channels.read" | "role_connections.write" | "presences.read" | "presences.write" | "openid" | "dm_channels.messages.read" | "dm_channels.messages.write" | "gateway.connect" | "account.global_name.update" | "payment_sources.country_code" | "sdk.social_layer_presence" | "sdk.social_layer" | "lobbies.write" | "application_identities.write" | undefined)[];
            expires: string;
            application: {
                id: string;
                description: string;
                name: string;
                icon?: string | null | undefined;
                rpc_origins?: string[] | undefined;
            };
        }>;
    };
    readonly GET_ACTIVITY_INSTANCE_CONNECTED_PARTICIPANTS: {
        readonly request: z.ZodVoid;
        readonly response: z.ZodObject<{
            participants: z.ZodArray<z.ZodObject<{
                id: z.ZodString;
                username: z.ZodString;
                global_name: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
                discriminator: z.ZodString;
                avatar: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
                flags: z.ZodNumber;
                bot: z.ZodBoolean;
                avatar_decoration_data: z.ZodOptional<z.ZodUnion<[z.ZodObject<{
                    asset: z.ZodString;
                    skuId: z.ZodOptional<z.ZodString>;
                    expiresAt: z.ZodOptional<z.ZodNumber>;
                }, "strip", z.ZodTypeAny, {
                    asset: string;
                    skuId?: string | undefined;
                    expiresAt?: number | undefined;
                }, {
                    asset: string;
                    skuId?: string | undefined;
                    expiresAt?: number | undefined;
                }>, z.ZodNull]>>;
                premium_type: z.ZodOptional<z.ZodUnion<[z.ZodNumber, z.ZodNull]>>;
                nickname: z.ZodOptional<z.ZodString>;
            }, "strip", z.ZodTypeAny, {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                flags: number;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                avatar_decoration_data?: {
                    asset: string;
                    skuId?: string | undefined;
                    expiresAt?: number | undefined;
                } | null | undefined;
                premium_type?: number | null | undefined;
                nickname?: string | undefined;
            }, {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                flags: number;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                avatar_decoration_data?: {
                    asset: string;
                    skuId?: string | undefined;
                    expiresAt?: number | undefined;
                } | null | undefined;
                premium_type?: number | null | undefined;
                nickname?: string | undefined;
            }>, "many">;
        }, "strip", z.ZodTypeAny, {
            participants: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                flags: number;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                avatar_decoration_data?: {
                    asset: string;
                    skuId?: string | undefined;
                    expiresAt?: number | undefined;
                } | null | undefined;
                premium_type?: number | null | undefined;
                nickname?: string | undefined;
            }[];
        }, {
            participants: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                flags: number;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                avatar_decoration_data?: {
                    asset: string;
                    skuId?: string | undefined;
                    expiresAt?: number | undefined;
                } | null | undefined;
                premium_type?: number | null | undefined;
                nickname?: string | undefined;
            }[];
        }>;
    };
    readonly SHARE_INTERACTION: {
        readonly request: z.ZodObject<{
            command: z.ZodString;
            options: z.ZodOptional<z.ZodArray<z.ZodObject<{
                name: z.ZodString;
                value: z.ZodString;
            }, "strip", z.ZodTypeAny, {
                value: string;
                name: string;
            }, {
                value: string;
                name: string;
            }>, "many">>;
            content: z.ZodOptional<z.ZodString>;
            require_launch_channel: z.ZodOptional<z.ZodBoolean>;
            preview_image: z.ZodOptional<z.ZodObject<{
                height: z.ZodNumber;
                url: z.ZodString;
                width: z.ZodNumber;
            }, "strip", z.ZodTypeAny, {
                height: number;
                url: string;
                width: number;
            }, {
                height: number;
                url: string;
                width: number;
            }>>;
            components: z.ZodOptional<z.ZodArray<z.ZodObject<{
                type: z.ZodLiteral<1>;
                components: z.ZodOptional<z.ZodArray<z.ZodObject<{
                    type: z.ZodLiteral<2>;
                    style: z.ZodNumber;
                    label: z.ZodOptional<z.ZodString>;
                    custom_id: z.ZodOptional<z.ZodString>;
                }, "strip", z.ZodTypeAny, {
                    type: 2;
                    style: number;
                    label?: string | undefined;
                    custom_id?: string | undefined;
                }, {
                    type: 2;
                    style: number;
                    label?: string | undefined;
                    custom_id?: string | undefined;
                }>, "many">>;
            }, "strip", z.ZodTypeAny, {
                type: 1;
                components?: {
                    type: 2;
                    style: number;
                    label?: string | undefined;
                    custom_id?: string | undefined;
                }[] | undefined;
            }, {
                type: 1;
                components?: {
                    type: 2;
                    style: number;
                    label?: string | undefined;
                    custom_id?: string | undefined;
                }[] | undefined;
            }>, "many">>;
            pid: z.ZodOptional<z.ZodNumber>;
        }, "strip", z.ZodTypeAny, {
            command: string;
            options?: {
                value: string;
                name: string;
            }[] | undefined;
            content?: string | undefined;
            require_launch_channel?: boolean | undefined;
            preview_image?: {
                height: number;
                url: string;
                width: number;
            } | undefined;
            components?: {
                type: 1;
                components?: {
                    type: 2;
                    style: number;
                    label?: string | undefined;
                    custom_id?: string | undefined;
                }[] | undefined;
            }[] | undefined;
            pid?: number | undefined;
        }, {
            command: string;
            options?: {
                value: string;
                name: string;
            }[] | undefined;
            content?: string | undefined;
            require_launch_channel?: boolean | undefined;
            preview_image?: {
                height: number;
                url: string;
                width: number;
            } | undefined;
            components?: {
                type: 1;
                components?: {
                    type: 2;
                    style: number;
                    label?: string | undefined;
                    custom_id?: string | undefined;
                }[] | undefined;
            }[] | undefined;
            pid?: number | undefined;
        }>;
        readonly response: z.ZodObject<{
            success: z.ZodBoolean;
        }, "strip", z.ZodTypeAny, {
            success: boolean;
        }, {
            success: boolean;
        }>;
    };
    readonly SHARE_LINK: {
        readonly request: z.ZodObject<{
            custom_id: z.ZodOptional<z.ZodString>;
            message: z.ZodString;
            link_id: z.ZodOptional<z.ZodString>;
        }, "strip", z.ZodTypeAny, {
            message: string;
            custom_id?: string | undefined;
            link_id?: string | undefined;
        }, {
            message: string;
            custom_id?: string | undefined;
            link_id?: string | undefined;
        }>;
        readonly response: z.ZodObject<{
            success: z.ZodBoolean;
            didCopyLink: z.ZodBoolean;
            didSendMessage: z.ZodBoolean;
        }, "strip", z.ZodTypeAny, {
            success: boolean;
            didCopyLink: boolean;
            didSendMessage: boolean;
        }, {
            success: boolean;
            didCopyLink: boolean;
            didSendMessage: boolean;
        }>;
    };
    readonly GET_RELATIONSHIPS: {
        readonly request: z.ZodVoid;
        readonly response: z.ZodObject<{
            relationships: z.ZodArray<z.ZodObject<{
                type: z.ZodNumber;
                user: z.ZodObject<{
                    id: z.ZodString;
                    username: z.ZodString;
                    global_name: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
                    discriminator: z.ZodString;
                    avatar: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
                    flags: z.ZodNumber;
                    bot: z.ZodBoolean;
                    avatar_decoration_data: z.ZodOptional<z.ZodUnion<[z.ZodObject<{
                        asset: z.ZodString;
                        skuId: z.ZodOptional<z.ZodString>;
                        expiresAt: z.ZodOptional<z.ZodNumber>;
                    }, "strip", z.ZodTypeAny, {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    }, {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    }>, z.ZodNull]>>;
                    premium_type: z.ZodOptional<z.ZodUnion<[z.ZodNumber, z.ZodNull]>>;
                }, "strip", z.ZodTypeAny, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                }, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                }>;
                presence: z.ZodOptional<z.ZodObject<{
                    status: z.ZodString;
                    activity: z.ZodOptional<z.ZodUnion<[z.ZodObject<{
                        session_id: z.ZodOptional<z.ZodString>;
                        type: z.ZodOptional<z.ZodNumber>;
                        name: z.ZodString;
                        url: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
                        application_id: z.ZodOptional<z.ZodString>;
                        status_display_type: z.ZodOptional<z.ZodNumber>;
                        state: z.ZodOptional<z.ZodString>;
                        state_url: z.ZodOptional<z.ZodString>;
                        details: z.ZodOptional<z.ZodString>;
                        details_url: z.ZodOptional<z.ZodString>;
                        emoji: z.ZodOptional<z.ZodUnion<[z.ZodObject<{
                            name: z.ZodString;
                            id: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
                            animated: z.ZodOptional<z.ZodUnion<[z.ZodBoolean, z.ZodNull]>>;
                        }, "strip", z.ZodTypeAny, {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        }, {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        }>, z.ZodNull]>>;
                        assets: z.ZodOptional<z.ZodObject<{
                            large_image: z.ZodOptional<z.ZodString>;
                            large_text: z.ZodOptional<z.ZodString>;
                            large_url: z.ZodOptional<z.ZodString>;
                            small_image: z.ZodOptional<z.ZodString>;
                            small_text: z.ZodOptional<z.ZodString>;
                            small_url: z.ZodOptional<z.ZodString>;
                        }, "strip", z.ZodTypeAny, {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        }, {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        }>>;
                        timestamps: z.ZodOptional<z.ZodObject<{
                            start: z.ZodOptional<z.ZodNumber>;
                            end: z.ZodOptional<z.ZodNumber>;
                        }, "strip", z.ZodTypeAny, {
                            start?: number | undefined;
                            end?: number | undefined;
                        }, {
                            start?: number | undefined;
                            end?: number | undefined;
                        }>>;
                        party: z.ZodOptional<z.ZodObject<{
                            id: z.ZodOptional<z.ZodString>;
                            size: z.ZodOptional<z.ZodArray<z.ZodNumber, "many">>;
                            privacy: z.ZodOptional<z.ZodNumber>;
                        }, "strip", z.ZodTypeAny, {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        }, {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        }>>;
                        secrets: z.ZodOptional<z.ZodObject<{
                            match: z.ZodOptional<z.ZodString>;
                            join: z.ZodOptional<z.ZodString>;
                        }, "strip", z.ZodTypeAny, {
                            join?: string | undefined;
                            match?: string | undefined;
                        }, {
                            join?: string | undefined;
                            match?: string | undefined;
                        }>>;
                        sync_id: z.ZodOptional<z.ZodString>;
                        created_at: z.ZodOptional<z.ZodNumber>;
                        instance: z.ZodOptional<z.ZodBoolean>;
                        flags: z.ZodOptional<z.ZodNumber>;
                        metadata: z.ZodOptional<z.ZodObject<{}, "strip", z.ZodTypeAny, {}, {}>>;
                        platform: z.ZodOptional<z.ZodString>;
                        supported_platforms: z.ZodOptional<z.ZodArray<z.ZodString, "many">>;
                        buttons: z.ZodOptional<z.ZodArray<z.ZodString, "many">>;
                        hangStatus: z.ZodOptional<z.ZodString>;
                    }, "strip", z.ZodTypeAny, {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    }, {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    }>, z.ZodNull]>>;
                }, "strip", z.ZodTypeAny, {
                    status: string;
                    activity?: {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    } | null | undefined;
                }, {
                    status: string;
                    activity?: {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    } | null | undefined;
                }>>;
            }, "strip", z.ZodTypeAny, {
                type: number;
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                };
                presence?: {
                    status: string;
                    activity?: {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    } | null | undefined;
                } | undefined;
            }, {
                type: number;
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                };
                presence?: {
                    status: string;
                    activity?: {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    } | null | undefined;
                } | undefined;
            }>, "many">;
        }, "strip", z.ZodTypeAny, {
            relationships: {
                type: number;
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                };
                presence?: {
                    status: string;
                    activity?: {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    } | null | undefined;
                } | undefined;
            }[];
        }, {
            relationships: {
                type: number;
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                };
                presence?: {
                    status: string;
                    activity?: {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    } | null | undefined;
                } | undefined;
            }[];
        }>;
    };
    readonly INVITE_USER_EMBEDDED: {
        readonly request: z.ZodObject<{
            user_id: z.ZodString;
            content: z.ZodOptional<z.ZodString>;
        }, "strip", z.ZodTypeAny, {
            user_id: string;
            content?: string | undefined;
        }, {
            user_id: string;
            content?: string | undefined;
        }>;
        readonly response: z.ZodNullable<z.ZodOptional<z.ZodObject<{}, "strip", z.ZodTypeAny, {}, {}>>>;
    };
    readonly GET_USER: {
        readonly request: z.ZodObject<{
            id: z.ZodString;
        }, "strip", z.ZodTypeAny, {
            id: string;
        }, {
            id: string;
        }>;
        readonly response: z.ZodUnion<[z.ZodObject<{
            id: z.ZodString;
            username: z.ZodString;
            global_name: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
            discriminator: z.ZodString;
            avatar: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
            flags: z.ZodNumber;
            bot: z.ZodBoolean;
            avatar_decoration_data: z.ZodOptional<z.ZodUnion<[z.ZodObject<{
                asset: z.ZodString;
                skuId: z.ZodOptional<z.ZodString>;
                expiresAt: z.ZodOptional<z.ZodNumber>;
            }, "strip", z.ZodTypeAny, {
                asset: string;
                skuId?: string | undefined;
                expiresAt?: number | undefined;
            }, {
                asset: string;
                skuId?: string | undefined;
                expiresAt?: number | undefined;
            }>, z.ZodNull]>>;
            premium_type: z.ZodOptional<z.ZodUnion<[z.ZodNumber, z.ZodNull]>>;
        }, "strip", z.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            flags: number;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            avatar_decoration_data?: {
                asset: string;
                skuId?: string | undefined;
                expiresAt?: number | undefined;
            } | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            flags: number;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            avatar_decoration_data?: {
                asset: string;
                skuId?: string | undefined;
                expiresAt?: number | undefined;
            } | null | undefined;
            premium_type?: number | null | undefined;
        }>, z.ZodNull]>;
    };
    readonly GET_QUEST_ENROLLMENT_STATUS: {
        readonly request: z.ZodObject<{
            quest_id: z.ZodString;
        }, "strip", z.ZodTypeAny, {
            quest_id: string;
        }, {
            quest_id: string;
        }>;
        readonly response: z.ZodObject<{
            quest_id: z.ZodString;
            is_enrolled: z.ZodBoolean;
            enrolled_at: z.ZodOptional<z.ZodUnion<[z.ZodString, z.ZodNull]>>;
        }, "strip", z.ZodTypeAny, {
            quest_id: string;
            is_enrolled: boolean;
            enrolled_at?: string | null | undefined;
        }, {
            quest_id: string;
            is_enrolled: boolean;
            enrolled_at?: string | null | undefined;
        }>;
    };
    readonly QUEST_START_TIMER: {
        readonly request: z.ZodObject<{
            quest_id: z.ZodString;
        }, "strip", z.ZodTypeAny, {
            quest_id: string;
        }, {
            quest_id: string;
        }>;
        readonly response: z.ZodObject<{
            success: z.ZodBoolean;
        }, "strip", z.ZodTypeAny, {
            success: boolean;
        }, {
            success: boolean;
        }>;
    };
};

// ===== output/index.d.ts =====
export type { EventPayloadData } from './schema/events';
$1export declare const Commands: typeof Common.Commands;
export type { IDiscordSDK, CommandTypes, CommandInput, CommandInputTypes, CommandResponse, CommandResponseTypes, ISDKError, Types, };

// ===== output/interface.d.ts =====
/**
 * An optional configuration object to customize the sdk options
 */
export interface SdkConfiguration {
    /**
     * By default, all console logging is overridden and forwarded to the host application.
     * Logs will still be sent to the web console as well.
     * Setting this flag to true will disable this functionality
     */
    readonly disableConsoleLogOverride: boolean;
}
export type MaybeZodObjectArray<T extends EventArgs> = T['subscribeArgs'] extends NonNullable<EventArgs['subscribeArgs']> ? [zod.infer<T['subscribeArgs']>] : [undefined?];
export interface IDiscordSDK {
    readonly clientId: string;
    readonly instanceId: string;
    readonly customId: string | null;
    readonly referrerId: string | null;
    readonly platform: Platform;
    readonly mobileAppVersion: string | null;
    readonly sdkVersion: string;
    readonly commands: ReturnType<typeof commands>;
    readonly configuration: SdkConfiguration;
    readonly channelId: string | null;
    readonly guildId: string | null;
    readonly source: Window | WindowProxy | null;
    readonly sourceOrigin: string;
    close(code: RPCCloseCodes, message: string): void;
    subscribe<K extends keyof typeof EventSchema>(event: K, listener: (event: zod.infer<(typeof EventSchema)[K]['payload']>['data']) => unknown, ...subscribeArgs: MaybeZodObjectArray<(typeof EventSchema)[K]>): Promise<unknown>;
    unsubscribe<K extends keyof typeof EventSchema>(event: K, listener: (event: zod.infer<(typeof EventSchema)[K]['payload']>['data']) => unknown, ...unsubscribeArgs: MaybeZodObjectArray<(typeof EventSchema)[K]>): Promise<unknown>;
    ready(): Promise<void>;
}

// ===== output/mock.d.ts =====
export declare class DiscordSDKMock implements IDiscordSDK {
    readonly clientId: string;
    readonly platform = Platform.DESKTOP;
    readonly instanceId = "123456789012345678";
    readonly customId: string | null;
    readonly referrerId: string | null;
    readonly configuration: import("./interface").SdkConfiguration;
    readonly source: Window | WindowProxy | null;
    readonly sourceOrigin: string;
    readonly sdkVersion = "mock";
    readonly mobileAppVersion = "unknown";
    private frameId;
    private eventBus;
    commands: IDiscordSDK['commands'];
    readonly guildId: string | null;
    readonly channelId: string | null;
    readonly locationId: string | null;
    constructor(clientId: string, guildId: string | null, channelId: string | null, locationId: string | null);
    _updateCommandMocks(newCommands: Partial<IDiscordSDK['commands']>): {
        authorize: (args: import("./commands/authorize").AuthorizeInput) => Promise<{
            code: string;
        }>;
        captureLog: (args: import("./commands/captureLog").CaptureLogInput) => Promise<{} | null>;
        encourageHardwareAcceleration: (args: void) => Promise<{
            enabled: boolean;
        }>;
        getChannel: (args: import("./commands/getChannel").GetChannelInput) => Promise<{
            type: 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1;
            id: string;
            voice_states: {
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                };
                nick: string;
                mute: boolean;
                voice_state: {
                    deaf: boolean;
                    mute: boolean;
                    self_mute: boolean;
                    self_deaf: boolean;
                    suppress: boolean;
                };
                volume: number;
            }[];
            messages: {
                type: number;
                id: string;
                content: string;
                timestamp: string;
                channel_id: string;
                tts: boolean;
                mention_everyone: boolean;
                mentions: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                }[];
                mention_roles: string[];
                mention_channels: {
                    type: number;
                    id: string;
                    name: string;
                    guild_id: string;
                }[];
                attachments: {
                    id: string;
                    url: string;
                    size: number;
                    filename: string;
                    proxy_url: string;
                    height?: number | null | undefined;
                    width?: number | null | undefined;
                }[];
                embeds: {
                    type?: string | null | undefined;
                    description?: string | null | undefined;
                    url?: string | null | undefined;
                    color?: number | null | undefined;
                    title?: string | null | undefined;
                    timestamp?: string | null | undefined;
                    footer?: {
                        text: string;
                        icon_url?: string | null | undefined;
                        proxy_icon_url?: string | null | undefined;
                    } | null | undefined;
                    image?: {
                        height?: number | null | undefined;
                        url?: string | null | undefined;
                        width?: number | null | undefined;
                        proxy_url?: string | null | undefined;
                    } | null | undefined;
                    thumbnail?: {
                        height?: number | null | undefined;
                        url?: string | null | undefined;
                        width?: number | null | undefined;
                        proxy_url?: string | null | undefined;
                    } | null | undefined;
                    video?: {
                        height?: number | null | undefined;
                        url?: string | null | undefined;
                        width?: number | null | undefined;
                    } | null | undefined;
                    provider?: {
                        name?: string | null | undefined;
                        url?: string | null | undefined;
                    } | null | undefined;
                    author?: {
                        name?: string | null | undefined;
                        url?: string | null | undefined;
                        icon_url?: string | null | undefined;
                        proxy_icon_url?: string | null | undefined;
                    } | null | undefined;
                    fields?: {
                        value: string;
                        name: string;
                        inline: boolean;
                    }[] | null | undefined;
                }[];
                pinned: boolean;
                application?: {
                    id: string;
                    description: string;
                    name: string;
                    icon?: string | null | undefined;
                    cover_image?: string | null | undefined;
                } | null | undefined;
                flags?: number | null | undefined;
                activity?: {
                    type: number;
                    party_id?: string | null | undefined;
                } | null | undefined;
                nonce?: string | number | null | undefined;
                guild_id?: string | null | undefined;
                author?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                member?: {
                    user: {
                        username: string;
                        discriminator: string;
                        id: string;
                        bot: boolean;
                        avatar_decoration_data: {
                            asset: string;
                            sku_id?: string | undefined;
                        } | null;
                        avatar?: string | null | undefined;
                        global_name?: string | null | undefined;
                        flags?: number | null | undefined;
                        premium_type?: number | null | undefined;
                    };
                    roles: string[];
                    joined_at: string;
                    deaf: boolean;
                    mute: boolean;
                    nick?: string | null | undefined;
                } | null | undefined;
                edited_timestamp?: string | null | undefined;
                reactions?: {
                    emoji: {
                        id: string;
                        user?: {
                            username: string;
                            discriminator: string;
                            id: string;
                            bot: boolean;
                            avatar_decoration_data: {
                                asset: string;
                                sku_id?: string | undefined;
                            } | null;
                            avatar?: string | null | undefined;
                            global_name?: string | null | undefined;
                            flags?: number | null | undefined;
                            premium_type?: number | null | undefined;
                        } | null | undefined;
                        name?: string | null | undefined;
                        animated?: boolean | null | undefined;
                        roles?: string[] | null | undefined;
                        require_colons?: boolean | null | undefined;
                        managed?: boolean | null | undefined;
                        available?: boolean | null | undefined;
                    };
                    count: number;
                    me: boolean;
                }[] | null | undefined;
                webhook_id?: string | null | undefined;
                message_reference?: {
                    guild_id?: string | null | undefined;
                    message_id?: string | null | undefined;
                    channel_id?: string | null | undefined;
                } | null | undefined;
                stickers?: unknown[] | null | undefined;
                referenced_message?: unknown;
            }[];
            name?: string | null | undefined;
            guild_id?: string | null | undefined;
            position?: number | null | undefined;
            topic?: string | null | undefined;
            bitrate?: number | null | undefined;
            user_limit?: number | null | undefined;
        }>;
        getChannelPermissions: (args: void) => Promise<{
            permissions: string | bigint;
        }>;
        getEntitlements: (args: void) => Promise<{
            entitlements: {
                type: 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1;
                id: string;
                application_id: string;
                user_id: string;
                sku_id: string;
                gift_code_flags: number;
                parent_id?: string | null | undefined;
                gifter_user_id?: string | null | undefined;
                branches?: string[] | null | undefined;
                starts_at?: string | null | undefined;
                ends_at?: string | null | undefined;
                consumed?: boolean | null | undefined;
                deleted?: boolean | null | undefined;
                gift_code_batch_id?: string | null | undefined;
            }[];
        }>;
        getPlatformBehaviors: (args: void) => Promise<{
            iosKeyboardResizesView?: boolean | undefined;
        }>;
        getSkus: (args: void) => Promise<{
            skus: {
                type: 1 | 4 | 2 | 3 | 5 | -1;
                id: string;
                name: string;
                flags: number;
                application_id: string;
                price: {
                    amount: number;
                    currency: string;
                };
                release_date: string | null;
            }[];
        }>;
        openExternalLink: (args: import("./commands/openExternalLink").OpenExternalLinkInput) => Promise<{
            opened: boolean | null;
        }>;
        openInviteDialog: (args: void) => Promise<{} | null>;
        setActivity: (args: import("./commands/setActivity").SetActivityInput) => Promise<{
            type: number;
            name: string;
            flags?: number | null | undefined;
            url?: string | null | undefined;
            application_id?: string | null | undefined;
            state?: string | null | undefined;
            state_url?: string | null | undefined;
            details?: string | null | undefined;
            details_url?: string | null | undefined;
            emoji?: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            } | null | undefined;
            assets?: {
                large_image?: string | null | undefined;
                large_text?: string | null | undefined;
                large_url?: string | null | undefined;
                small_image?: string | null | undefined;
                small_text?: string | null | undefined;
                small_url?: string | null | undefined;
            } | null | undefined;
            timestamps?: {
                start?: number | undefined;
                end?: number | undefined;
            } | null | undefined;
            party?: {
                id?: string | null | undefined;
                size?: number[] | null | undefined;
            } | null | undefined;
            secrets?: {
                join?: string | undefined;
                match?: string | undefined;
            } | null | undefined;
            created_at?: number | null | undefined;
            instance?: boolean | null | undefined;
        }>;
        setConfig: (args: import("./commands/setConfig").SetConfigInput) => Promise<{
            use_interactive_pip: boolean;
        }>;
        setOrientationLockState: (args: import("./commands/setOrientationLockState").SetOrientationLockStateInput) => Promise<{} | null>;
        startPurchase: (args: import("./commands/startPurchase").StartPurchaseInput) => Promise<{
            type: 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1;
            id: string;
            application_id: string;
            user_id: string;
            sku_id: string;
            gift_code_flags: number;
            parent_id?: string | null | undefined;
            gifter_user_id?: string | null | undefined;
            branches?: string[] | null | undefined;
            starts_at?: string | null | undefined;
            ends_at?: string | null | undefined;
            consumed?: boolean | null | undefined;
            deleted?: boolean | null | undefined;
            gift_code_batch_id?: string | null | undefined;
        }[] | null>;
        userSettingsGetLocale: (args: void) => Promise<{
            locale: string;
        }>;
        getInstanceConnectedParticipants: (args: void) => Promise<{
            participants: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                flags: number;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                avatar_decoration_data?: {
                    asset: string;
                    skuId?: string | undefined;
                    expiresAt?: number | undefined;
                } | null | undefined;
                premium_type?: number | null | undefined;
                nickname?: string | undefined;
            }[];
        }>;
        authenticate: (args: {
            access_token?: string | null | undefined;
        }) => Promise<{
            access_token: string;
            user: {
                username: string;
                discriminator: string;
                id: string;
                public_flags: number;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
            };
            scopes: (-1 | "identify" | "email" | "connections" | "guilds" | "guilds.join" | "guilds.members.read" | "guilds.channels.read" | "gdm.join" | "bot" | "rpc" | "rpc.notifications.read" | "rpc.voice.read" | "rpc.voice.write" | "rpc.video.read" | "rpc.video.write" | "rpc.screenshare.read" | "rpc.screenshare.write" | "rpc.activities.write" | "webhook.incoming" | "messages.read" | "applications.builds.upload" | "applications.builds.read" | "applications.commands" | "applications.commands.permissions.update" | "applications.commands.update" | "applications.store.update" | "applications.entitlements" | "activities.read" | "activities.write" | "activities.invites.write" | "relationships.read" | "relationships.write" | "voice" | "dm_channels.read" | "role_connections.write" | "presences.read" | "presences.write" | "openid" | "dm_channels.messages.read" | "dm_channels.messages.write" | "gateway.connect" | "account.global_name.update" | "payment_sources.country_code" | "sdk.social_layer_presence" | "sdk.social_layer" | "lobbies.write" | "application_identities.write")[];
            expires: string;
            application: {
                id: string;
                description: string;
                name: string;
                icon?: string | null | undefined;
                rpc_origins?: string[] | undefined;
            };
        }>;
        getActivityInstanceConnectedParticipants: (args: void) => Promise<{
            participants: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                flags: number;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                avatar_decoration_data?: {
                    asset: string;
                    skuId?: string | undefined;
                    expiresAt?: number | undefined;
                } | null | undefined;
                premium_type?: number | null | undefined;
                nickname?: string | undefined;
            }[];
        }>;
        getQuestEnrollmentStatus: (args: {
            quest_id: string;
        }) => Promise<{
            quest_id: string;
            is_enrolled: boolean;
            enrolled_at?: string | null | undefined;
        }>;
        getRelationships: (args: void) => Promise<{
            relationships: {
                type: number;
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                };
                presence?: {
                    status: string;
                    activity?: {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    } | null | undefined;
                } | undefined;
            }[];
        }>;
        getUser: (args: {
            id: string;
        }) => Promise<{
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            flags: number;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            avatar_decoration_data?: {
                asset: string;
                skuId?: string | undefined;
                expiresAt?: number | undefined;
            } | null | undefined;
            premium_type?: number | null | undefined;
        } | null>;
        initiateImageUpload: (args: void) => Promise<{
            image_url: string;
        }>;
        inviteUserEmbedded: (args: {
            user_id: string;
            content?: string | undefined;
        }) => Promise<{} | null | undefined>;
        openShareMomentDialog: (args: {
            mediaUrl: string;
        }) => Promise<{} | null | undefined>;
        questStartTimer: (args: {
            quest_id: string;
        }) => Promise<{
            success: boolean;
        }>;
        shareInteraction: (args: {
            command: string;
            options?: {
                value: string;
                name: string;
            }[] | undefined;
            content?: string | undefined;
            require_launch_channel?: boolean | undefined;
            preview_image?: {
                height: number;
                url: string;
                width: number;
            } | undefined;
            components?: {
                type: 1;
                components?: {
                    type: 2;
                    style: number;
                    label?: string | undefined;
                    custom_id?: string | undefined;
                }[] | undefined;
            }[] | undefined;
            pid?: number | undefined;
        }) => Promise<{
            success: boolean;
        }>;
        shareLink: (args: {
            message: string;
            custom_id?: string | undefined;
            link_id?: string | undefined;
        }) => Promise<{
            success: boolean;
            didCopyLink: boolean;
            didSendMessage: boolean;
        }>;
    };
    emitReady(): void;
    close(...args: any[]): void;
    ready(): Promise<void>;
    subscribe<K extends keyof typeof EventSchema>(event: K, listener: (event: zod.infer<(typeof EventSchema)[K]['payload']>['data']) => unknown, ..._subscribeArgs: MaybeZodObjectArray<(typeof EventSchema)[K]>): Promise<EventEmitter<string | symbol, any>>;
    unsubscribe<K extends keyof typeof EventSchema>(event: K, listener: (event: zod.infer<(typeof EventSchema)[K]['payload']>['data']) => unknown, ..._unsubscribeArgs: MaybeZodObjectArray<(typeof EventSchema)[K]>): Promise<unknown>;
    emitEvent<T>(event: string, data: T): void;
}
/** Default return values for all discord SDK commands */
export declare const commandsMockDefault: IDiscordSDK['commands'];

// ===== output/schema/common.d.ts =====
export declare const DISPATCH = "DISPATCH";
export declare enum Commands {
    AUTHORIZE = "AUTHORIZE",
    GET_GUILDS = "GET_GUILDS",
    GET_GUILD = "GET_GUILD",
    GET_CHANNEL = "GET_CHANNEL",
    GET_CHANNELS = "GET_CHANNELS",
    SELECT_VOICE_CHANNEL = "SELECT_VOICE_CHANNEL",
    SELECT_TEXT_CHANNEL = "SELECT_TEXT_CHANNEL",
    SUBSCRIBE = "SUBSCRIBE",
    UNSUBSCRIBE = "UNSUBSCRIBE",
    CAPTURE_SHORTCUT = "CAPTURE_SHORTCUT",
    SET_CERTIFIED_DEVICES = "SET_CERTIFIED_DEVICES",
    SET_ACTIVITY = "SET_ACTIVITY",
    GET_SKUS = "GET_SKUS",
    GET_ENTITLEMENTS = "GET_ENTITLEMENTS",
    GET_SKUS_EMBEDDED = "GET_SKUS_EMBEDDED",
    GET_ENTITLEMENTS_EMBEDDED = "GET_ENTITLEMENTS_EMBEDDED",
    START_PURCHASE = "START_PURCHASE",
    SET_CONFIG = "SET_CONFIG",
    SEND_ANALYTICS_EVENT = "SEND_ANALYTICS_EVENT",
    USER_SETTINGS_GET_LOCALE = "USER_SETTINGS_GET_LOCALE",
    OPEN_EXTERNAL_LINK = "OPEN_EXTERNAL_LINK",
    ENCOURAGE_HW_ACCELERATION = "ENCOURAGE_HW_ACCELERATION",
    CAPTURE_LOG = "CAPTURE_LOG",
    SET_ORIENTATION_LOCK_STATE = "SET_ORIENTATION_LOCK_STATE",
    OPEN_INVITE_DIALOG = "OPEN_INVITE_DIALOG",
    GET_PLATFORM_BEHAVIORS = "GET_PLATFORM_BEHAVIORS",
    GET_CHANNEL_PERMISSIONS = "GET_CHANNEL_PERMISSIONS",
    AUTHENTICATE = "AUTHENTICATE",
    GET_ACTIVITY_INSTANCE_CONNECTED_PARTICIPANTS = "GET_ACTIVITY_INSTANCE_CONNECTED_PARTICIPANTS",
    GET_QUEST_ENROLLMENT_STATUS = "GET_QUEST_ENROLLMENT_STATUS",
    GET_RELATIONSHIPS = "GET_RELATIONSHIPS",
    GET_USER = "GET_USER",
    INITIATE_IMAGE_UPLOAD = "INITIATE_IMAGE_UPLOAD",
    INVITE_USER_EMBEDDED = "INVITE_USER_EMBEDDED",
    OPEN_SHARE_MOMENT_DIALOG = "OPEN_SHARE_MOMENT_DIALOG",
    QUEST_START_TIMER = "QUEST_START_TIMER",
    SHARE_INTERACTION = "SHARE_INTERACTION",
    SHARE_LINK = "SHARE_LINK"
}
export declare const ReceiveFramePayload: zod.ZodObject<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, zod.ZodTypeAny, "passthrough">>;
export declare const ScopesObject: {
    readonly UNHANDLED: -1;
    readonly identify: "identify";
    readonly email: "email";
    readonly connections: "connections";
    readonly guilds: "guilds";
    readonly "guilds.join": "guilds.join";
    readonly "guilds.members.read": "guilds.members.read";
    readonly "guilds.channels.read": "guilds.channels.read";
    readonly "gdm.join": "gdm.join";
    readonly bot: "bot";
    readonly rpc: "rpc";
    readonly "rpc.notifications.read": "rpc.notifications.read";
    readonly "rpc.voice.read": "rpc.voice.read";
    readonly "rpc.voice.write": "rpc.voice.write";
    readonly "rpc.video.read": "rpc.video.read";
    readonly "rpc.video.write": "rpc.video.write";
    readonly "rpc.screenshare.read": "rpc.screenshare.read";
    readonly "rpc.screenshare.write": "rpc.screenshare.write";
    readonly "rpc.activities.write": "rpc.activities.write";
    readonly "webhook.incoming": "webhook.incoming";
    readonly "messages.read": "messages.read";
    readonly "applications.builds.upload": "applications.builds.upload";
    readonly "applications.builds.read": "applications.builds.read";
    readonly "applications.commands": "applications.commands";
    readonly "applications.commands.permissions.update": "applications.commands.permissions.update";
    readonly "applications.commands.update": "applications.commands.update";
    readonly "applications.store.update": "applications.store.update";
    readonly "applications.entitlements": "applications.entitlements";
    readonly "activities.read": "activities.read";
    readonly "activities.write": "activities.write";
    readonly "activities.invites.write": "activities.invites.write";
    readonly "relationships.read": "relationships.read";
    readonly "relationships.write": "relationships.write";
    readonly voice: "voice";
    readonly "dm_channels.read": "dm_channels.read";
    readonly "role_connections.write": "role_connections.write";
    readonly "presences.read": "presences.read";
    readonly "presences.write": "presences.write";
    readonly openid: "openid";
    readonly "dm_channels.messages.read": "dm_channels.messages.read";
    readonly "dm_channels.messages.write": "dm_channels.messages.write";
    readonly "gateway.connect": "gateway.connect";
    readonly "account.global_name.update": "account.global_name.update";
    readonly "payment_sources.country_code": "payment_sources.country_code";
    readonly "sdk.social_layer_presence": "sdk.social_layer_presence";
    readonly "sdk.social_layer": "sdk.social_layer";
    readonly "lobbies.write": "lobbies.write";
    readonly "application_identities.write": "application_identities.write";
};
export declare const Scopes: zod.ZodEffects<zod.ZodType<-1 | "identify" | "email" | "connections" | "guilds" | "guilds.join" | "guilds.members.read" | "guilds.channels.read" | "gdm.join" | "bot" | "rpc" | "rpc.notifications.read" | "rpc.voice.read" | "rpc.voice.write" | "rpc.video.read" | "rpc.video.write" | "rpc.screenshare.read" | "rpc.screenshare.write" | "rpc.activities.write" | "webhook.incoming" | "messages.read" | "applications.builds.upload" | "applications.builds.read" | "applications.commands" | "applications.commands.permissions.update" | "applications.commands.update" | "applications.store.update" | "applications.entitlements" | "activities.read" | "activities.write" | "activities.invites.write" | "relationships.read" | "relationships.write" | "voice" | "dm_channels.read" | "role_connections.write" | "presences.read" | "presences.write" | "openid" | "dm_channels.messages.read" | "dm_channels.messages.write" | "gateway.connect" | "account.global_name.update" | "payment_sources.country_code" | "sdk.social_layer_presence" | "sdk.social_layer" | "lobbies.write" | "application_identities.write", zod.ZodTypeDef, -1 | "identify" | "email" | "connections" | "guilds" | "guilds.join" | "guilds.members.read" | "guilds.channels.read" | "gdm.join" | "bot" | "rpc" | "rpc.notifications.read" | "rpc.voice.read" | "rpc.voice.write" | "rpc.video.read" | "rpc.video.write" | "rpc.screenshare.read" | "rpc.screenshare.write" | "rpc.activities.write" | "webhook.incoming" | "messages.read" | "applications.builds.upload" | "applications.builds.read" | "applications.commands" | "applications.commands.permissions.update" | "applications.commands.update" | "applications.store.update" | "applications.entitlements" | "activities.read" | "activities.write" | "activities.invites.write" | "relationships.read" | "relationships.write" | "voice" | "dm_channels.read" | "role_connections.write" | "presences.read" | "presences.write" | "openid" | "dm_channels.messages.read" | "dm_channels.messages.write" | "gateway.connect" | "account.global_name.update" | "payment_sources.country_code" | "sdk.social_layer_presence" | "sdk.social_layer" | "lobbies.write" | "application_identities.write">, -1 | "identify" | "email" | "connections" | "guilds" | "guilds.join" | "guilds.members.read" | "guilds.channels.read" | "gdm.join" | "bot" | "rpc" | "rpc.notifications.read" | "rpc.voice.read" | "rpc.voice.write" | "rpc.video.read" | "rpc.video.write" | "rpc.screenshare.read" | "rpc.screenshare.write" | "rpc.activities.write" | "webhook.incoming" | "messages.read" | "applications.builds.upload" | "applications.builds.read" | "applications.commands" | "applications.commands.permissions.update" | "applications.commands.update" | "applications.store.update" | "applications.entitlements" | "activities.read" | "activities.write" | "activities.invites.write" | "relationships.read" | "relationships.write" | "voice" | "dm_channels.read" | "role_connections.write" | "presences.read" | "presences.write" | "openid" | "dm_channels.messages.read" | "dm_channels.messages.write" | "gateway.connect" | "account.global_name.update" | "payment_sources.country_code" | "sdk.social_layer_presence" | "sdk.social_layer" | "lobbies.write" | "application_identities.write", unknown>;
export declare const Relationship: zod.ZodObject<{
    type: zod.ZodNumber;
    user: zod.ZodObject<{
        id: zod.ZodString;
        username: zod.ZodString;
        global_name: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
        discriminator: zod.ZodString;
        avatar: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
        flags: zod.ZodNumber;
        bot: zod.ZodBoolean;
        avatar_decoration_data: zod.ZodOptional<zod.ZodUnion<[zod.ZodObject<{
            asset: zod.ZodString;
            skuId: zod.ZodOptional<zod.ZodString>;
            expiresAt: zod.ZodOptional<zod.ZodNumber>;
        }, "strip", zod.ZodTypeAny, {
            asset: string;
            skuId?: string | undefined;
            expiresAt?: number | undefined;
        }, {
            asset: string;
            skuId?: string | undefined;
            expiresAt?: number | undefined;
        }>, zod.ZodNull]>>;
        premium_type: zod.ZodOptional<zod.ZodUnion<[zod.ZodNumber, zod.ZodNull]>>;
    }, "strip", zod.ZodTypeAny, {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        flags: number;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        avatar_decoration_data?: {
            asset: string;
            skuId?: string | undefined;
            expiresAt?: number | undefined;
        } | null | undefined;
        premium_type?: number | null | undefined;
    }, {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        flags: number;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        avatar_decoration_data?: {
            asset: string;
            skuId?: string | undefined;
            expiresAt?: number | undefined;
        } | null | undefined;
        premium_type?: number | null | undefined;
    }>;
    presence: zod.ZodOptional<zod.ZodObject<{
        status: zod.ZodString;
        activity: zod.ZodOptional<zod.ZodUnion<[zod.ZodObject<{
            session_id: zod.ZodOptional<zod.ZodString>;
            type: zod.ZodOptional<zod.ZodNumber>;
            name: zod.ZodString;
            url: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
            application_id: zod.ZodOptional<zod.ZodString>;
            status_display_type: zod.ZodOptional<zod.ZodNumber>;
            state: zod.ZodOptional<zod.ZodString>;
            state_url: zod.ZodOptional<zod.ZodString>;
            details: zod.ZodOptional<zod.ZodString>;
            details_url: zod.ZodOptional<zod.ZodString>;
            emoji: zod.ZodOptional<zod.ZodUnion<[zod.ZodObject<{
                name: zod.ZodString;
                id: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
                animated: zod.ZodOptional<zod.ZodUnion<[zod.ZodBoolean, zod.ZodNull]>>;
            }, "strip", zod.ZodTypeAny, {
                name: string;
                id?: string | null | undefined;
                animated?: boolean | null | undefined;
            }, {
                name: string;
                id?: string | null | undefined;
                animated?: boolean | null | undefined;
            }>, zod.ZodNull]>>;
            assets: zod.ZodOptional<zod.ZodObject<{
                large_image: zod.ZodOptional<zod.ZodString>;
                large_text: zod.ZodOptional<zod.ZodString>;
                large_url: zod.ZodOptional<zod.ZodString>;
                small_image: zod.ZodOptional<zod.ZodString>;
                small_text: zod.ZodOptional<zod.ZodString>;
                small_url: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                large_image?: string | undefined;
                large_text?: string | undefined;
                large_url?: string | undefined;
                small_image?: string | undefined;
                small_text?: string | undefined;
                small_url?: string | undefined;
            }, {
                large_image?: string | undefined;
                large_text?: string | undefined;
                large_url?: string | undefined;
                small_image?: string | undefined;
                small_text?: string | undefined;
                small_url?: string | undefined;
            }>>;
            timestamps: zod.ZodOptional<zod.ZodObject<{
                start: zod.ZodOptional<zod.ZodNumber>;
                end: zod.ZodOptional<zod.ZodNumber>;
            }, "strip", zod.ZodTypeAny, {
                start?: number | undefined;
                end?: number | undefined;
            }, {
                start?: number | undefined;
                end?: number | undefined;
            }>>;
            party: zod.ZodOptional<zod.ZodObject<{
                id: zod.ZodOptional<zod.ZodString>;
                size: zod.ZodOptional<zod.ZodArray<zod.ZodNumber, "many">>;
                privacy: zod.ZodOptional<zod.ZodNumber>;
            }, "strip", zod.ZodTypeAny, {
                id?: string | undefined;
                size?: number[] | undefined;
                privacy?: number | undefined;
            }, {
                id?: string | undefined;
                size?: number[] | undefined;
                privacy?: number | undefined;
            }>>;
            secrets: zod.ZodOptional<zod.ZodObject<{
                match: zod.ZodOptional<zod.ZodString>;
                join: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                join?: string | undefined;
                match?: string | undefined;
            }, {
                join?: string | undefined;
                match?: string | undefined;
            }>>;
            sync_id: zod.ZodOptional<zod.ZodString>;
            created_at: zod.ZodOptional<zod.ZodNumber>;
            instance: zod.ZodOptional<zod.ZodBoolean>;
            flags: zod.ZodOptional<zod.ZodNumber>;
            metadata: zod.ZodOptional<zod.ZodObject<{}, "strip", zod.ZodTypeAny, {}, {}>>;
            platform: zod.ZodOptional<zod.ZodString>;
            supported_platforms: zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>;
            buttons: zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>;
            hangStatus: zod.ZodOptional<zod.ZodString>;
        }, "strip", zod.ZodTypeAny, {
            name: string;
            type?: number | undefined;
            flags?: number | undefined;
            url?: string | null | undefined;
            session_id?: string | undefined;
            application_id?: string | undefined;
            status_display_type?: number | undefined;
            state?: string | undefined;
            state_url?: string | undefined;
            details?: string | undefined;
            details_url?: string | undefined;
            emoji?: {
                name: string;
                id?: string | null | undefined;
                animated?: boolean | null | undefined;
            } | null | undefined;
            assets?: {
                large_image?: string | undefined;
                large_text?: string | undefined;
                large_url?: string | undefined;
                small_image?: string | undefined;
                small_text?: string | undefined;
                small_url?: string | undefined;
            } | undefined;
            timestamps?: {
                start?: number | undefined;
                end?: number | undefined;
            } | undefined;
            party?: {
                id?: string | undefined;
                size?: number[] | undefined;
                privacy?: number | undefined;
            } | undefined;
            secrets?: {
                join?: string | undefined;
                match?: string | undefined;
            } | undefined;
            sync_id?: string | undefined;
            created_at?: number | undefined;
            instance?: boolean | undefined;
            metadata?: {} | undefined;
            platform?: string | undefined;
            supported_platforms?: string[] | undefined;
            buttons?: string[] | undefined;
            hangStatus?: string | undefined;
        }, {
            name: string;
            type?: number | undefined;
            flags?: number | undefined;
            url?: string | null | undefined;
            session_id?: string | undefined;
            application_id?: string | undefined;
            status_display_type?: number | undefined;
            state?: string | undefined;
            state_url?: string | undefined;
            details?: string | undefined;
            details_url?: string | undefined;
            emoji?: {
                name: string;
                id?: string | null | undefined;
                animated?: boolean | null | undefined;
            } | null | undefined;
            assets?: {
                large_image?: string | undefined;
                large_text?: string | undefined;
                large_url?: string | undefined;
                small_image?: string | undefined;
                small_text?: string | undefined;
                small_url?: string | undefined;
            } | undefined;
            timestamps?: {
                start?: number | undefined;
                end?: number | undefined;
            } | undefined;
            party?: {
                id?: string | undefined;
                size?: number[] | undefined;
                privacy?: number | undefined;
            } | undefined;
            secrets?: {
                join?: string | undefined;
                match?: string | undefined;
            } | undefined;
            sync_id?: string | undefined;
            created_at?: number | undefined;
            instance?: boolean | undefined;
            metadata?: {} | undefined;
            platform?: string | undefined;
            supported_platforms?: string[] | undefined;
            buttons?: string[] | undefined;
            hangStatus?: string | undefined;
        }>, zod.ZodNull]>>;
    }, "strip", zod.ZodTypeAny, {
        status: string;
        activity?: {
            name: string;
            type?: number | undefined;
            flags?: number | undefined;
            url?: string | null | undefined;
            session_id?: string | undefined;
            application_id?: string | undefined;
            status_display_type?: number | undefined;
            state?: string | undefined;
            state_url?: string | undefined;
            details?: string | undefined;
            details_url?: string | undefined;
            emoji?: {
                name: string;
                id?: string | null | undefined;
                animated?: boolean | null | undefined;
            } | null | undefined;
            assets?: {
                large_image?: string | undefined;
                large_text?: string | undefined;
                large_url?: string | undefined;
                small_image?: string | undefined;
                small_text?: string | undefined;
                small_url?: string | undefined;
            } | undefined;
            timestamps?: {
                start?: number | undefined;
                end?: number | undefined;
            } | undefined;
            party?: {
                id?: string | undefined;
                size?: number[] | undefined;
                privacy?: number | undefined;
            } | undefined;
            secrets?: {
                join?: string | undefined;
                match?: string | undefined;
            } | undefined;
            sync_id?: string | undefined;
            created_at?: number | undefined;
            instance?: boolean | undefined;
            metadata?: {} | undefined;
            platform?: string | undefined;
            supported_platforms?: string[] | undefined;
            buttons?: string[] | undefined;
            hangStatus?: string | undefined;
        } | null | undefined;
    }, {
        status: string;
        activity?: {
            name: string;
            type?: number | undefined;
            flags?: number | undefined;
            url?: string | null | undefined;
            session_id?: string | undefined;
            application_id?: string | undefined;
            status_display_type?: number | undefined;
            state?: string | undefined;
            state_url?: string | undefined;
            details?: string | undefined;
            details_url?: string | undefined;
            emoji?: {
                name: string;
                id?: string | null | undefined;
                animated?: boolean | null | undefined;
            } | null | undefined;
            assets?: {
                large_image?: string | undefined;
                large_text?: string | undefined;
                large_url?: string | undefined;
                small_image?: string | undefined;
                small_text?: string | undefined;
                small_url?: string | undefined;
            } | undefined;
            timestamps?: {
                start?: number | undefined;
                end?: number | undefined;
            } | undefined;
            party?: {
                id?: string | undefined;
                size?: number[] | undefined;
                privacy?: number | undefined;
            } | undefined;
            secrets?: {
                join?: string | undefined;
                match?: string | undefined;
            } | undefined;
            sync_id?: string | undefined;
            created_at?: number | undefined;
            instance?: boolean | undefined;
            metadata?: {} | undefined;
            platform?: string | undefined;
            supported_platforms?: string[] | undefined;
            buttons?: string[] | undefined;
            hangStatus?: string | undefined;
        } | null | undefined;
    }>>;
}, "strip", zod.ZodTypeAny, {
    type: number;
    user: {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        flags: number;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        avatar_decoration_data?: {
            asset: string;
            skuId?: string | undefined;
            expiresAt?: number | undefined;
        } | null | undefined;
        premium_type?: number | null | undefined;
    };
    presence?: {
        status: string;
        activity?: {
            name: string;
            type?: number | undefined;
            flags?: number | undefined;
            url?: string | null | undefined;
            session_id?: string | undefined;
            application_id?: string | undefined;
            status_display_type?: number | undefined;
            state?: string | undefined;
            state_url?: string | undefined;
            details?: string | undefined;
            details_url?: string | undefined;
            emoji?: {
                name: string;
                id?: string | null | undefined;
                animated?: boolean | null | undefined;
            } | null | undefined;
            assets?: {
                large_image?: string | undefined;
                large_text?: string | undefined;
                large_url?: string | undefined;
                small_image?: string | undefined;
                small_text?: string | undefined;
                small_url?: string | undefined;
            } | undefined;
            timestamps?: {
                start?: number | undefined;
                end?: number | undefined;
            } | undefined;
            party?: {
                id?: string | undefined;
                size?: number[] | undefined;
                privacy?: number | undefined;
            } | undefined;
            secrets?: {
                join?: string | undefined;
                match?: string | undefined;
            } | undefined;
            sync_id?: string | undefined;
            created_at?: number | undefined;
            instance?: boolean | undefined;
            metadata?: {} | undefined;
            platform?: string | undefined;
            supported_platforms?: string[] | undefined;
            buttons?: string[] | undefined;
            hangStatus?: string | undefined;
        } | null | undefined;
    } | undefined;
}, {
    type: number;
    user: {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        flags: number;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        avatar_decoration_data?: {
            asset: string;
            skuId?: string | undefined;
            expiresAt?: number | undefined;
        } | null | undefined;
        premium_type?: number | null | undefined;
    };
    presence?: {
        status: string;
        activity?: {
            name: string;
            type?: number | undefined;
            flags?: number | undefined;
            url?: string | null | undefined;
            session_id?: string | undefined;
            application_id?: string | undefined;
            status_display_type?: number | undefined;
            state?: string | undefined;
            state_url?: string | undefined;
            details?: string | undefined;
            details_url?: string | undefined;
            emoji?: {
                name: string;
                id?: string | null | undefined;
                animated?: boolean | null | undefined;
            } | null | undefined;
            assets?: {
                large_image?: string | undefined;
                large_text?: string | undefined;
                large_url?: string | undefined;
                small_image?: string | undefined;
                small_text?: string | undefined;
                small_url?: string | undefined;
            } | undefined;
            timestamps?: {
                start?: number | undefined;
                end?: number | undefined;
            } | undefined;
            party?: {
                id?: string | undefined;
                size?: number[] | undefined;
                privacy?: number | undefined;
            } | undefined;
            secrets?: {
                join?: string | undefined;
                match?: string | undefined;
            } | undefined;
            sync_id?: string | undefined;
            created_at?: number | undefined;
            instance?: boolean | undefined;
            metadata?: {} | undefined;
            platform?: string | undefined;
            supported_platforms?: string[] | undefined;
            buttons?: string[] | undefined;
            hangStatus?: string | undefined;
        } | null | undefined;
    } | undefined;
}>;
export declare const User: zod.ZodObject<{
    id: zod.ZodString;
    username: zod.ZodString;
    discriminator: zod.ZodString;
    global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
        asset: zod.ZodString;
        sku_id: zod.ZodOptional<zod.ZodString>;
    }, "strip", zod.ZodTypeAny, {
        asset: string;
        sku_id?: string | undefined;
    }, {
        asset: string;
        sku_id?: string | undefined;
    }>>;
    bot: zod.ZodBoolean;
    flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
}, "strip", zod.ZodTypeAny, {
    username: string;
    discriminator: string;
    id: string;
    bot: boolean;
    avatar_decoration_data: {
        asset: string;
        sku_id?: string | undefined;
    } | null;
    avatar?: string | null | undefined;
    global_name?: string | null | undefined;
    flags?: number | null | undefined;
    premium_type?: number | null | undefined;
}, {
    username: string;
    discriminator: string;
    id: string;
    bot: boolean;
    avatar_decoration_data: {
        asset: string;
        sku_id?: string | undefined;
    } | null;
    avatar?: string | null | undefined;
    global_name?: string | null | undefined;
    flags?: number | null | undefined;
    premium_type?: number | null | undefined;
}>;
export declare const GuildMember: zod.ZodObject<{
    user: zod.ZodObject<{
        id: zod.ZodString;
        username: zod.ZodString;
        discriminator: zod.ZodString;
        global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
            asset: zod.ZodString;
            sku_id: zod.ZodOptional<zod.ZodString>;
        }, "strip", zod.ZodTypeAny, {
            asset: string;
            sku_id?: string | undefined;
        }, {
            asset: string;
            sku_id?: string | undefined;
        }>>;
        bot: zod.ZodBoolean;
        flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    }, "strip", zod.ZodTypeAny, {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    }, {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    }>;
    nick: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    roles: zod.ZodArray<zod.ZodString, "many">;
    joined_at: zod.ZodString;
    deaf: zod.ZodBoolean;
    mute: zod.ZodBoolean;
}, "strip", zod.ZodTypeAny, {
    user: {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    };
    roles: string[];
    joined_at: string;
    deaf: boolean;
    mute: boolean;
    nick?: string | null | undefined;
}, {
    user: {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    };
    roles: string[];
    joined_at: string;
    deaf: boolean;
    mute: boolean;
    nick?: string | null | undefined;
}>;
export declare const GuildMemberRPC: zod.ZodObject<{
    user_id: zod.ZodString;
    nick: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    guild_id: zod.ZodString;
    avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    avatar_decoration_data: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        asset: zod.ZodString;
        sku_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    }, "strip", zod.ZodTypeAny, {
        asset: string;
        sku_id?: string | null | undefined;
    }, {
        asset: string;
        sku_id?: string | null | undefined;
    }>>>;
    color_string: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
}, "strip", zod.ZodTypeAny, {
    user_id: string;
    guild_id: string;
    avatar?: string | null | undefined;
    avatar_decoration_data?: {
        asset: string;
        sku_id?: string | null | undefined;
    } | null | undefined;
    nick?: string | null | undefined;
    color_string?: string | null | undefined;
}, {
    user_id: string;
    guild_id: string;
    avatar?: string | null | undefined;
    avatar_decoration_data?: {
        asset: string;
        sku_id?: string | null | undefined;
    } | null | undefined;
    nick?: string | null | undefined;
    color_string?: string | null | undefined;
}>;
export declare const Emoji: zod.ZodObject<{
    id: zod.ZodString;
    name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    roles: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>>;
    user: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        id: zod.ZodString;
        username: zod.ZodString;
        discriminator: zod.ZodString;
        global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
            asset: zod.ZodString;
            sku_id: zod.ZodOptional<zod.ZodString>;
        }, "strip", zod.ZodTypeAny, {
            asset: string;
            sku_id?: string | undefined;
        }, {
            asset: string;
            sku_id?: string | undefined;
        }>>;
        bot: zod.ZodBoolean;
        flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    }, "strip", zod.ZodTypeAny, {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    }, {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    }>>>;
    require_colons: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    managed: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    animated: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    available: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
}, "strip", zod.ZodTypeAny, {
    id: string;
    user?: {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    } | null | undefined;
    name?: string | null | undefined;
    animated?: boolean | null | undefined;
    roles?: string[] | null | undefined;
    require_colons?: boolean | null | undefined;
    managed?: boolean | null | undefined;
    available?: boolean | null | undefined;
}, {
    id: string;
    user?: {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    } | null | undefined;
    name?: string | null | undefined;
    animated?: boolean | null | undefined;
    roles?: string[] | null | undefined;
    require_colons?: boolean | null | undefined;
    managed?: boolean | null | undefined;
    available?: boolean | null | undefined;
}>;
export declare const VoiceState: zod.ZodObject<{
    mute: zod.ZodBoolean;
    deaf: zod.ZodBoolean;
    self_mute: zod.ZodBoolean;
    self_deaf: zod.ZodBoolean;
    suppress: zod.ZodBoolean;
}, "strip", zod.ZodTypeAny, {
    deaf: boolean;
    mute: boolean;
    self_mute: boolean;
    self_deaf: boolean;
    suppress: boolean;
}, {
    deaf: boolean;
    mute: boolean;
    self_mute: boolean;
    self_deaf: boolean;
    suppress: boolean;
}>;
export declare const UserVoiceState: zod.ZodObject<{
    mute: zod.ZodBoolean;
    nick: zod.ZodString;
    user: zod.ZodObject<{
        id: zod.ZodString;
        username: zod.ZodString;
        discriminator: zod.ZodString;
        global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
            asset: zod.ZodString;
            sku_id: zod.ZodOptional<zod.ZodString>;
        }, "strip", zod.ZodTypeAny, {
            asset: string;
            sku_id?: string | undefined;
        }, {
            asset: string;
            sku_id?: string | undefined;
        }>>;
        bot: zod.ZodBoolean;
        flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    }, "strip", zod.ZodTypeAny, {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    }, {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    }>;
    voice_state: zod.ZodObject<{
        mute: zod.ZodBoolean;
        deaf: zod.ZodBoolean;
        self_mute: zod.ZodBoolean;
        self_deaf: zod.ZodBoolean;
        suppress: zod.ZodBoolean;
    }, "strip", zod.ZodTypeAny, {
        deaf: boolean;
        mute: boolean;
        self_mute: boolean;
        self_deaf: boolean;
        suppress: boolean;
    }, {
        deaf: boolean;
        mute: boolean;
        self_mute: boolean;
        self_deaf: boolean;
        suppress: boolean;
    }>;
    volume: zod.ZodNumber;
}, "strip", zod.ZodTypeAny, {
    user: {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    };
    nick: string;
    mute: boolean;
    voice_state: {
        deaf: boolean;
        mute: boolean;
        self_mute: boolean;
        self_deaf: boolean;
        suppress: boolean;
    };
    volume: number;
}, {
    user: {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    };
    nick: string;
    mute: boolean;
    voice_state: {
        deaf: boolean;
        mute: boolean;
        self_mute: boolean;
        self_deaf: boolean;
        suppress: boolean;
    };
    volume: number;
}>;
export declare const StatusObject: {
    readonly UNHANDLED: -1;
    readonly IDLE: "idle";
    readonly DND: "dnd";
    readonly ONLINE: "online";
    readonly OFFLINE: "offline";
};
export declare const Status: zod.ZodEffects<zod.ZodType<-1 | "idle" | "dnd" | "online" | "offline", zod.ZodTypeDef, -1 | "idle" | "dnd" | "online" | "offline">, -1 | "idle" | "dnd" | "online" | "offline", unknown>;
export declare const Activity: zod.ZodObject<{
    name: zod.ZodString;
    type: zod.ZodNumber;
    url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    created_at: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    timestamps: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        start: zod.ZodOptional<zod.ZodNumber>;
        end: zod.ZodOptional<zod.ZodNumber>;
    }, "strip", zod.ZodTypeAny, {
        start?: number | undefined;
        end?: number | undefined;
    }, {
        start?: number | undefined;
        end?: number | undefined;
    }>>>;
    application_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    details: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    details_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    state: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    state_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    emoji: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        id: zod.ZodString;
        name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        roles: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>>;
        user: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>>>;
        require_colons: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        managed: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        animated: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        available: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    }, "strip", zod.ZodTypeAny, {
        id: string;
        user?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        name?: string | null | undefined;
        animated?: boolean | null | undefined;
        roles?: string[] | null | undefined;
        require_colons?: boolean | null | undefined;
        managed?: boolean | null | undefined;
        available?: boolean | null | undefined;
    }, {
        id: string;
        user?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        name?: string | null | undefined;
        animated?: boolean | null | undefined;
        roles?: string[] | null | undefined;
        require_colons?: boolean | null | undefined;
        managed?: boolean | null | undefined;
        available?: boolean | null | undefined;
    }>>>;
    party: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        size: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodNumber, "many">>>;
    }, "strip", zod.ZodTypeAny, {
        id?: string | null | undefined;
        size?: number[] | null | undefined;
    }, {
        id?: string | null | undefined;
        size?: number[] | null | undefined;
    }>>>;
    assets: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        large_image: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
        large_text: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
        large_url: zod.ZodOptional<zod.ZodNullable<zod.ZodOptional<zod.ZodString>>>;
        small_image: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
        small_text: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
        small_url: zod.ZodOptional<zod.ZodNullable<zod.ZodOptional<zod.ZodString>>>;
    }, "strip", zod.ZodTypeAny, {
        large_image?: string | null | undefined;
        large_text?: string | null | undefined;
        large_url?: string | null | undefined;
        small_image?: string | null | undefined;
        small_text?: string | null | undefined;
        small_url?: string | null | undefined;
    }, {
        large_image?: string | null | undefined;
        large_text?: string | null | undefined;
        large_url?: string | null | undefined;
        small_image?: string | null | undefined;
        small_text?: string | null | undefined;
        small_url?: string | null | undefined;
    }>>>;
    secrets: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        join: zod.ZodOptional<zod.ZodString>;
        match: zod.ZodOptional<zod.ZodString>;
    }, "strip", zod.ZodTypeAny, {
        join?: string | undefined;
        match?: string | undefined;
    }, {
        join?: string | undefined;
        match?: string | undefined;
    }>>>;
    instance: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
}, "strip", zod.ZodTypeAny, {
    type: number;
    name: string;
    flags?: number | null | undefined;
    url?: string | null | undefined;
    application_id?: string | null | undefined;
    state?: string | null | undefined;
    state_url?: string | null | undefined;
    details?: string | null | undefined;
    details_url?: string | null | undefined;
    emoji?: {
        id: string;
        user?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        name?: string | null | undefined;
        animated?: boolean | null | undefined;
        roles?: string[] | null | undefined;
        require_colons?: boolean | null | undefined;
        managed?: boolean | null | undefined;
        available?: boolean | null | undefined;
    } | null | undefined;
    assets?: {
        large_image?: string | null | undefined;
        large_text?: string | null | undefined;
        large_url?: string | null | undefined;
        small_image?: string | null | undefined;
        small_text?: string | null | undefined;
        small_url?: string | null | undefined;
    } | null | undefined;
    timestamps?: {
        start?: number | undefined;
        end?: number | undefined;
    } | null | undefined;
    party?: {
        id?: string | null | undefined;
        size?: number[] | null | undefined;
    } | null | undefined;
    secrets?: {
        join?: string | undefined;
        match?: string | undefined;
    } | null | undefined;
    created_at?: number | null | undefined;
    instance?: boolean | null | undefined;
}, {
    type: number;
    name: string;
    flags?: number | null | undefined;
    url?: string | null | undefined;
    application_id?: string | null | undefined;
    state?: string | null | undefined;
    state_url?: string | null | undefined;
    details?: string | null | undefined;
    details_url?: string | null | undefined;
    emoji?: {
        id: string;
        user?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        name?: string | null | undefined;
        animated?: boolean | null | undefined;
        roles?: string[] | null | undefined;
        require_colons?: boolean | null | undefined;
        managed?: boolean | null | undefined;
        available?: boolean | null | undefined;
    } | null | undefined;
    assets?: {
        large_image?: string | null | undefined;
        large_text?: string | null | undefined;
        large_url?: string | null | undefined;
        small_image?: string | null | undefined;
        small_text?: string | null | undefined;
        small_url?: string | null | undefined;
    } | null | undefined;
    timestamps?: {
        start?: number | undefined;
        end?: number | undefined;
    } | null | undefined;
    party?: {
        id?: string | null | undefined;
        size?: number[] | null | undefined;
    } | null | undefined;
    secrets?: {
        join?: string | undefined;
        match?: string | undefined;
    } | null | undefined;
    created_at?: number | null | undefined;
    instance?: boolean | null | undefined;
}>;
export declare const PermissionOverwriteTypeObject: {
    readonly UNHANDLED: -1;
    readonly ROLE: 0;
    readonly MEMBER: 1;
};
export declare const PermissionOverwrite: zod.ZodObject<{
    id: zod.ZodString;
    type: zod.ZodEffects<zod.ZodType<0 | 1 | -1, zod.ZodTypeDef, 0 | 1 | -1>, 0 | 1 | -1, unknown>;
    allow: zod.ZodString;
    deny: zod.ZodString;
}, "strip", zod.ZodTypeAny, {
    type: 0 | 1 | -1;
    id: string;
    allow: string;
    deny: string;
}, {
    id: string;
    allow: string;
    deny: string;
    type?: unknown;
}>;
export declare const ChannelTypesObject: {
    readonly UNHANDLED: -1;
    readonly DM: 1;
    readonly GROUP_DM: 3;
    readonly GUILD_TEXT: 0;
    readonly GUILD_VOICE: 2;
    readonly GUILD_CATEGORY: 4;
    readonly GUILD_ANNOUNCEMENT: 5;
    readonly GUILD_STORE: 6;
    readonly ANNOUNCEMENT_THREAD: 10;
    readonly PUBLIC_THREAD: 11;
    readonly PRIVATE_THREAD: 12;
    readonly GUILD_STAGE_VOICE: 13;
    readonly GUILD_DIRECTORY: 14;
    readonly GUILD_FORUM: 15;
};
export declare const Channel: zod.ZodObject<{
    id: zod.ZodString;
    type: zod.ZodEffects<zod.ZodType<0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1, zod.ZodTypeDef, 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1>, 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1, unknown>;
    guild_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    position: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    permission_overwrites: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
        id: zod.ZodString;
        type: zod.ZodEffects<zod.ZodType<0 | 1 | -1, zod.ZodTypeDef, 0 | 1 | -1>, 0 | 1 | -1, unknown>;
        allow: zod.ZodString;
        deny: zod.ZodString;
    }, "strip", zod.ZodTypeAny, {
        type: 0 | 1 | -1;
        id: string;
        allow: string;
        deny: string;
    }, {
        id: string;
        allow: string;
        deny: string;
        type?: unknown;
    }>, "many">>>;
    name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    topic: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    nsfw: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    last_message_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    bitrate: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    user_limit: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    rate_limit_per_user: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    recipients: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
        id: zod.ZodString;
        username: zod.ZodString;
        discriminator: zod.ZodString;
        global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
            asset: zod.ZodString;
            sku_id: zod.ZodOptional<zod.ZodString>;
        }, "strip", zod.ZodTypeAny, {
            asset: string;
            sku_id?: string | undefined;
        }, {
            asset: string;
            sku_id?: string | undefined;
        }>>;
        bot: zod.ZodBoolean;
        flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    }, "strip", zod.ZodTypeAny, {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    }, {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    }>, "many">>>;
    icon: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    owner_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    application_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    parent_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    last_pin_timestamp: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
}, "strip", zod.ZodTypeAny, {
    type: 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1;
    id: string;
    icon?: string | null | undefined;
    name?: string | null | undefined;
    application_id?: string | null | undefined;
    guild_id?: string | null | undefined;
    position?: number | null | undefined;
    permission_overwrites?: {
        type: 0 | 1 | -1;
        id: string;
        allow: string;
        deny: string;
    }[] | null | undefined;
    topic?: string | null | undefined;
    nsfw?: boolean | null | undefined;
    last_message_id?: string | null | undefined;
    bitrate?: number | null | undefined;
    user_limit?: number | null | undefined;
    rate_limit_per_user?: number | null | undefined;
    recipients?: {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    }[] | null | undefined;
    owner_id?: string | null | undefined;
    parent_id?: string | null | undefined;
    last_pin_timestamp?: string | null | undefined;
}, {
    id: string;
    type?: unknown;
    icon?: string | null | undefined;
    name?: string | null | undefined;
    application_id?: string | null | undefined;
    guild_id?: string | null | undefined;
    position?: number | null | undefined;
    permission_overwrites?: {
        id: string;
        allow: string;
        deny: string;
        type?: unknown;
    }[] | null | undefined;
    topic?: string | null | undefined;
    nsfw?: boolean | null | undefined;
    last_message_id?: string | null | undefined;
    bitrate?: number | null | undefined;
    user_limit?: number | null | undefined;
    rate_limit_per_user?: number | null | undefined;
    recipients?: {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    }[] | null | undefined;
    owner_id?: string | null | undefined;
    parent_id?: string | null | undefined;
    last_pin_timestamp?: string | null | undefined;
}>;
export declare const PresenceUpdate: zod.ZodObject<{
    user: zod.ZodObject<{
        id: zod.ZodString;
        username: zod.ZodString;
        discriminator: zod.ZodString;
        global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
            asset: zod.ZodString;
            sku_id: zod.ZodOptional<zod.ZodString>;
        }, "strip", zod.ZodTypeAny, {
            asset: string;
            sku_id?: string | undefined;
        }, {
            asset: string;
            sku_id?: string | undefined;
        }>>;
        bot: zod.ZodBoolean;
        flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    }, "strip", zod.ZodTypeAny, {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    }, {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    }>;
    guild_id: zod.ZodString;
    status: zod.ZodEffects<zod.ZodType<-1 | "idle" | "dnd" | "online" | "offline", zod.ZodTypeDef, -1 | "idle" | "dnd" | "online" | "offline">, -1 | "idle" | "dnd" | "online" | "offline", unknown>;
    activities: zod.ZodArray<zod.ZodObject<{
        name: zod.ZodString;
        type: zod.ZodNumber;
        url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        created_at: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        timestamps: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            start: zod.ZodOptional<zod.ZodNumber>;
            end: zod.ZodOptional<zod.ZodNumber>;
        }, "strip", zod.ZodTypeAny, {
            start?: number | undefined;
            end?: number | undefined;
        }, {
            start?: number | undefined;
            end?: number | undefined;
        }>>>;
        application_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        details: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        details_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        state: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        state_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        emoji: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            id: zod.ZodString;
            name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            roles: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>>;
            user: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                id: zod.ZodString;
                username: zod.ZodString;
                discriminator: zod.ZodString;
                global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                    asset: zod.ZodString;
                    sku_id: zod.ZodOptional<zod.ZodString>;
                }, "strip", zod.ZodTypeAny, {
                    asset: string;
                    sku_id?: string | undefined;
                }, {
                    asset: string;
                    sku_id?: string | undefined;
                }>>;
                bot: zod.ZodBoolean;
                flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "strip", zod.ZodTypeAny, {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            }, {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            }>>>;
            require_colons: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
            managed: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
            animated: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
            available: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        }, "strip", zod.ZodTypeAny, {
            id: string;
            user?: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            } | null | undefined;
            name?: string | null | undefined;
            animated?: boolean | null | undefined;
            roles?: string[] | null | undefined;
            require_colons?: boolean | null | undefined;
            managed?: boolean | null | undefined;
            available?: boolean | null | undefined;
        }, {
            id: string;
            user?: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            } | null | undefined;
            name?: string | null | undefined;
            animated?: boolean | null | undefined;
            roles?: string[] | null | undefined;
            require_colons?: boolean | null | undefined;
            managed?: boolean | null | undefined;
            available?: boolean | null | undefined;
        }>>>;
        party: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            size: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodNumber, "many">>>;
        }, "strip", zod.ZodTypeAny, {
            id?: string | null | undefined;
            size?: number[] | null | undefined;
        }, {
            id?: string | null | undefined;
            size?: number[] | null | undefined;
        }>>>;
        assets: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            large_image: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
            large_text: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
            large_url: zod.ZodOptional<zod.ZodNullable<zod.ZodOptional<zod.ZodString>>>;
            small_image: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
            small_text: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
            small_url: zod.ZodOptional<zod.ZodNullable<zod.ZodOptional<zod.ZodString>>>;
        }, "strip", zod.ZodTypeAny, {
            large_image?: string | null | undefined;
            large_text?: string | null | undefined;
            large_url?: string | null | undefined;
            small_image?: string | null | undefined;
            small_text?: string | null | undefined;
            small_url?: string | null | undefined;
        }, {
            large_image?: string | null | undefined;
            large_text?: string | null | undefined;
            large_url?: string | null | undefined;
            small_image?: string | null | undefined;
            small_text?: string | null | undefined;
            small_url?: string | null | undefined;
        }>>>;
        secrets: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            join: zod.ZodOptional<zod.ZodString>;
            match: zod.ZodOptional<zod.ZodString>;
        }, "strip", zod.ZodTypeAny, {
            join?: string | undefined;
            match?: string | undefined;
        }, {
            join?: string | undefined;
            match?: string | undefined;
        }>>>;
        instance: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    }, "strip", zod.ZodTypeAny, {
        type: number;
        name: string;
        flags?: number | null | undefined;
        url?: string | null | undefined;
        application_id?: string | null | undefined;
        state?: string | null | undefined;
        state_url?: string | null | undefined;
        details?: string | null | undefined;
        details_url?: string | null | undefined;
        emoji?: {
            id: string;
            user?: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            } | null | undefined;
            name?: string | null | undefined;
            animated?: boolean | null | undefined;
            roles?: string[] | null | undefined;
            require_colons?: boolean | null | undefined;
            managed?: boolean | null | undefined;
            available?: boolean | null | undefined;
        } | null | undefined;
        assets?: {
            large_image?: string | null | undefined;
            large_text?: string | null | undefined;
            large_url?: string | null | undefined;
            small_image?: string | null | undefined;
            small_text?: string | null | undefined;
            small_url?: string | null | undefined;
        } | null | undefined;
        timestamps?: {
            start?: number | undefined;
            end?: number | undefined;
        } | null | undefined;
        party?: {
            id?: string | null | undefined;
            size?: number[] | null | undefined;
        } | null | undefined;
        secrets?: {
            join?: string | undefined;
            match?: string | undefined;
        } | null | undefined;
        created_at?: number | null | undefined;
        instance?: boolean | null | undefined;
    }, {
        type: number;
        name: string;
        flags?: number | null | undefined;
        url?: string | null | undefined;
        application_id?: string | null | undefined;
        state?: string | null | undefined;
        state_url?: string | null | undefined;
        details?: string | null | undefined;
        details_url?: string | null | undefined;
        emoji?: {
            id: string;
            user?: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            } | null | undefined;
            name?: string | null | undefined;
            animated?: boolean | null | undefined;
            roles?: string[] | null | undefined;
            require_colons?: boolean | null | undefined;
            managed?: boolean | null | undefined;
            available?: boolean | null | undefined;
        } | null | undefined;
        assets?: {
            large_image?: string | null | undefined;
            large_text?: string | null | undefined;
            large_url?: string | null | undefined;
            small_image?: string | null | undefined;
            small_text?: string | null | undefined;
            small_url?: string | null | undefined;
        } | null | undefined;
        timestamps?: {
            start?: number | undefined;
            end?: number | undefined;
        } | null | undefined;
        party?: {
            id?: string | null | undefined;
            size?: number[] | null | undefined;
        } | null | undefined;
        secrets?: {
            join?: string | undefined;
            match?: string | undefined;
        } | null | undefined;
        created_at?: number | null | undefined;
        instance?: boolean | null | undefined;
    }>, "many">;
    client_status: zod.ZodObject<{
        desktop: zod.ZodOptional<zod.ZodEffects<zod.ZodType<-1 | "idle" | "dnd" | "online" | "offline", zod.ZodTypeDef, -1 | "idle" | "dnd" | "online" | "offline">, -1 | "idle" | "dnd" | "online" | "offline", unknown>>;
        mobile: zod.ZodOptional<zod.ZodEffects<zod.ZodType<-1 | "idle" | "dnd" | "online" | "offline", zod.ZodTypeDef, -1 | "idle" | "dnd" | "online" | "offline">, -1 | "idle" | "dnd" | "online" | "offline", unknown>>;
        web: zod.ZodOptional<zod.ZodEffects<zod.ZodType<-1 | "idle" | "dnd" | "online" | "offline", zod.ZodTypeDef, -1 | "idle" | "dnd" | "online" | "offline">, -1 | "idle" | "dnd" | "online" | "offline", unknown>>;
    }, "strip", zod.ZodTypeAny, {
        mobile?: (-1 | "idle" | "dnd" | "online" | "offline") | undefined;
        desktop?: (-1 | "idle" | "dnd" | "online" | "offline") | undefined;
        web?: (-1 | "idle" | "dnd" | "online" | "offline") | undefined;
    }, {
        mobile?: unknown;
        desktop?: unknown;
        web?: unknown;
    }>;
}, "strip", zod.ZodTypeAny, {
    status: -1 | "idle" | "dnd" | "online" | "offline";
    user: {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    };
    guild_id: string;
    activities: {
        type: number;
        name: string;
        flags?: number | null | undefined;
        url?: string | null | undefined;
        application_id?: string | null | undefined;
        state?: string | null | undefined;
        state_url?: string | null | undefined;
        details?: string | null | undefined;
        details_url?: string | null | undefined;
        emoji?: {
            id: string;
            user?: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            } | null | undefined;
            name?: string | null | undefined;
            animated?: boolean | null | undefined;
            roles?: string[] | null | undefined;
            require_colons?: boolean | null | undefined;
            managed?: boolean | null | undefined;
            available?: boolean | null | undefined;
        } | null | undefined;
        assets?: {
            large_image?: string | null | undefined;
            large_text?: string | null | undefined;
            large_url?: string | null | undefined;
            small_image?: string | null | undefined;
            small_text?: string | null | undefined;
            small_url?: string | null | undefined;
        } | null | undefined;
        timestamps?: {
            start?: number | undefined;
            end?: number | undefined;
        } | null | undefined;
        party?: {
            id?: string | null | undefined;
            size?: number[] | null | undefined;
        } | null | undefined;
        secrets?: {
            join?: string | undefined;
            match?: string | undefined;
        } | null | undefined;
        created_at?: number | null | undefined;
        instance?: boolean | null | undefined;
    }[];
    client_status: {
        mobile?: (-1 | "idle" | "dnd" | "online" | "offline") | undefined;
        desktop?: (-1 | "idle" | "dnd" | "online" | "offline") | undefined;
        web?: (-1 | "idle" | "dnd" | "online" | "offline") | undefined;
    };
}, {
    user: {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    };
    guild_id: string;
    activities: {
        type: number;
        name: string;
        flags?: number | null | undefined;
        url?: string | null | undefined;
        application_id?: string | null | undefined;
        state?: string | null | undefined;
        state_url?: string | null | undefined;
        details?: string | null | undefined;
        details_url?: string | null | undefined;
        emoji?: {
            id: string;
            user?: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            } | null | undefined;
            name?: string | null | undefined;
            animated?: boolean | null | undefined;
            roles?: string[] | null | undefined;
            require_colons?: boolean | null | undefined;
            managed?: boolean | null | undefined;
            available?: boolean | null | undefined;
        } | null | undefined;
        assets?: {
            large_image?: string | null | undefined;
            large_text?: string | null | undefined;
            large_url?: string | null | undefined;
            small_image?: string | null | undefined;
            small_text?: string | null | undefined;
            small_url?: string | null | undefined;
        } | null | undefined;
        timestamps?: {
            start?: number | undefined;
            end?: number | undefined;
        } | null | undefined;
        party?: {
            id?: string | null | undefined;
            size?: number[] | null | undefined;
        } | null | undefined;
        secrets?: {
            join?: string | undefined;
            match?: string | undefined;
        } | null | undefined;
        created_at?: number | null | undefined;
        instance?: boolean | null | undefined;
    }[];
    client_status: {
        mobile?: unknown;
        desktop?: unknown;
        web?: unknown;
    };
    status?: unknown;
}>;
export declare const Role: zod.ZodObject<{
    id: zod.ZodString;
    name: zod.ZodString;
    color: zod.ZodNumber;
    hoist: zod.ZodBoolean;
    position: zod.ZodNumber;
    permissions: zod.ZodString;
    managed: zod.ZodBoolean;
    mentionable: zod.ZodBoolean;
}, "strip", zod.ZodTypeAny, {
    id: string;
    name: string;
    managed: boolean;
    position: number;
    color: number;
    hoist: boolean;
    permissions: string;
    mentionable: boolean;
}, {
    id: string;
    name: string;
    managed: boolean;
    position: number;
    color: number;
    hoist: boolean;
    permissions: string;
    mentionable: boolean;
}>;
export declare const Guild: zod.ZodObject<{
    id: zod.ZodString;
    name: zod.ZodString;
    owner_id: zod.ZodString;
    icon: zod.ZodNullable<zod.ZodString>;
    icon_hash: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    splash: zod.ZodNullable<zod.ZodString>;
    discovery_splash: zod.ZodNullable<zod.ZodString>;
    owner: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    permissions: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    region: zod.ZodString;
    afk_channel_id: zod.ZodNullable<zod.ZodString>;
    afk_timeout: zod.ZodNumber;
    widget_enabled: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    widget_channel_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    verification_level: zod.ZodNumber;
    default_message_notifications: zod.ZodNumber;
    explicit_content_filter: zod.ZodNumber;
    roles: zod.ZodArray<zod.ZodObject<{
        id: zod.ZodString;
        name: zod.ZodString;
        color: zod.ZodNumber;
        hoist: zod.ZodBoolean;
        position: zod.ZodNumber;
        permissions: zod.ZodString;
        managed: zod.ZodBoolean;
        mentionable: zod.ZodBoolean;
    }, "strip", zod.ZodTypeAny, {
        id: string;
        name: string;
        managed: boolean;
        position: number;
        color: number;
        hoist: boolean;
        permissions: string;
        mentionable: boolean;
    }, {
        id: string;
        name: string;
        managed: boolean;
        position: number;
        color: number;
        hoist: boolean;
        permissions: string;
        mentionable: boolean;
    }>, "many">;
    emojis: zod.ZodArray<zod.ZodObject<{
        id: zod.ZodString;
        name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        roles: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>>;
        user: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>>>;
        require_colons: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        managed: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        animated: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        available: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    }, "strip", zod.ZodTypeAny, {
        id: string;
        user?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        name?: string | null | undefined;
        animated?: boolean | null | undefined;
        roles?: string[] | null | undefined;
        require_colons?: boolean | null | undefined;
        managed?: boolean | null | undefined;
        available?: boolean | null | undefined;
    }, {
        id: string;
        user?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        name?: string | null | undefined;
        animated?: boolean | null | undefined;
        roles?: string[] | null | undefined;
        require_colons?: boolean | null | undefined;
        managed?: boolean | null | undefined;
        available?: boolean | null | undefined;
    }>, "many">;
    features: zod.ZodArray<zod.ZodString, "many">;
    mfa_level: zod.ZodNumber;
    application_id: zod.ZodNullable<zod.ZodString>;
    system_channel_id: zod.ZodNullable<zod.ZodString>;
    system_channel_flags: zod.ZodNumber;
    rules_channel_id: zod.ZodNullable<zod.ZodString>;
    joined_at: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    large: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    unavailable: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    member_count: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    voice_states: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
        mute: zod.ZodBoolean;
        deaf: zod.ZodBoolean;
        self_mute: zod.ZodBoolean;
        self_deaf: zod.ZodBoolean;
        suppress: zod.ZodBoolean;
    }, "strip", zod.ZodTypeAny, {
        deaf: boolean;
        mute: boolean;
        self_mute: boolean;
        self_deaf: boolean;
        suppress: boolean;
    }, {
        deaf: boolean;
        mute: boolean;
        self_mute: boolean;
        self_deaf: boolean;
        suppress: boolean;
    }>, "many">>>;
    members: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
        user: zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>;
        nick: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        roles: zod.ZodArray<zod.ZodString, "many">;
        joined_at: zod.ZodString;
        deaf: zod.ZodBoolean;
        mute: zod.ZodBoolean;
    }, "strip", zod.ZodTypeAny, {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        roles: string[];
        joined_at: string;
        deaf: boolean;
        mute: boolean;
        nick?: string | null | undefined;
    }, {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        roles: string[];
        joined_at: string;
        deaf: boolean;
        mute: boolean;
        nick?: string | null | undefined;
    }>, "many">>>;
    channels: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
        id: zod.ZodString;
        type: zod.ZodEffects<zod.ZodType<0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1, zod.ZodTypeDef, 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1>, 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1, unknown>;
        guild_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        position: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        permission_overwrites: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
            id: zod.ZodString;
            type: zod.ZodEffects<zod.ZodType<0 | 1 | -1, zod.ZodTypeDef, 0 | 1 | -1>, 0 | 1 | -1, unknown>;
            allow: zod.ZodString;
            deny: zod.ZodString;
        }, "strip", zod.ZodTypeAny, {
            type: 0 | 1 | -1;
            id: string;
            allow: string;
            deny: string;
        }, {
            id: string;
            allow: string;
            deny: string;
            type?: unknown;
        }>, "many">>>;
        name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        topic: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        nsfw: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        last_message_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        bitrate: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        user_limit: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        rate_limit_per_user: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        recipients: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>, "many">>>;
        icon: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        owner_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        application_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        parent_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        last_pin_timestamp: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    }, "strip", zod.ZodTypeAny, {
        type: 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1;
        id: string;
        icon?: string | null | undefined;
        name?: string | null | undefined;
        application_id?: string | null | undefined;
        guild_id?: string | null | undefined;
        position?: number | null | undefined;
        permission_overwrites?: {
            type: 0 | 1 | -1;
            id: string;
            allow: string;
            deny: string;
        }[] | null | undefined;
        topic?: string | null | undefined;
        nsfw?: boolean | null | undefined;
        last_message_id?: string | null | undefined;
        bitrate?: number | null | undefined;
        user_limit?: number | null | undefined;
        rate_limit_per_user?: number | null | undefined;
        recipients?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[] | null | undefined;
        owner_id?: string | null | undefined;
        parent_id?: string | null | undefined;
        last_pin_timestamp?: string | null | undefined;
    }, {
        id: string;
        type?: unknown;
        icon?: string | null | undefined;
        name?: string | null | undefined;
        application_id?: string | null | undefined;
        guild_id?: string | null | undefined;
        position?: number | null | undefined;
        permission_overwrites?: {
            id: string;
            allow: string;
            deny: string;
            type?: unknown;
        }[] | null | undefined;
        topic?: string | null | undefined;
        nsfw?: boolean | null | undefined;
        last_message_id?: string | null | undefined;
        bitrate?: number | null | undefined;
        user_limit?: number | null | undefined;
        rate_limit_per_user?: number | null | undefined;
        recipients?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[] | null | undefined;
        owner_id?: string | null | undefined;
        parent_id?: string | null | undefined;
        last_pin_timestamp?: string | null | undefined;
    }>, "many">>>;
    presences: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
        user: zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>;
        guild_id: zod.ZodString;
        status: zod.ZodEffects<zod.ZodType<-1 | "idle" | "dnd" | "online" | "offline", zod.ZodTypeDef, -1 | "idle" | "dnd" | "online" | "offline">, -1 | "idle" | "dnd" | "online" | "offline", unknown>;
        activities: zod.ZodArray<zod.ZodObject<{
            name: zod.ZodString;
            type: zod.ZodNumber;
            url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            created_at: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            timestamps: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                start: zod.ZodOptional<zod.ZodNumber>;
                end: zod.ZodOptional<zod.ZodNumber>;
            }, "strip", zod.ZodTypeAny, {
                start?: number | undefined;
                end?: number | undefined;
            }, {
                start?: number | undefined;
                end?: number | undefined;
            }>>>;
            application_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            details: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            details_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            state: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            state_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            emoji: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                id: zod.ZodString;
                name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                roles: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>>;
                user: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                    id: zod.ZodString;
                    username: zod.ZodString;
                    discriminator: zod.ZodString;
                    global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                        asset: zod.ZodString;
                        sku_id: zod.ZodOptional<zod.ZodString>;
                    }, "strip", zod.ZodTypeAny, {
                        asset: string;
                        sku_id?: string | undefined;
                    }, {
                        asset: string;
                        sku_id?: string | undefined;
                    }>>;
                    bot: zod.ZodBoolean;
                    flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                    premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                }, "strip", zod.ZodTypeAny, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                }, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                }>>>;
                require_colons: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                managed: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                animated: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                available: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
            }, "strip", zod.ZodTypeAny, {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            }, {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            }>>>;
            party: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                size: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodNumber, "many">>>;
            }, "strip", zod.ZodTypeAny, {
                id?: string | null | undefined;
                size?: number[] | null | undefined;
            }, {
                id?: string | null | undefined;
                size?: number[] | null | undefined;
            }>>>;
            assets: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                large_image: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
                large_text: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
                large_url: zod.ZodOptional<zod.ZodNullable<zod.ZodOptional<zod.ZodString>>>;
                small_image: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
                small_text: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
                small_url: zod.ZodOptional<zod.ZodNullable<zod.ZodOptional<zod.ZodString>>>;
            }, "strip", zod.ZodTypeAny, {
                large_image?: string | null | undefined;
                large_text?: string | null | undefined;
                large_url?: string | null | undefined;
                small_image?: string | null | undefined;
                small_text?: string | null | undefined;
                small_url?: string | null | undefined;
            }, {
                large_image?: string | null | undefined;
                large_text?: string | null | undefined;
                large_url?: string | null | undefined;
                small_image?: string | null | undefined;
                small_text?: string | null | undefined;
                small_url?: string | null | undefined;
            }>>>;
            secrets: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                join: zod.ZodOptional<zod.ZodString>;
                match: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                join?: string | undefined;
                match?: string | undefined;
            }, {
                join?: string | undefined;
                match?: string | undefined;
            }>>>;
            instance: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            type: number;
            name: string;
            flags?: number | null | undefined;
            url?: string | null | undefined;
            application_id?: string | null | undefined;
            state?: string | null | undefined;
            state_url?: string | null | undefined;
            details?: string | null | undefined;
            details_url?: string | null | undefined;
            emoji?: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            } | null | undefined;
            assets?: {
                large_image?: string | null | undefined;
                large_text?: string | null | undefined;
                large_url?: string | null | undefined;
                small_image?: string | null | undefined;
                small_text?: string | null | undefined;
                small_url?: string | null | undefined;
            } | null | undefined;
            timestamps?: {
                start?: number | undefined;
                end?: number | undefined;
            } | null | undefined;
            party?: {
                id?: string | null | undefined;
                size?: number[] | null | undefined;
            } | null | undefined;
            secrets?: {
                join?: string | undefined;
                match?: string | undefined;
            } | null | undefined;
            created_at?: number | null | undefined;
            instance?: boolean | null | undefined;
        }, {
            type: number;
            name: string;
            flags?: number | null | undefined;
            url?: string | null | undefined;
            application_id?: string | null | undefined;
            state?: string | null | undefined;
            state_url?: string | null | undefined;
            details?: string | null | undefined;
            details_url?: string | null | undefined;
            emoji?: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            } | null | undefined;
            assets?: {
                large_image?: string | null | undefined;
                large_text?: string | null | undefined;
                large_url?: string | null | undefined;
                small_image?: string | null | undefined;
                small_text?: string | null | undefined;
                small_url?: string | null | undefined;
            } | null | undefined;
            timestamps?: {
                start?: number | undefined;
                end?: number | undefined;
            } | null | undefined;
            party?: {
                id?: string | null | undefined;
                size?: number[] | null | undefined;
            } | null | undefined;
            secrets?: {
                join?: string | undefined;
                match?: string | undefined;
            } | null | undefined;
            created_at?: number | null | undefined;
            instance?: boolean | null | undefined;
        }>, "many">;
        client_status: zod.ZodObject<{
            desktop: zod.ZodOptional<zod.ZodEffects<zod.ZodType<-1 | "idle" | "dnd" | "online" | "offline", zod.ZodTypeDef, -1 | "idle" | "dnd" | "online" | "offline">, -1 | "idle" | "dnd" | "online" | "offline", unknown>>;
            mobile: zod.ZodOptional<zod.ZodEffects<zod.ZodType<-1 | "idle" | "dnd" | "online" | "offline", zod.ZodTypeDef, -1 | "idle" | "dnd" | "online" | "offline">, -1 | "idle" | "dnd" | "online" | "offline", unknown>>;
            web: zod.ZodOptional<zod.ZodEffects<zod.ZodType<-1 | "idle" | "dnd" | "online" | "offline", zod.ZodTypeDef, -1 | "idle" | "dnd" | "online" | "offline">, -1 | "idle" | "dnd" | "online" | "offline", unknown>>;
        }, "strip", zod.ZodTypeAny, {
            mobile?: (-1 | "idle" | "dnd" | "online" | "offline") | undefined;
            desktop?: (-1 | "idle" | "dnd" | "online" | "offline") | undefined;
            web?: (-1 | "idle" | "dnd" | "online" | "offline") | undefined;
        }, {
            mobile?: unknown;
            desktop?: unknown;
            web?: unknown;
        }>;
    }, "strip", zod.ZodTypeAny, {
        status: -1 | "idle" | "dnd" | "online" | "offline";
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        guild_id: string;
        activities: {
            type: number;
            name: string;
            flags?: number | null | undefined;
            url?: string | null | undefined;
            application_id?: string | null | undefined;
            state?: string | null | undefined;
            state_url?: string | null | undefined;
            details?: string | null | undefined;
            details_url?: string | null | undefined;
            emoji?: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            } | null | undefined;
            assets?: {
                large_image?: string | null | undefined;
                large_text?: string | null | undefined;
                large_url?: string | null | undefined;
                small_image?: string | null | undefined;
                small_text?: string | null | undefined;
                small_url?: string | null | undefined;
            } | null | undefined;
            timestamps?: {
                start?: number | undefined;
                end?: number | undefined;
            } | null | undefined;
            party?: {
                id?: string | null | undefined;
                size?: number[] | null | undefined;
            } | null | undefined;
            secrets?: {
                join?: string | undefined;
                match?: string | undefined;
            } | null | undefined;
            created_at?: number | null | undefined;
            instance?: boolean | null | undefined;
        }[];
        client_status: {
            mobile?: (-1 | "idle" | "dnd" | "online" | "offline") | undefined;
            desktop?: (-1 | "idle" | "dnd" | "online" | "offline") | undefined;
            web?: (-1 | "idle" | "dnd" | "online" | "offline") | undefined;
        };
    }, {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        guild_id: string;
        activities: {
            type: number;
            name: string;
            flags?: number | null | undefined;
            url?: string | null | undefined;
            application_id?: string | null | undefined;
            state?: string | null | undefined;
            state_url?: string | null | undefined;
            details?: string | null | undefined;
            details_url?: string | null | undefined;
            emoji?: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            } | null | undefined;
            assets?: {
                large_image?: string | null | undefined;
                large_text?: string | null | undefined;
                large_url?: string | null | undefined;
                small_image?: string | null | undefined;
                small_text?: string | null | undefined;
                small_url?: string | null | undefined;
            } | null | undefined;
            timestamps?: {
                start?: number | undefined;
                end?: number | undefined;
            } | null | undefined;
            party?: {
                id?: string | null | undefined;
                size?: number[] | null | undefined;
            } | null | undefined;
            secrets?: {
                join?: string | undefined;
                match?: string | undefined;
            } | null | undefined;
            created_at?: number | null | undefined;
            instance?: boolean | null | undefined;
        }[];
        client_status: {
            mobile?: unknown;
            desktop?: unknown;
            web?: unknown;
        };
        status?: unknown;
    }>, "many">>>;
    max_presences: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    max_members: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    vanity_url_code: zod.ZodNullable<zod.ZodString>;
    description: zod.ZodNullable<zod.ZodString>;
    banner: zod.ZodNullable<zod.ZodString>;
    premium_tier: zod.ZodNumber;
    premium_subscription_count: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    preferred_locale: zod.ZodString;
    public_updates_channel_id: zod.ZodNullable<zod.ZodString>;
    max_video_channel_users: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    approximate_member_count: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    approximate_presence_count: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
}, "strip", zod.ZodTypeAny, {
    id: string;
    description: string | null;
    icon: string | null;
    name: string;
    application_id: string | null;
    roles: {
        id: string;
        name: string;
        managed: boolean;
        position: number;
        color: number;
        hoist: boolean;
        permissions: string;
        mentionable: boolean;
    }[];
    owner_id: string;
    splash: string | null;
    discovery_splash: string | null;
    region: string;
    afk_channel_id: string | null;
    afk_timeout: number;
    verification_level: number;
    default_message_notifications: number;
    explicit_content_filter: number;
    emojis: {
        id: string;
        user?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        name?: string | null | undefined;
        animated?: boolean | null | undefined;
        roles?: string[] | null | undefined;
        require_colons?: boolean | null | undefined;
        managed?: boolean | null | undefined;
        available?: boolean | null | undefined;
    }[];
    features: string[];
    mfa_level: number;
    system_channel_id: string | null;
    system_channel_flags: number;
    rules_channel_id: string | null;
    vanity_url_code: string | null;
    banner: string | null;
    premium_tier: number;
    preferred_locale: string;
    public_updates_channel_id: string | null;
    joined_at?: string | null | undefined;
    permissions?: string | null | undefined;
    icon_hash?: string | null | undefined;
    owner?: boolean | null | undefined;
    widget_enabled?: boolean | null | undefined;
    widget_channel_id?: string | null | undefined;
    large?: boolean | null | undefined;
    unavailable?: boolean | null | undefined;
    member_count?: number | null | undefined;
    voice_states?: {
        deaf: boolean;
        mute: boolean;
        self_mute: boolean;
        self_deaf: boolean;
        suppress: boolean;
    }[] | null | undefined;
    members?: {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        roles: string[];
        joined_at: string;
        deaf: boolean;
        mute: boolean;
        nick?: string | null | undefined;
    }[] | null | undefined;
    channels?: {
        type: 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1;
        id: string;
        icon?: string | null | undefined;
        name?: string | null | undefined;
        application_id?: string | null | undefined;
        guild_id?: string | null | undefined;
        position?: number | null | undefined;
        permission_overwrites?: {
            type: 0 | 1 | -1;
            id: string;
            allow: string;
            deny: string;
        }[] | null | undefined;
        topic?: string | null | undefined;
        nsfw?: boolean | null | undefined;
        last_message_id?: string | null | undefined;
        bitrate?: number | null | undefined;
        user_limit?: number | null | undefined;
        rate_limit_per_user?: number | null | undefined;
        recipients?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[] | null | undefined;
        owner_id?: string | null | undefined;
        parent_id?: string | null | undefined;
        last_pin_timestamp?: string | null | undefined;
    }[] | null | undefined;
    presences?: {
        status: -1 | "idle" | "dnd" | "online" | "offline";
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        guild_id: string;
        activities: {
            type: number;
            name: string;
            flags?: number | null | undefined;
            url?: string | null | undefined;
            application_id?: string | null | undefined;
            state?: string | null | undefined;
            state_url?: string | null | undefined;
            details?: string | null | undefined;
            details_url?: string | null | undefined;
            emoji?: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            } | null | undefined;
            assets?: {
                large_image?: string | null | undefined;
                large_text?: string | null | undefined;
                large_url?: string | null | undefined;
                small_image?: string | null | undefined;
                small_text?: string | null | undefined;
                small_url?: string | null | undefined;
            } | null | undefined;
            timestamps?: {
                start?: number | undefined;
                end?: number | undefined;
            } | null | undefined;
            party?: {
                id?: string | null | undefined;
                size?: number[] | null | undefined;
            } | null | undefined;
            secrets?: {
                join?: string | undefined;
                match?: string | undefined;
            } | null | undefined;
            created_at?: number | null | undefined;
            instance?: boolean | null | undefined;
        }[];
        client_status: {
            mobile?: (-1 | "idle" | "dnd" | "online" | "offline") | undefined;
            desktop?: (-1 | "idle" | "dnd" | "online" | "offline") | undefined;
            web?: (-1 | "idle" | "dnd" | "online" | "offline") | undefined;
        };
    }[] | null | undefined;
    max_presences?: number | null | undefined;
    max_members?: number | null | undefined;
    premium_subscription_count?: number | null | undefined;
    max_video_channel_users?: number | null | undefined;
    approximate_member_count?: number | null | undefined;
    approximate_presence_count?: number | null | undefined;
}, {
    id: string;
    description: string | null;
    icon: string | null;
    name: string;
    application_id: string | null;
    roles: {
        id: string;
        name: string;
        managed: boolean;
        position: number;
        color: number;
        hoist: boolean;
        permissions: string;
        mentionable: boolean;
    }[];
    owner_id: string;
    splash: string | null;
    discovery_splash: string | null;
    region: string;
    afk_channel_id: string | null;
    afk_timeout: number;
    verification_level: number;
    default_message_notifications: number;
    explicit_content_filter: number;
    emojis: {
        id: string;
        user?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        name?: string | null | undefined;
        animated?: boolean | null | undefined;
        roles?: string[] | null | undefined;
        require_colons?: boolean | null | undefined;
        managed?: boolean | null | undefined;
        available?: boolean | null | undefined;
    }[];
    features: string[];
    mfa_level: number;
    system_channel_id: string | null;
    system_channel_flags: number;
    rules_channel_id: string | null;
    vanity_url_code: string | null;
    banner: string | null;
    premium_tier: number;
    preferred_locale: string;
    public_updates_channel_id: string | null;
    joined_at?: string | null | undefined;
    permissions?: string | null | undefined;
    icon_hash?: string | null | undefined;
    owner?: boolean | null | undefined;
    widget_enabled?: boolean | null | undefined;
    widget_channel_id?: string | null | undefined;
    large?: boolean | null | undefined;
    unavailable?: boolean | null | undefined;
    member_count?: number | null | undefined;
    voice_states?: {
        deaf: boolean;
        mute: boolean;
        self_mute: boolean;
        self_deaf: boolean;
        suppress: boolean;
    }[] | null | undefined;
    members?: {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        roles: string[];
        joined_at: string;
        deaf: boolean;
        mute: boolean;
        nick?: string | null | undefined;
    }[] | null | undefined;
    channels?: {
        id: string;
        type?: unknown;
        icon?: string | null | undefined;
        name?: string | null | undefined;
        application_id?: string | null | undefined;
        guild_id?: string | null | undefined;
        position?: number | null | undefined;
        permission_overwrites?: {
            id: string;
            allow: string;
            deny: string;
            type?: unknown;
        }[] | null | undefined;
        topic?: string | null | undefined;
        nsfw?: boolean | null | undefined;
        last_message_id?: string | null | undefined;
        bitrate?: number | null | undefined;
        user_limit?: number | null | undefined;
        rate_limit_per_user?: number | null | undefined;
        recipients?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[] | null | undefined;
        owner_id?: string | null | undefined;
        parent_id?: string | null | undefined;
        last_pin_timestamp?: string | null | undefined;
    }[] | null | undefined;
    presences?: {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        guild_id: string;
        activities: {
            type: number;
            name: string;
            flags?: number | null | undefined;
            url?: string | null | undefined;
            application_id?: string | null | undefined;
            state?: string | null | undefined;
            state_url?: string | null | undefined;
            details?: string | null | undefined;
            details_url?: string | null | undefined;
            emoji?: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            } | null | undefined;
            assets?: {
                large_image?: string | null | undefined;
                large_text?: string | null | undefined;
                large_url?: string | null | undefined;
                small_image?: string | null | undefined;
                small_text?: string | null | undefined;
                small_url?: string | null | undefined;
            } | null | undefined;
            timestamps?: {
                start?: number | undefined;
                end?: number | undefined;
            } | null | undefined;
            party?: {
                id?: string | null | undefined;
                size?: number[] | null | undefined;
            } | null | undefined;
            secrets?: {
                join?: string | undefined;
                match?: string | undefined;
            } | null | undefined;
            created_at?: number | null | undefined;
            instance?: boolean | null | undefined;
        }[];
        client_status: {
            mobile?: unknown;
            desktop?: unknown;
            web?: unknown;
        };
        status?: unknown;
    }[] | null | undefined;
    max_presences?: number | null | undefined;
    max_members?: number | null | undefined;
    premium_subscription_count?: number | null | undefined;
    max_video_channel_users?: number | null | undefined;
    approximate_member_count?: number | null | undefined;
    approximate_presence_count?: number | null | undefined;
}>;
export declare const ChannelMention: zod.ZodObject<{
    id: zod.ZodString;
    guild_id: zod.ZodString;
    type: zod.ZodNumber;
    name: zod.ZodString;
}, "strip", zod.ZodTypeAny, {
    type: number;
    id: string;
    name: string;
    guild_id: string;
}, {
    type: number;
    id: string;
    name: string;
    guild_id: string;
}>;
export declare const Attachment: zod.ZodObject<{
    id: zod.ZodString;
    filename: zod.ZodString;
    size: zod.ZodNumber;
    url: zod.ZodString;
    proxy_url: zod.ZodString;
    height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
}, "strip", zod.ZodTypeAny, {
    id: string;
    url: string;
    size: number;
    filename: string;
    proxy_url: string;
    height?: number | null | undefined;
    width?: number | null | undefined;
}, {
    id: string;
    url: string;
    size: number;
    filename: string;
    proxy_url: string;
    height?: number | null | undefined;
    width?: number | null | undefined;
}>;
export declare const EmbedFooter: zod.ZodObject<{
    text: zod.ZodString;
    icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    proxy_icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
}, "strip", zod.ZodTypeAny, {
    text: string;
    icon_url?: string | null | undefined;
    proxy_icon_url?: string | null | undefined;
}, {
    text: string;
    icon_url?: string | null | undefined;
    proxy_icon_url?: string | null | undefined;
}>;
export declare const Image: zod.ZodObject<{
    url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    proxy_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
}, "strip", zod.ZodTypeAny, {
    height?: number | null | undefined;
    url?: string | null | undefined;
    width?: number | null | undefined;
    proxy_url?: string | null | undefined;
}, {
    height?: number | null | undefined;
    url?: string | null | undefined;
    width?: number | null | undefined;
    proxy_url?: string | null | undefined;
}>;
export declare const Video: zod.ZodObject<Omit<{
    url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    proxy_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
}, "proxy_url">, "strip", zod.ZodTypeAny, {
    height?: number | null | undefined;
    url?: string | null | undefined;
    width?: number | null | undefined;
}, {
    height?: number | null | undefined;
    url?: string | null | undefined;
    width?: number | null | undefined;
}>;
export declare const EmbedProvider: zod.ZodObject<{
    name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
}, "strip", zod.ZodTypeAny, {
    name?: string | null | undefined;
    url?: string | null | undefined;
}, {
    name?: string | null | undefined;
    url?: string | null | undefined;
}>;
export declare const EmbedAuthor: zod.ZodObject<{
    name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    proxy_icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
}, "strip", zod.ZodTypeAny, {
    name?: string | null | undefined;
    url?: string | null | undefined;
    icon_url?: string | null | undefined;
    proxy_icon_url?: string | null | undefined;
}, {
    name?: string | null | undefined;
    url?: string | null | undefined;
    icon_url?: string | null | undefined;
    proxy_icon_url?: string | null | undefined;
}>;
export declare const EmbedField: zod.ZodObject<{
    name: zod.ZodString;
    value: zod.ZodString;
    inline: zod.ZodBoolean;
}, "strip", zod.ZodTypeAny, {
    value: string;
    name: string;
    inline: boolean;
}, {
    value: string;
    name: string;
    inline: boolean;
}>;
export declare const Embed: zod.ZodObject<{
    title: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    type: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    description: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    timestamp: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    color: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    footer: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        text: zod.ZodString;
        icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        proxy_icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    }, "strip", zod.ZodTypeAny, {
        text: string;
        icon_url?: string | null | undefined;
        proxy_icon_url?: string | null | undefined;
    }, {
        text: string;
        icon_url?: string | null | undefined;
        proxy_icon_url?: string | null | undefined;
    }>>>;
    image: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        proxy_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    }, "strip", zod.ZodTypeAny, {
        height?: number | null | undefined;
        url?: string | null | undefined;
        width?: number | null | undefined;
        proxy_url?: string | null | undefined;
    }, {
        height?: number | null | undefined;
        url?: string | null | undefined;
        width?: number | null | undefined;
        proxy_url?: string | null | undefined;
    }>>>;
    thumbnail: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        proxy_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    }, "strip", zod.ZodTypeAny, {
        height?: number | null | undefined;
        url?: string | null | undefined;
        width?: number | null | undefined;
        proxy_url?: string | null | undefined;
    }, {
        height?: number | null | undefined;
        url?: string | null | undefined;
        width?: number | null | undefined;
        proxy_url?: string | null | undefined;
    }>>>;
    video: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<Omit<{
        url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        proxy_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    }, "proxy_url">, "strip", zod.ZodTypeAny, {
        height?: number | null | undefined;
        url?: string | null | undefined;
        width?: number | null | undefined;
    }, {
        height?: number | null | undefined;
        url?: string | null | undefined;
        width?: number | null | undefined;
    }>>>;
    provider: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    }, "strip", zod.ZodTypeAny, {
        name?: string | null | undefined;
        url?: string | null | undefined;
    }, {
        name?: string | null | undefined;
        url?: string | null | undefined;
    }>>>;
    author: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        proxy_icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    }, "strip", zod.ZodTypeAny, {
        name?: string | null | undefined;
        url?: string | null | undefined;
        icon_url?: string | null | undefined;
        proxy_icon_url?: string | null | undefined;
    }, {
        name?: string | null | undefined;
        url?: string | null | undefined;
        icon_url?: string | null | undefined;
        proxy_icon_url?: string | null | undefined;
    }>>>;
    fields: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
        name: zod.ZodString;
        value: zod.ZodString;
        inline: zod.ZodBoolean;
    }, "strip", zod.ZodTypeAny, {
        value: string;
        name: string;
        inline: boolean;
    }, {
        value: string;
        name: string;
        inline: boolean;
    }>, "many">>>;
}, "strip", zod.ZodTypeAny, {
    type?: string | null | undefined;
    description?: string | null | undefined;
    url?: string | null | undefined;
    color?: number | null | undefined;
    title?: string | null | undefined;
    timestamp?: string | null | undefined;
    footer?: {
        text: string;
        icon_url?: string | null | undefined;
        proxy_icon_url?: string | null | undefined;
    } | null | undefined;
    image?: {
        height?: number | null | undefined;
        url?: string | null | undefined;
        width?: number | null | undefined;
        proxy_url?: string | null | undefined;
    } | null | undefined;
    thumbnail?: {
        height?: number | null | undefined;
        url?: string | null | undefined;
        width?: number | null | undefined;
        proxy_url?: string | null | undefined;
    } | null | undefined;
    video?: {
        height?: number | null | undefined;
        url?: string | null | undefined;
        width?: number | null | undefined;
    } | null | undefined;
    provider?: {
        name?: string | null | undefined;
        url?: string | null | undefined;
    } | null | undefined;
    author?: {
        name?: string | null | undefined;
        url?: string | null | undefined;
        icon_url?: string | null | undefined;
        proxy_icon_url?: string | null | undefined;
    } | null | undefined;
    fields?: {
        value: string;
        name: string;
        inline: boolean;
    }[] | null | undefined;
}, {
    type?: string | null | undefined;
    description?: string | null | undefined;
    url?: string | null | undefined;
    color?: number | null | undefined;
    title?: string | null | undefined;
    timestamp?: string | null | undefined;
    footer?: {
        text: string;
        icon_url?: string | null | undefined;
        proxy_icon_url?: string | null | undefined;
    } | null | undefined;
    image?: {
        height?: number | null | undefined;
        url?: string | null | undefined;
        width?: number | null | undefined;
        proxy_url?: string | null | undefined;
    } | null | undefined;
    thumbnail?: {
        height?: number | null | undefined;
        url?: string | null | undefined;
        width?: number | null | undefined;
        proxy_url?: string | null | undefined;
    } | null | undefined;
    video?: {
        height?: number | null | undefined;
        url?: string | null | undefined;
        width?: number | null | undefined;
    } | null | undefined;
    provider?: {
        name?: string | null | undefined;
        url?: string | null | undefined;
    } | null | undefined;
    author?: {
        name?: string | null | undefined;
        url?: string | null | undefined;
        icon_url?: string | null | undefined;
        proxy_icon_url?: string | null | undefined;
    } | null | undefined;
    fields?: {
        value: string;
        name: string;
        inline: boolean;
    }[] | null | undefined;
}>;
export declare const Reaction: zod.ZodObject<{
    count: zod.ZodNumber;
    me: zod.ZodBoolean;
    emoji: zod.ZodObject<{
        id: zod.ZodString;
        name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        roles: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>>;
        user: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>>>;
        require_colons: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        managed: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        animated: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        available: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    }, "strip", zod.ZodTypeAny, {
        id: string;
        user?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        name?: string | null | undefined;
        animated?: boolean | null | undefined;
        roles?: string[] | null | undefined;
        require_colons?: boolean | null | undefined;
        managed?: boolean | null | undefined;
        available?: boolean | null | undefined;
    }, {
        id: string;
        user?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        name?: string | null | undefined;
        animated?: boolean | null | undefined;
        roles?: string[] | null | undefined;
        require_colons?: boolean | null | undefined;
        managed?: boolean | null | undefined;
        available?: boolean | null | undefined;
    }>;
}, "strip", zod.ZodTypeAny, {
    emoji: {
        id: string;
        user?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        name?: string | null | undefined;
        animated?: boolean | null | undefined;
        roles?: string[] | null | undefined;
        require_colons?: boolean | null | undefined;
        managed?: boolean | null | undefined;
        available?: boolean | null | undefined;
    };
    count: number;
    me: boolean;
}, {
    emoji: {
        id: string;
        user?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        name?: string | null | undefined;
        animated?: boolean | null | undefined;
        roles?: string[] | null | undefined;
        require_colons?: boolean | null | undefined;
        managed?: boolean | null | undefined;
        available?: boolean | null | undefined;
    };
    count: number;
    me: boolean;
}>;
export declare const MessageActivity: zod.ZodObject<{
    type: zod.ZodNumber;
    party_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
}, "strip", zod.ZodTypeAny, {
    type: number;
    party_id?: string | null | undefined;
}, {
    type: number;
    party_id?: string | null | undefined;
}>;
export declare const MessageApplication: zod.ZodObject<{
    id: zod.ZodString;
    cover_image: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    description: zod.ZodString;
    icon: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    name: zod.ZodString;
}, "strip", zod.ZodTypeAny, {
    id: string;
    description: string;
    name: string;
    icon?: string | null | undefined;
    cover_image?: string | null | undefined;
}, {
    id: string;
    description: string;
    name: string;
    icon?: string | null | undefined;
    cover_image?: string | null | undefined;
}>;
export declare const MessageReference: zod.ZodObject<{
    message_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    channel_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    guild_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
}, "strip", zod.ZodTypeAny, {
    guild_id?: string | null | undefined;
    message_id?: string | null | undefined;
    channel_id?: string | null | undefined;
}, {
    guild_id?: string | null | undefined;
    message_id?: string | null | undefined;
    channel_id?: string | null | undefined;
}>;
export declare const Message: zod.ZodObject<{
    id: zod.ZodString;
    channel_id: zod.ZodString;
    guild_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    author: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        id: zod.ZodString;
        username: zod.ZodString;
        discriminator: zod.ZodString;
        global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
            asset: zod.ZodString;
            sku_id: zod.ZodOptional<zod.ZodString>;
        }, "strip", zod.ZodTypeAny, {
            asset: string;
            sku_id?: string | undefined;
        }, {
            asset: string;
            sku_id?: string | undefined;
        }>>;
        bot: zod.ZodBoolean;
        flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    }, "strip", zod.ZodTypeAny, {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    }, {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    }>>>;
    member: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        user: zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>;
        nick: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        roles: zod.ZodArray<zod.ZodString, "many">;
        joined_at: zod.ZodString;
        deaf: zod.ZodBoolean;
        mute: zod.ZodBoolean;
    }, "strip", zod.ZodTypeAny, {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        roles: string[];
        joined_at: string;
        deaf: boolean;
        mute: boolean;
        nick?: string | null | undefined;
    }, {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        roles: string[];
        joined_at: string;
        deaf: boolean;
        mute: boolean;
        nick?: string | null | undefined;
    }>>>;
    content: zod.ZodString;
    timestamp: zod.ZodString;
    edited_timestamp: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    tts: zod.ZodBoolean;
    mention_everyone: zod.ZodBoolean;
    mentions: zod.ZodArray<zod.ZodObject<{
        id: zod.ZodString;
        username: zod.ZodString;
        discriminator: zod.ZodString;
        global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
            asset: zod.ZodString;
            sku_id: zod.ZodOptional<zod.ZodString>;
        }, "strip", zod.ZodTypeAny, {
            asset: string;
            sku_id?: string | undefined;
        }, {
            asset: string;
            sku_id?: string | undefined;
        }>>;
        bot: zod.ZodBoolean;
        flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    }, "strip", zod.ZodTypeAny, {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    }, {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    }>, "many">;
    mention_roles: zod.ZodArray<zod.ZodString, "many">;
    mention_channels: zod.ZodArray<zod.ZodObject<{
        id: zod.ZodString;
        guild_id: zod.ZodString;
        type: zod.ZodNumber;
        name: zod.ZodString;
    }, "strip", zod.ZodTypeAny, {
        type: number;
        id: string;
        name: string;
        guild_id: string;
    }, {
        type: number;
        id: string;
        name: string;
        guild_id: string;
    }>, "many">;
    attachments: zod.ZodArray<zod.ZodObject<{
        id: zod.ZodString;
        filename: zod.ZodString;
        size: zod.ZodNumber;
        url: zod.ZodString;
        proxy_url: zod.ZodString;
        height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    }, "strip", zod.ZodTypeAny, {
        id: string;
        url: string;
        size: number;
        filename: string;
        proxy_url: string;
        height?: number | null | undefined;
        width?: number | null | undefined;
    }, {
        id: string;
        url: string;
        size: number;
        filename: string;
        proxy_url: string;
        height?: number | null | undefined;
        width?: number | null | undefined;
    }>, "many">;
    embeds: zod.ZodArray<zod.ZodObject<{
        title: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        type: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        description: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        timestamp: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        color: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        footer: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            text: zod.ZodString;
            icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            proxy_icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        }, "strip", zod.ZodTypeAny, {
            text: string;
            icon_url?: string | null | undefined;
            proxy_icon_url?: string | null | undefined;
        }, {
            text: string;
            icon_url?: string | null | undefined;
            proxy_icon_url?: string | null | undefined;
        }>>>;
        image: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            proxy_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            height?: number | null | undefined;
            url?: string | null | undefined;
            width?: number | null | undefined;
            proxy_url?: string | null | undefined;
        }, {
            height?: number | null | undefined;
            url?: string | null | undefined;
            width?: number | null | undefined;
            proxy_url?: string | null | undefined;
        }>>>;
        thumbnail: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            proxy_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            height?: number | null | undefined;
            url?: string | null | undefined;
            width?: number | null | undefined;
            proxy_url?: string | null | undefined;
        }, {
            height?: number | null | undefined;
            url?: string | null | undefined;
            width?: number | null | undefined;
            proxy_url?: string | null | undefined;
        }>>>;
        video: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<Omit<{
            url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            proxy_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "proxy_url">, "strip", zod.ZodTypeAny, {
            height?: number | null | undefined;
            url?: string | null | undefined;
            width?: number | null | undefined;
        }, {
            height?: number | null | undefined;
            url?: string | null | undefined;
            width?: number | null | undefined;
        }>>>;
        provider: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        }, "strip", zod.ZodTypeAny, {
            name?: string | null | undefined;
            url?: string | null | undefined;
        }, {
            name?: string | null | undefined;
            url?: string | null | undefined;
        }>>>;
        author: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            proxy_icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        }, "strip", zod.ZodTypeAny, {
            name?: string | null | undefined;
            url?: string | null | undefined;
            icon_url?: string | null | undefined;
            proxy_icon_url?: string | null | undefined;
        }, {
            name?: string | null | undefined;
            url?: string | null | undefined;
            icon_url?: string | null | undefined;
            proxy_icon_url?: string | null | undefined;
        }>>>;
        fields: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
            name: zod.ZodString;
            value: zod.ZodString;
            inline: zod.ZodBoolean;
        }, "strip", zod.ZodTypeAny, {
            value: string;
            name: string;
            inline: boolean;
        }, {
            value: string;
            name: string;
            inline: boolean;
        }>, "many">>>;
    }, "strip", zod.ZodTypeAny, {
        type?: string | null | undefined;
        description?: string | null | undefined;
        url?: string | null | undefined;
        color?: number | null | undefined;
        title?: string | null | undefined;
        timestamp?: string | null | undefined;
        footer?: {
            text: string;
            icon_url?: string | null | undefined;
            proxy_icon_url?: string | null | undefined;
        } | null | undefined;
        image?: {
            height?: number | null | undefined;
            url?: string | null | undefined;
            width?: number | null | undefined;
            proxy_url?: string | null | undefined;
        } | null | undefined;
        thumbnail?: {
            height?: number | null | undefined;
            url?: string | null | undefined;
            width?: number | null | undefined;
            proxy_url?: string | null | undefined;
        } | null | undefined;
        video?: {
            height?: number | null | undefined;
            url?: string | null | undefined;
            width?: number | null | undefined;
        } | null | undefined;
        provider?: {
            name?: string | null | undefined;
            url?: string | null | undefined;
        } | null | undefined;
        author?: {
            name?: string | null | undefined;
            url?: string | null | undefined;
            icon_url?: string | null | undefined;
            proxy_icon_url?: string | null | undefined;
        } | null | undefined;
        fields?: {
            value: string;
            name: string;
            inline: boolean;
        }[] | null | undefined;
    }, {
        type?: string | null | undefined;
        description?: string | null | undefined;
        url?: string | null | undefined;
        color?: number | null | undefined;
        title?: string | null | undefined;
        timestamp?: string | null | undefined;
        footer?: {
            text: string;
            icon_url?: string | null | undefined;
            proxy_icon_url?: string | null | undefined;
        } | null | undefined;
        image?: {
            height?: number | null | undefined;
            url?: string | null | undefined;
            width?: number | null | undefined;
            proxy_url?: string | null | undefined;
        } | null | undefined;
        thumbnail?: {
            height?: number | null | undefined;
            url?: string | null | undefined;
            width?: number | null | undefined;
            proxy_url?: string | null | undefined;
        } | null | undefined;
        video?: {
            height?: number | null | undefined;
            url?: string | null | undefined;
            width?: number | null | undefined;
        } | null | undefined;
        provider?: {
            name?: string | null | undefined;
            url?: string | null | undefined;
        } | null | undefined;
        author?: {
            name?: string | null | undefined;
            url?: string | null | undefined;
            icon_url?: string | null | undefined;
            proxy_icon_url?: string | null | undefined;
        } | null | undefined;
        fields?: {
            value: string;
            name: string;
            inline: boolean;
        }[] | null | undefined;
    }>, "many">;
    reactions: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
        count: zod.ZodNumber;
        me: zod.ZodBoolean;
        emoji: zod.ZodObject<{
            id: zod.ZodString;
            name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            roles: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>>;
            user: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                id: zod.ZodString;
                username: zod.ZodString;
                discriminator: zod.ZodString;
                global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                    asset: zod.ZodString;
                    sku_id: zod.ZodOptional<zod.ZodString>;
                }, "strip", zod.ZodTypeAny, {
                    asset: string;
                    sku_id?: string | undefined;
                }, {
                    asset: string;
                    sku_id?: string | undefined;
                }>>;
                bot: zod.ZodBoolean;
                flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "strip", zod.ZodTypeAny, {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            }, {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            }>>>;
            require_colons: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
            managed: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
            animated: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
            available: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        }, "strip", zod.ZodTypeAny, {
            id: string;
            user?: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            } | null | undefined;
            name?: string | null | undefined;
            animated?: boolean | null | undefined;
            roles?: string[] | null | undefined;
            require_colons?: boolean | null | undefined;
            managed?: boolean | null | undefined;
            available?: boolean | null | undefined;
        }, {
            id: string;
            user?: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            } | null | undefined;
            name?: string | null | undefined;
            animated?: boolean | null | undefined;
            roles?: string[] | null | undefined;
            require_colons?: boolean | null | undefined;
            managed?: boolean | null | undefined;
            available?: boolean | null | undefined;
        }>;
    }, "strip", zod.ZodTypeAny, {
        emoji: {
            id: string;
            user?: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            } | null | undefined;
            name?: string | null | undefined;
            animated?: boolean | null | undefined;
            roles?: string[] | null | undefined;
            require_colons?: boolean | null | undefined;
            managed?: boolean | null | undefined;
            available?: boolean | null | undefined;
        };
        count: number;
        me: boolean;
    }, {
        emoji: {
            id: string;
            user?: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            } | null | undefined;
            name?: string | null | undefined;
            animated?: boolean | null | undefined;
            roles?: string[] | null | undefined;
            require_colons?: boolean | null | undefined;
            managed?: boolean | null | undefined;
            available?: boolean | null | undefined;
        };
        count: number;
        me: boolean;
    }>, "many">>>;
    nonce: zod.ZodNullable<zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNumber]>>>;
    pinned: zod.ZodBoolean;
    webhook_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    type: zod.ZodNumber;
    activity: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        type: zod.ZodNumber;
        party_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    }, "strip", zod.ZodTypeAny, {
        type: number;
        party_id?: string | null | undefined;
    }, {
        type: number;
        party_id?: string | null | undefined;
    }>>>;
    application: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        id: zod.ZodString;
        cover_image: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        description: zod.ZodString;
        icon: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        name: zod.ZodString;
    }, "strip", zod.ZodTypeAny, {
        id: string;
        description: string;
        name: string;
        icon?: string | null | undefined;
        cover_image?: string | null | undefined;
    }, {
        id: string;
        description: string;
        name: string;
        icon?: string | null | undefined;
        cover_image?: string | null | undefined;
    }>>>;
    message_reference: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        message_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        channel_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        guild_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    }, "strip", zod.ZodTypeAny, {
        guild_id?: string | null | undefined;
        message_id?: string | null | undefined;
        channel_id?: string | null | undefined;
    }, {
        guild_id?: string | null | undefined;
        message_id?: string | null | undefined;
        channel_id?: string | null | undefined;
    }>>>;
    flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    stickers: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodUnknown, "many">>>;
    referenced_message: zod.ZodNullable<zod.ZodOptional<zod.ZodUnknown>>;
}, "strip", zod.ZodTypeAny, {
    type: number;
    id: string;
    content: string;
    timestamp: string;
    channel_id: string;
    tts: boolean;
    mention_everyone: boolean;
    mentions: {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    }[];
    mention_roles: string[];
    mention_channels: {
        type: number;
        id: string;
        name: string;
        guild_id: string;
    }[];
    attachments: {
        id: string;
        url: string;
        size: number;
        filename: string;
        proxy_url: string;
        height?: number | null | undefined;
        width?: number | null | undefined;
    }[];
    embeds: {
        type?: string | null | undefined;
        description?: string | null | undefined;
        url?: string | null | undefined;
        color?: number | null | undefined;
        title?: string | null | undefined;
        timestamp?: string | null | undefined;
        footer?: {
            text: string;
            icon_url?: string | null | undefined;
            proxy_icon_url?: string | null | undefined;
        } | null | undefined;
        image?: {
            height?: number | null | undefined;
            url?: string | null | undefined;
            width?: number | null | undefined;
            proxy_url?: string | null | undefined;
        } | null | undefined;
        thumbnail?: {
            height?: number | null | undefined;
            url?: string | null | undefined;
            width?: number | null | undefined;
            proxy_url?: string | null | undefined;
        } | null | undefined;
        video?: {
            height?: number | null | undefined;
            url?: string | null | undefined;
            width?: number | null | undefined;
        } | null | undefined;
        provider?: {
            name?: string | null | undefined;
            url?: string | null | undefined;
        } | null | undefined;
        author?: {
            name?: string | null | undefined;
            url?: string | null | undefined;
            icon_url?: string | null | undefined;
            proxy_icon_url?: string | null | undefined;
        } | null | undefined;
        fields?: {
            value: string;
            name: string;
            inline: boolean;
        }[] | null | undefined;
    }[];
    pinned: boolean;
    application?: {
        id: string;
        description: string;
        name: string;
        icon?: string | null | undefined;
        cover_image?: string | null | undefined;
    } | null | undefined;
    flags?: number | null | undefined;
    activity?: {
        type: number;
        party_id?: string | null | undefined;
    } | null | undefined;
    nonce?: string | number | null | undefined;
    guild_id?: string | null | undefined;
    author?: {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    } | null | undefined;
    member?: {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        roles: string[];
        joined_at: string;
        deaf: boolean;
        mute: boolean;
        nick?: string | null | undefined;
    } | null | undefined;
    edited_timestamp?: string | null | undefined;
    reactions?: {
        emoji: {
            id: string;
            user?: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            } | null | undefined;
            name?: string | null | undefined;
            animated?: boolean | null | undefined;
            roles?: string[] | null | undefined;
            require_colons?: boolean | null | undefined;
            managed?: boolean | null | undefined;
            available?: boolean | null | undefined;
        };
        count: number;
        me: boolean;
    }[] | null | undefined;
    webhook_id?: string | null | undefined;
    message_reference?: {
        guild_id?: string | null | undefined;
        message_id?: string | null | undefined;
        channel_id?: string | null | undefined;
    } | null | undefined;
    stickers?: unknown[] | null | undefined;
    referenced_message?: unknown;
}, {
    type: number;
    id: string;
    content: string;
    timestamp: string;
    channel_id: string;
    tts: boolean;
    mention_everyone: boolean;
    mentions: {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    }[];
    mention_roles: string[];
    mention_channels: {
        type: number;
        id: string;
        name: string;
        guild_id: string;
    }[];
    attachments: {
        id: string;
        url: string;
        size: number;
        filename: string;
        proxy_url: string;
        height?: number | null | undefined;
        width?: number | null | undefined;
    }[];
    embeds: {
        type?: string | null | undefined;
        description?: string | null | undefined;
        url?: string | null | undefined;
        color?: number | null | undefined;
        title?: string | null | undefined;
        timestamp?: string | null | undefined;
        footer?: {
            text: string;
            icon_url?: string | null | undefined;
            proxy_icon_url?: string | null | undefined;
        } | null | undefined;
        image?: {
            height?: number | null | undefined;
            url?: string | null | undefined;
            width?: number | null | undefined;
            proxy_url?: string | null | undefined;
        } | null | undefined;
        thumbnail?: {
            height?: number | null | undefined;
            url?: string | null | undefined;
            width?: number | null | undefined;
            proxy_url?: string | null | undefined;
        } | null | undefined;
        video?: {
            height?: number | null | undefined;
            url?: string | null | undefined;
            width?: number | null | undefined;
        } | null | undefined;
        provider?: {
            name?: string | null | undefined;
            url?: string | null | undefined;
        } | null | undefined;
        author?: {
            name?: string | null | undefined;
            url?: string | null | undefined;
            icon_url?: string | null | undefined;
            proxy_icon_url?: string | null | undefined;
        } | null | undefined;
        fields?: {
            value: string;
            name: string;
            inline: boolean;
        }[] | null | undefined;
    }[];
    pinned: boolean;
    application?: {
        id: string;
        description: string;
        name: string;
        icon?: string | null | undefined;
        cover_image?: string | null | undefined;
    } | null | undefined;
    flags?: number | null | undefined;
    activity?: {
        type: number;
        party_id?: string | null | undefined;
    } | null | undefined;
    nonce?: string | number | null | undefined;
    guild_id?: string | null | undefined;
    author?: {
        username: string;
        discriminator: string;
        id: string;
        bot: boolean;
        avatar_decoration_data: {
            asset: string;
            sku_id?: string | undefined;
        } | null;
        avatar?: string | null | undefined;
        global_name?: string | null | undefined;
        flags?: number | null | undefined;
        premium_type?: number | null | undefined;
    } | null | undefined;
    member?: {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        roles: string[];
        joined_at: string;
        deaf: boolean;
        mute: boolean;
        nick?: string | null | undefined;
    } | null | undefined;
    edited_timestamp?: string | null | undefined;
    reactions?: {
        emoji: {
            id: string;
            user?: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            } | null | undefined;
            name?: string | null | undefined;
            animated?: boolean | null | undefined;
            roles?: string[] | null | undefined;
            require_colons?: boolean | null | undefined;
            managed?: boolean | null | undefined;
            available?: boolean | null | undefined;
        };
        count: number;
        me: boolean;
    }[] | null | undefined;
    webhook_id?: string | null | undefined;
    message_reference?: {
        guild_id?: string | null | undefined;
        message_id?: string | null | undefined;
        channel_id?: string | null | undefined;
    } | null | undefined;
    stickers?: unknown[] | null | undefined;
    referenced_message?: unknown;
}>;
export declare const VoiceDevice: zod.ZodObject<{
    id: zod.ZodString;
    name: zod.ZodString;
}, "strip", zod.ZodTypeAny, {
    id: string;
    name: string;
}, {
    id: string;
    name: string;
}>;
export declare const KeyTypesObject: {
    readonly UNHANDLED: -1;
    readonly KEYBOARD_KEY: 0;
    readonly MOUSE_BUTTON: 1;
    readonly KEYBOARD_MODIFIER_KEY: 2;
    readonly GAMEPAD_BUTTON: 3;
};
export declare const ShortcutKey: zod.ZodObject<{
    type: zod.ZodEffects<zod.ZodType<0 | 1 | 2 | 3 | -1, zod.ZodTypeDef, 0 | 1 | 2 | 3 | -1>, 0 | 1 | 2 | 3 | -1, unknown>;
    code: zod.ZodNumber;
    name: zod.ZodString;
}, "strip", zod.ZodTypeAny, {
    code: number;
    type: 0 | 1 | 2 | 3 | -1;
    name: string;
}, {
    code: number;
    name: string;
    type?: unknown;
}>;
export declare const VoiceSettingModeTypeObject: {
    readonly UNHANDLED: -1;
    readonly PUSH_TO_TALK: "PUSH_TO_TALK";
    readonly VOICE_ACTIVITY: "VOICE_ACTIVITY";
};
export declare const VoiceSettingsMode: zod.ZodObject<{
    type: zod.ZodEffects<zod.ZodType<-1 | "PUSH_TO_TALK" | "VOICE_ACTIVITY", zod.ZodTypeDef, -1 | "PUSH_TO_TALK" | "VOICE_ACTIVITY">, -1 | "PUSH_TO_TALK" | "VOICE_ACTIVITY", unknown>;
    auto_threshold: zod.ZodBoolean;
    threshold: zod.ZodNumber;
    shortcut: zod.ZodArray<zod.ZodObject<{
        type: zod.ZodEffects<zod.ZodType<0 | 1 | 2 | 3 | -1, zod.ZodTypeDef, 0 | 1 | 2 | 3 | -1>, 0 | 1 | 2 | 3 | -1, unknown>;
        code: zod.ZodNumber;
        name: zod.ZodString;
    }, "strip", zod.ZodTypeAny, {
        code: number;
        type: 0 | 1 | 2 | 3 | -1;
        name: string;
    }, {
        code: number;
        name: string;
        type?: unknown;
    }>, "many">;
    delay: zod.ZodNumber;
}, "strip", zod.ZodTypeAny, {
    type: -1 | "PUSH_TO_TALK" | "VOICE_ACTIVITY";
    auto_threshold: boolean;
    threshold: number;
    shortcut: {
        code: number;
        type: 0 | 1 | 2 | 3 | -1;
        name: string;
    }[];
    delay: number;
}, {
    auto_threshold: boolean;
    threshold: number;
    shortcut: {
        code: number;
        name: string;
        type?: unknown;
    }[];
    delay: number;
    type?: unknown;
}>;
export declare const VoiceSettingsIO: zod.ZodObject<{
    device_id: zod.ZodString;
    volume: zod.ZodNumber;
    available_devices: zod.ZodArray<zod.ZodObject<{
        id: zod.ZodString;
        name: zod.ZodString;
    }, "strip", zod.ZodTypeAny, {
        id: string;
        name: string;
    }, {
        id: string;
        name: string;
    }>, "many">;
}, "strip", zod.ZodTypeAny, {
    volume: number;
    device_id: string;
    available_devices: {
        id: string;
        name: string;
    }[];
}, {
    volume: number;
    device_id: string;
    available_devices: {
        id: string;
        name: string;
    }[];
}>;
export declare const CertifiedDeviceTypeObject: {
    readonly UNHANDLED: -1;
    readonly AUDIO_INPUT: "AUDIO_INPUT";
    readonly AUDIO_OUTPUT: "AUDIO_OUTPUT";
    readonly VIDEO_INPUT: "VIDEO_INPUT";
};
export declare const CertifiedDevice: zod.ZodObject<{
    type: zod.ZodEffects<zod.ZodType<-1 | "AUDIO_INPUT" | "AUDIO_OUTPUT" | "VIDEO_INPUT", zod.ZodTypeDef, -1 | "AUDIO_INPUT" | "AUDIO_OUTPUT" | "VIDEO_INPUT">, -1 | "AUDIO_INPUT" | "AUDIO_OUTPUT" | "VIDEO_INPUT", unknown>;
    id: zod.ZodString;
    vendor: zod.ZodObject<{
        name: zod.ZodString;
        url: zod.ZodString;
    }, "strip", zod.ZodTypeAny, {
        name: string;
        url: string;
    }, {
        name: string;
        url: string;
    }>;
    model: zod.ZodObject<{
        name: zod.ZodString;
        url: zod.ZodString;
    }, "strip", zod.ZodTypeAny, {
        name: string;
        url: string;
    }, {
        name: string;
        url: string;
    }>;
    related: zod.ZodArray<zod.ZodString, "many">;
    echo_cancellation: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    noise_suppression: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    automatic_gain_control: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    hardware_mute: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
}, "strip", zod.ZodTypeAny, {
    type: -1 | "AUDIO_INPUT" | "AUDIO_OUTPUT" | "VIDEO_INPUT";
    id: string;
    vendor: {
        name: string;
        url: string;
    };
    model: {
        name: string;
        url: string;
    };
    related: string[];
    echo_cancellation?: boolean | null | undefined;
    noise_suppression?: boolean | null | undefined;
    automatic_gain_control?: boolean | null | undefined;
    hardware_mute?: boolean | null | undefined;
}, {
    id: string;
    vendor: {
        name: string;
        url: string;
    };
    model: {
        name: string;
        url: string;
    };
    related: string[];
    type?: unknown;
    echo_cancellation?: boolean | null | undefined;
    noise_suppression?: boolean | null | undefined;
    automatic_gain_control?: boolean | null | undefined;
    hardware_mute?: boolean | null | undefined;
}>;
export declare const SkuTypeObject: {
    readonly UNHANDLED: -1;
    readonly APPLICATION: 1;
    readonly DLC: 2;
    readonly CONSUMABLE: 3;
    readonly BUNDLE: 4;
    readonly SUBSCRIPTION: 5;
};
export declare const Sku: zod.ZodObject<{
    id: zod.ZodString;
    name: zod.ZodString;
    type: zod.ZodEffects<zod.ZodType<1 | 4 | 2 | 3 | 5 | -1, zod.ZodTypeDef, 1 | 4 | 2 | 3 | 5 | -1>, 1 | 4 | 2 | 3 | 5 | -1, unknown>;
    price: zod.ZodObject<{
        amount: zod.ZodNumber;
        currency: zod.ZodString;
    }, "strip", zod.ZodTypeAny, {
        amount: number;
        currency: string;
    }, {
        amount: number;
        currency: string;
    }>;
    application_id: zod.ZodString;
    flags: zod.ZodNumber;
    release_date: zod.ZodNullable<zod.ZodString>;
}, "strip", zod.ZodTypeAny, {
    type: 1 | 4 | 2 | 3 | 5 | -1;
    id: string;
    name: string;
    flags: number;
    application_id: string;
    price: {
        amount: number;
        currency: string;
    };
    release_date: string | null;
}, {
    id: string;
    name: string;
    flags: number;
    application_id: string;
    price: {
        amount: number;
        currency: string;
    };
    release_date: string | null;
    type?: unknown;
}>;
export declare const EntitlementTypesObject: {
    readonly UNHANDLED: -1;
    readonly PURCHASE: 1;
    readonly PREMIUM_SUBSCRIPTION: 2;
    readonly DEVELOPER_GIFT: 3;
    readonly TEST_MODE_PURCHASE: 4;
    readonly FREE_PURCHASE: 5;
    readonly USER_GIFT: 6;
    readonly PREMIUM_PURCHASE: 7;
};
export declare const Entitlement: zod.ZodObject<{
    id: zod.ZodString;
    sku_id: zod.ZodString;
    application_id: zod.ZodString;
    user_id: zod.ZodString;
    gift_code_flags: zod.ZodNumber;
    type: zod.ZodEffects<zod.ZodType<1 | 4 | 2 | 3 | 5 | 6 | 7 | -1, zod.ZodTypeDef, 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1>, 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1, unknown>;
    gifter_user_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    branches: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>>;
    starts_at: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    ends_at: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    parent_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    consumed: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    deleted: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    gift_code_batch_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
}, "strip", zod.ZodTypeAny, {
    type: 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1;
    id: string;
    application_id: string;
    user_id: string;
    sku_id: string;
    gift_code_flags: number;
    parent_id?: string | null | undefined;
    gifter_user_id?: string | null | undefined;
    branches?: string[] | null | undefined;
    starts_at?: string | null | undefined;
    ends_at?: string | null | undefined;
    consumed?: boolean | null | undefined;
    deleted?: boolean | null | undefined;
    gift_code_batch_id?: string | null | undefined;
}, {
    id: string;
    application_id: string;
    user_id: string;
    sku_id: string;
    gift_code_flags: number;
    type?: unknown;
    parent_id?: string | null | undefined;
    gifter_user_id?: string | null | undefined;
    branches?: string[] | null | undefined;
    starts_at?: string | null | undefined;
    ends_at?: string | null | undefined;
    consumed?: boolean | null | undefined;
    deleted?: boolean | null | undefined;
    gift_code_batch_id?: string | null | undefined;
}>;
export declare const OrientationLockStateTypeObject: {
    readonly UNHANDLED: -1;
    readonly UNLOCKED: 1;
    readonly PORTRAIT: 2;
    readonly LANDSCAPE: 3;
};
export declare const OrientationLockState: zod.ZodEffects<zod.ZodType<1 | 2 | 3 | -1, zod.ZodTypeDef, 1 | 2 | 3 | -1>, 1 | 2 | 3 | -1, unknown>;
export declare const ThermalStateTypeObject: {
    readonly UNHANDLED: -1;
    readonly NOMINAL: 0;
    readonly FAIR: 1;
    readonly SERIOUS: 2;
    readonly CRITICAL: 3;
};
export declare const ThermalState: zod.ZodEffects<zod.ZodType<0 | 1 | 2 | 3 | -1, zod.ZodTypeDef, 0 | 1 | 2 | 3 | -1>, 0 | 1 | 2 | 3 | -1, unknown>;
export declare const OrientationTypeObject: {
    readonly UNHANDLED: -1;
    readonly PORTRAIT: 0;
    readonly LANDSCAPE: 1;
};
export declare const Orientation: zod.ZodEffects<zod.ZodType<0 | 1 | -1, zod.ZodTypeDef, 0 | 1 | -1>, 0 | 1 | -1, unknown>;
export declare const LayoutModeTypeObject: {
    readonly UNHANDLED: -1;
    readonly FOCUSED: 0;
    readonly PIP: 1;
    readonly GRID: 2;
};
export declare const LayoutMode: zod.ZodEffects<zod.ZodType<0 | 1 | 2 | -1, zod.ZodTypeDef, 0 | 1 | 2 | -1>, 0 | 1 | 2 | -1, unknown>;

// ===== output/schema/events.d.ts =====
export declare const ERROR = "ERROR";
export declare enum Events {
    READY = "READY",
    VOICE_STATE_UPDATE = "VOICE_STATE_UPDATE",
    SPEAKING_START = "SPEAKING_START",
    SPEAKING_STOP = "SPEAKING_STOP",
    ACTIVITY_LAYOUT_MODE_UPDATE = "ACTIVITY_LAYOUT_MODE_UPDATE",
    ORIENTATION_UPDATE = "ORIENTATION_UPDATE",
    CURRENT_USER_UPDATE = "CURRENT_USER_UPDATE",
    CURRENT_GUILD_MEMBER_UPDATE = "CURRENT_GUILD_MEMBER_UPDATE",
    ENTITLEMENT_CREATE = "ENTITLEMENT_CREATE",
    THERMAL_STATE_UPDATE = "THERMAL_STATE_UPDATE",
    ACTIVITY_INSTANCE_PARTICIPANTS_UPDATE = "ACTIVITY_INSTANCE_PARTICIPANTS_UPDATE",
    RELATIONSHIP_UPDATE = "RELATIONSHIP_UPDATE",
    ACTIVITY_JOIN = "ACTIVITY_JOIN",
    QUEST_ENROLLMENT_STATUS_UPDATE = "QUEST_ENROLLMENT_STATUS_UPDATE"
}
export declare const DispatchEventFrame: zod.ZodObject<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    evt: zod.ZodNativeEnum<typeof Events>;
    nonce: zod.ZodNullable<zod.ZodString>;
    cmd: zod.ZodLiteral<"DISPATCH">;
    data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
}>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    evt: zod.ZodNativeEnum<typeof Events>;
    nonce: zod.ZodNullable<zod.ZodString>;
    cmd: zod.ZodLiteral<"DISPATCH">;
    data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
}>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    evt: zod.ZodNativeEnum<typeof Events>;
    nonce: zod.ZodNullable<zod.ZodString>;
    cmd: zod.ZodLiteral<"DISPATCH">;
    data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
}>, zod.ZodTypeAny, "passthrough">>;
export interface EventArgs<Z extends zod.AnyZodObject = zod.AnyZodObject> {
    payload: Z;
    subscribeArgs?: Z;
}
export type EventPayloadData<K extends keyof typeof EventSchema> = zod.infer<(typeof EventSchema)[K]['payload']>['data'];
export declare const ErrorEvent: zod.ZodObject<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    evt: zod.ZodLiteral<"ERROR">;
    data: zod.ZodObject<{
        code: zod.ZodNumber;
        message: zod.ZodOptional<zod.ZodString>;
    }, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{
        code: zod.ZodNumber;
        message: zod.ZodOptional<zod.ZodString>;
    }, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{
        code: zod.ZodNumber;
        message: zod.ZodOptional<zod.ZodString>;
    }, zod.ZodTypeAny, "passthrough">>;
    cmd: zod.ZodNativeEnum<typeof Commands>;
    nonce: zod.ZodNullable<zod.ZodString>;
}>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    evt: zod.ZodLiteral<"ERROR">;
    data: zod.ZodObject<{
        code: zod.ZodNumber;
        message: zod.ZodOptional<zod.ZodString>;
    }, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{
        code: zod.ZodNumber;
        message: zod.ZodOptional<zod.ZodString>;
    }, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{
        code: zod.ZodNumber;
        message: zod.ZodOptional<zod.ZodString>;
    }, zod.ZodTypeAny, "passthrough">>;
    cmd: zod.ZodNativeEnum<typeof Commands>;
    nonce: zod.ZodNullable<zod.ZodString>;
}>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    evt: zod.ZodLiteral<"ERROR">;
    data: zod.ZodObject<{
        code: zod.ZodNumber;
        message: zod.ZodOptional<zod.ZodString>;
    }, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{
        code: zod.ZodNumber;
        message: zod.ZodOptional<zod.ZodString>;
    }, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{
        code: zod.ZodNumber;
        message: zod.ZodOptional<zod.ZodString>;
    }, zod.ZodTypeAny, "passthrough">>;
    cmd: zod.ZodNativeEnum<typeof Commands>;
    nonce: zod.ZodNullable<zod.ZodString>;
}>, zod.ZodTypeAny, "passthrough">>;
export declare const OtherEvent: zod.ZodObject<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    evt: zod.ZodNativeEnum<typeof Events>;
    nonce: zod.ZodNullable<zod.ZodString>;
    cmd: zod.ZodLiteral<"DISPATCH">;
    data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
}>, {
    evt: zod.ZodString;
}>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    evt: zod.ZodNativeEnum<typeof Events>;
    nonce: zod.ZodNullable<zod.ZodString>;
    cmd: zod.ZodLiteral<"DISPATCH">;
    data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
}>, {
    evt: zod.ZodString;
}>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    evt: zod.ZodNativeEnum<typeof Events>;
    nonce: zod.ZodNullable<zod.ZodString>;
    cmd: zod.ZodLiteral<"DISPATCH">;
    data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
}>, {
    evt: zod.ZodString;
}>, zod.ZodTypeAny, "passthrough">>;
export declare const EventFrame: zod.ZodUnion<[zod.ZodObject<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    evt: zod.ZodNativeEnum<typeof Events>;
    nonce: zod.ZodNullable<zod.ZodString>;
    cmd: zod.ZodLiteral<"DISPATCH">;
    data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
}>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    evt: zod.ZodNativeEnum<typeof Events>;
    nonce: zod.ZodNullable<zod.ZodString>;
    cmd: zod.ZodLiteral<"DISPATCH">;
    data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
}>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    evt: zod.ZodNativeEnum<typeof Events>;
    nonce: zod.ZodNullable<zod.ZodString>;
    cmd: zod.ZodLiteral<"DISPATCH">;
    data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
}>, zod.ZodTypeAny, "passthrough">>, zod.ZodObject<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    evt: zod.ZodNativeEnum<typeof Events>;
    nonce: zod.ZodNullable<zod.ZodString>;
    cmd: zod.ZodLiteral<"DISPATCH">;
    data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
}>, {
    evt: zod.ZodString;
}>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    evt: zod.ZodNativeEnum<typeof Events>;
    nonce: zod.ZodNullable<zod.ZodString>;
    cmd: zod.ZodLiteral<"DISPATCH">;
    data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
}>, {
    evt: zod.ZodString;
}>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    evt: zod.ZodNativeEnum<typeof Events>;
    nonce: zod.ZodNullable<zod.ZodString>;
    cmd: zod.ZodLiteral<"DISPATCH">;
    data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
}>, {
    evt: zod.ZodString;
}>, zod.ZodTypeAny, "passthrough">>, zod.ZodObject<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    evt: zod.ZodLiteral<"ERROR">;
    data: zod.ZodObject<{
        code: zod.ZodNumber;
        message: zod.ZodOptional<zod.ZodString>;
    }, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{
        code: zod.ZodNumber;
        message: zod.ZodOptional<zod.ZodString>;
    }, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{
        code: zod.ZodNumber;
        message: zod.ZodOptional<zod.ZodString>;
    }, zod.ZodTypeAny, "passthrough">>;
    cmd: zod.ZodNativeEnum<typeof Commands>;
    nonce: zod.ZodNullable<zod.ZodString>;
}>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    evt: zod.ZodLiteral<"ERROR">;
    data: zod.ZodObject<{
        code: zod.ZodNumber;
        message: zod.ZodOptional<zod.ZodString>;
    }, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{
        code: zod.ZodNumber;
        message: zod.ZodOptional<zod.ZodString>;
    }, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{
        code: zod.ZodNumber;
        message: zod.ZodOptional<zod.ZodString>;
    }, zod.ZodTypeAny, "passthrough">>;
    cmd: zod.ZodNativeEnum<typeof Commands>;
    nonce: zod.ZodNullable<zod.ZodString>;
}>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    evt: zod.ZodLiteral<"ERROR">;
    data: zod.ZodObject<{
        code: zod.ZodNumber;
        message: zod.ZodOptional<zod.ZodString>;
    }, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{
        code: zod.ZodNumber;
        message: zod.ZodOptional<zod.ZodString>;
    }, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{
        code: zod.ZodNumber;
        message: zod.ZodOptional<zod.ZodString>;
    }, zod.ZodTypeAny, "passthrough">>;
    cmd: zod.ZodNativeEnum<typeof Commands>;
    nonce: zod.ZodNullable<zod.ZodString>;
}>, zod.ZodTypeAny, "passthrough">>]>;
export declare const VoiceConnectionStatusStateObject: {
    readonly UNHANDLED: -1;
    readonly DISCONNECTED: "DISCONNECTED";
    readonly AWAITING_ENDPOINT: "AWAITING_ENDPOINT";
    readonly AUTHENTICATING: "AUTHENTICATING";
    readonly CONNECTING: "CONNECTING";
    readonly CONNECTED: "CONNECTED";
    readonly VOICE_DISCONNECTED: "VOICE_DISCONNECTED";
    readonly VOICE_CONNECTING: "VOICE_CONNECTING";
    readonly VOICE_CONNECTED: "VOICE_CONNECTED";
    readonly NO_ROUTE: "NO_ROUTE";
    readonly ICE_CHECKING: "ICE_CHECKING";
};
export declare const ActivityJoinIntentObject: {
    readonly UNHANDLED: -1;
    readonly PLAY: 0;
    readonly SPECTATE: 1;
};
export declare function parseEventPayload<K extends keyof typeof EventSchema = keyof typeof EventSchema>(data: zod.infer<typeof EventFrame>): zod.infer<(typeof EventSchema)[K]['payload']>;
export declare const EventSchema: {
    /**
     * @description
     * The READY event is emitted by Discord's RPC server in reply to a client
     * initiating the RPC handshake. The event includes information about
     * - the rpc server version
     * - the discord client configuration
     * - the (basic) user object
     *
     * Unlike other events, READY will only be omitted once, immediately after the
     * Embedded App SDK is initialized
     *
     * # Supported Platforms
     * | Web | iOS | Android |
     * |-----|-----|---------|
     * | ✅  | ✅  | ✅      |
     *
     * Required scopes: []
     *
     */
    READY: {
        payload: zod.ZodObject<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.READY>;
            data: zod.ZodObject<{
                v: zod.ZodNumber;
                config: zod.ZodObject<{
                    cdn_host: zod.ZodOptional<zod.ZodString>;
                    api_endpoint: zod.ZodString;
                    environment: zod.ZodString;
                }, "strip", zod.ZodTypeAny, {
                    api_endpoint: string;
                    environment: string;
                    cdn_host?: string | undefined;
                }, {
                    api_endpoint: string;
                    environment: string;
                    cdn_host?: string | undefined;
                }>;
                user: zod.ZodOptional<zod.ZodObject<{
                    id: zod.ZodString;
                    username: zod.ZodString;
                    discriminator: zod.ZodString;
                    avatar: zod.ZodOptional<zod.ZodString>;
                }, "strip", zod.ZodTypeAny, {
                    username: string;
                    discriminator: string;
                    id: string;
                    avatar?: string | undefined;
                }, {
                    username: string;
                    discriminator: string;
                    id: string;
                    avatar?: string | undefined;
                }>>;
            }, "strip", zod.ZodTypeAny, {
                v: number;
                config: {
                    api_endpoint: string;
                    environment: string;
                    cdn_host?: string | undefined;
                };
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    avatar?: string | undefined;
                } | undefined;
            }, {
                v: number;
                config: {
                    api_endpoint: string;
                    environment: string;
                    cdn_host?: string | undefined;
                };
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    avatar?: string | undefined;
                } | undefined;
            }>;
        }>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.READY>;
            data: zod.ZodObject<{
                v: zod.ZodNumber;
                config: zod.ZodObject<{
                    cdn_host: zod.ZodOptional<zod.ZodString>;
                    api_endpoint: zod.ZodString;
                    environment: zod.ZodString;
                }, "strip", zod.ZodTypeAny, {
                    api_endpoint: string;
                    environment: string;
                    cdn_host?: string | undefined;
                }, {
                    api_endpoint: string;
                    environment: string;
                    cdn_host?: string | undefined;
                }>;
                user: zod.ZodOptional<zod.ZodObject<{
                    id: zod.ZodString;
                    username: zod.ZodString;
                    discriminator: zod.ZodString;
                    avatar: zod.ZodOptional<zod.ZodString>;
                }, "strip", zod.ZodTypeAny, {
                    username: string;
                    discriminator: string;
                    id: string;
                    avatar?: string | undefined;
                }, {
                    username: string;
                    discriminator: string;
                    id: string;
                    avatar?: string | undefined;
                }>>;
            }, "strip", zod.ZodTypeAny, {
                v: number;
                config: {
                    api_endpoint: string;
                    environment: string;
                    cdn_host?: string | undefined;
                };
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    avatar?: string | undefined;
                } | undefined;
            }, {
                v: number;
                config: {
                    api_endpoint: string;
                    environment: string;
                    cdn_host?: string | undefined;
                };
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    avatar?: string | undefined;
                } | undefined;
            }>;
        }>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.READY>;
            data: zod.ZodObject<{
                v: zod.ZodNumber;
                config: zod.ZodObject<{
                    cdn_host: zod.ZodOptional<zod.ZodString>;
                    api_endpoint: zod.ZodString;
                    environment: zod.ZodString;
                }, "strip", zod.ZodTypeAny, {
                    api_endpoint: string;
                    environment: string;
                    cdn_host?: string | undefined;
                }, {
                    api_endpoint: string;
                    environment: string;
                    cdn_host?: string | undefined;
                }>;
                user: zod.ZodOptional<zod.ZodObject<{
                    id: zod.ZodString;
                    username: zod.ZodString;
                    discriminator: zod.ZodString;
                    avatar: zod.ZodOptional<zod.ZodString>;
                }, "strip", zod.ZodTypeAny, {
                    username: string;
                    discriminator: string;
                    id: string;
                    avatar?: string | undefined;
                }, {
                    username: string;
                    discriminator: string;
                    id: string;
                    avatar?: string | undefined;
                }>>;
            }, "strip", zod.ZodTypeAny, {
                v: number;
                config: {
                    api_endpoint: string;
                    environment: string;
                    cdn_host?: string | undefined;
                };
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    avatar?: string | undefined;
                } | undefined;
            }, {
                v: number;
                config: {
                    api_endpoint: string;
                    environment: string;
                    cdn_host?: string | undefined;
                };
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    avatar?: string | undefined;
                } | undefined;
            }>;
        }>, zod.ZodTypeAny, "passthrough">>;
    };
    VOICE_STATE_UPDATE: {
        payload: zod.ZodObject<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.VOICE_STATE_UPDATE>;
            data: zod.ZodObject<{
                mute: zod.ZodBoolean;
                nick: zod.ZodString;
                user: zod.ZodObject<{
                    id: zod.ZodString;
                    username: zod.ZodString;
                    discriminator: zod.ZodString;
                    global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                        asset: zod.ZodString;
                        sku_id: zod.ZodOptional<zod.ZodString>;
                    }, "strip", zod.ZodTypeAny, {
                        asset: string;
                        sku_id?: string | undefined;
                    }, {
                        asset: string;
                        sku_id?: string | undefined;
                    }>>;
                    bot: zod.ZodBoolean;
                    flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                    premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                }, "strip", zod.ZodTypeAny, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                }, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                }>;
                voice_state: zod.ZodObject<{
                    mute: zod.ZodBoolean;
                    deaf: zod.ZodBoolean;
                    self_mute: zod.ZodBoolean;
                    self_deaf: zod.ZodBoolean;
                    suppress: zod.ZodBoolean;
                }, "strip", zod.ZodTypeAny, {
                    deaf: boolean;
                    mute: boolean;
                    self_mute: boolean;
                    self_deaf: boolean;
                    suppress: boolean;
                }, {
                    deaf: boolean;
                    mute: boolean;
                    self_mute: boolean;
                    self_deaf: boolean;
                    suppress: boolean;
                }>;
                volume: zod.ZodNumber;
            }, "strip", zod.ZodTypeAny, {
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                };
                nick: string;
                mute: boolean;
                voice_state: {
                    deaf: boolean;
                    mute: boolean;
                    self_mute: boolean;
                    self_deaf: boolean;
                    suppress: boolean;
                };
                volume: number;
            }, {
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                };
                nick: string;
                mute: boolean;
                voice_state: {
                    deaf: boolean;
                    mute: boolean;
                    self_mute: boolean;
                    self_deaf: boolean;
                    suppress: boolean;
                };
                volume: number;
            }>;
        }>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.VOICE_STATE_UPDATE>;
            data: zod.ZodObject<{
                mute: zod.ZodBoolean;
                nick: zod.ZodString;
                user: zod.ZodObject<{
                    id: zod.ZodString;
                    username: zod.ZodString;
                    discriminator: zod.ZodString;
                    global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                        asset: zod.ZodString;
                        sku_id: zod.ZodOptional<zod.ZodString>;
                    }, "strip", zod.ZodTypeAny, {
                        asset: string;
                        sku_id?: string | undefined;
                    }, {
                        asset: string;
                        sku_id?: string | undefined;
                    }>>;
                    bot: zod.ZodBoolean;
                    flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                    premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                }, "strip", zod.ZodTypeAny, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                }, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                }>;
                voice_state: zod.ZodObject<{
                    mute: zod.ZodBoolean;
                    deaf: zod.ZodBoolean;
                    self_mute: zod.ZodBoolean;
                    self_deaf: zod.ZodBoolean;
                    suppress: zod.ZodBoolean;
                }, "strip", zod.ZodTypeAny, {
                    deaf: boolean;
                    mute: boolean;
                    self_mute: boolean;
                    self_deaf: boolean;
                    suppress: boolean;
                }, {
                    deaf: boolean;
                    mute: boolean;
                    self_mute: boolean;
                    self_deaf: boolean;
                    suppress: boolean;
                }>;
                volume: zod.ZodNumber;
            }, "strip", zod.ZodTypeAny, {
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                };
                nick: string;
                mute: boolean;
                voice_state: {
                    deaf: boolean;
                    mute: boolean;
                    self_mute: boolean;
                    self_deaf: boolean;
                    suppress: boolean;
                };
                volume: number;
            }, {
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                };
                nick: string;
                mute: boolean;
                voice_state: {
                    deaf: boolean;
                    mute: boolean;
                    self_mute: boolean;
                    self_deaf: boolean;
                    suppress: boolean;
                };
                volume: number;
            }>;
        }>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.VOICE_STATE_UPDATE>;
            data: zod.ZodObject<{
                mute: zod.ZodBoolean;
                nick: zod.ZodString;
                user: zod.ZodObject<{
                    id: zod.ZodString;
                    username: zod.ZodString;
                    discriminator: zod.ZodString;
                    global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                        asset: zod.ZodString;
                        sku_id: zod.ZodOptional<zod.ZodString>;
                    }, "strip", zod.ZodTypeAny, {
                        asset: string;
                        sku_id?: string | undefined;
                    }, {
                        asset: string;
                        sku_id?: string | undefined;
                    }>>;
                    bot: zod.ZodBoolean;
                    flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                    premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                }, "strip", zod.ZodTypeAny, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                }, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                }>;
                voice_state: zod.ZodObject<{
                    mute: zod.ZodBoolean;
                    deaf: zod.ZodBoolean;
                    self_mute: zod.ZodBoolean;
                    self_deaf: zod.ZodBoolean;
                    suppress: zod.ZodBoolean;
                }, "strip", zod.ZodTypeAny, {
                    deaf: boolean;
                    mute: boolean;
                    self_mute: boolean;
                    self_deaf: boolean;
                    suppress: boolean;
                }, {
                    deaf: boolean;
                    mute: boolean;
                    self_mute: boolean;
                    self_deaf: boolean;
                    suppress: boolean;
                }>;
                volume: zod.ZodNumber;
            }, "strip", zod.ZodTypeAny, {
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                };
                nick: string;
                mute: boolean;
                voice_state: {
                    deaf: boolean;
                    mute: boolean;
                    self_mute: boolean;
                    self_deaf: boolean;
                    suppress: boolean;
                };
                volume: number;
            }, {
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                };
                nick: string;
                mute: boolean;
                voice_state: {
                    deaf: boolean;
                    mute: boolean;
                    self_mute: boolean;
                    self_deaf: boolean;
                    suppress: boolean;
                };
                volume: number;
            }>;
        }>, zod.ZodTypeAny, "passthrough">>;
        subscribeArgs: zod.ZodObject<{
            channel_id: zod.ZodString;
        }, "strip", zod.ZodTypeAny, {
            channel_id: string;
        }, {
            channel_id: string;
        }>;
    };
    SPEAKING_START: {
        payload: zod.ZodObject<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.SPEAKING_START>;
            data: zod.ZodObject<{
                lobby_id: zod.ZodOptional<zod.ZodString>;
                channel_id: zod.ZodOptional<zod.ZodString>;
                user_id: zod.ZodString;
            }, "strip", zod.ZodTypeAny, {
                user_id: string;
                channel_id?: string | undefined;
                lobby_id?: string | undefined;
            }, {
                user_id: string;
                channel_id?: string | undefined;
                lobby_id?: string | undefined;
            }>;
        }>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.SPEAKING_START>;
            data: zod.ZodObject<{
                lobby_id: zod.ZodOptional<zod.ZodString>;
                channel_id: zod.ZodOptional<zod.ZodString>;
                user_id: zod.ZodString;
            }, "strip", zod.ZodTypeAny, {
                user_id: string;
                channel_id?: string | undefined;
                lobby_id?: string | undefined;
            }, {
                user_id: string;
                channel_id?: string | undefined;
                lobby_id?: string | undefined;
            }>;
        }>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.SPEAKING_START>;
            data: zod.ZodObject<{
                lobby_id: zod.ZodOptional<zod.ZodString>;
                channel_id: zod.ZodOptional<zod.ZodString>;
                user_id: zod.ZodString;
            }, "strip", zod.ZodTypeAny, {
                user_id: string;
                channel_id?: string | undefined;
                lobby_id?: string | undefined;
            }, {
                user_id: string;
                channel_id?: string | undefined;
                lobby_id?: string | undefined;
            }>;
        }>, zod.ZodTypeAny, "passthrough">>;
        subscribeArgs: zod.ZodObject<{
            lobby_id: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
            channel_id: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
        }, "strip", zod.ZodTypeAny, {
            channel_id?: string | null | undefined;
            lobby_id?: string | null | undefined;
        }, {
            channel_id?: string | null | undefined;
            lobby_id?: string | null | undefined;
        }>;
    };
    SPEAKING_STOP: {
        payload: zod.ZodObject<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.SPEAKING_STOP>;
            data: zod.ZodObject<{
                lobby_id: zod.ZodOptional<zod.ZodString>;
                channel_id: zod.ZodOptional<zod.ZodString>;
                user_id: zod.ZodString;
            }, "strip", zod.ZodTypeAny, {
                user_id: string;
                channel_id?: string | undefined;
                lobby_id?: string | undefined;
            }, {
                user_id: string;
                channel_id?: string | undefined;
                lobby_id?: string | undefined;
            }>;
        }>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.SPEAKING_STOP>;
            data: zod.ZodObject<{
                lobby_id: zod.ZodOptional<zod.ZodString>;
                channel_id: zod.ZodOptional<zod.ZodString>;
                user_id: zod.ZodString;
            }, "strip", zod.ZodTypeAny, {
                user_id: string;
                channel_id?: string | undefined;
                lobby_id?: string | undefined;
            }, {
                user_id: string;
                channel_id?: string | undefined;
                lobby_id?: string | undefined;
            }>;
        }>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.SPEAKING_STOP>;
            data: zod.ZodObject<{
                lobby_id: zod.ZodOptional<zod.ZodString>;
                channel_id: zod.ZodOptional<zod.ZodString>;
                user_id: zod.ZodString;
            }, "strip", zod.ZodTypeAny, {
                user_id: string;
                channel_id?: string | undefined;
                lobby_id?: string | undefined;
            }, {
                user_id: string;
                channel_id?: string | undefined;
                lobby_id?: string | undefined;
            }>;
        }>, zod.ZodTypeAny, "passthrough">>;
        subscribeArgs: zod.ZodObject<{
            lobby_id: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
            channel_id: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
        }, "strip", zod.ZodTypeAny, {
            channel_id?: string | null | undefined;
            lobby_id?: string | null | undefined;
        }, {
            channel_id?: string | null | undefined;
            lobby_id?: string | null | undefined;
        }>;
    };
    ACTIVITY_LAYOUT_MODE_UPDATE: {
        payload: zod.ZodObject<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.ACTIVITY_LAYOUT_MODE_UPDATE>;
            data: zod.ZodObject<{
                layout_mode: zod.ZodEffects<zod.ZodType<0 | 1 | 2 | -1, zod.ZodTypeDef, 0 | 1 | 2 | -1>, 0 | 1 | 2 | -1, unknown>;
            }, "strip", zod.ZodTypeAny, {
                layout_mode: 0 | 1 | 2 | -1;
            }, {
                layout_mode?: unknown;
            }>;
        }>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.ACTIVITY_LAYOUT_MODE_UPDATE>;
            data: zod.ZodObject<{
                layout_mode: zod.ZodEffects<zod.ZodType<0 | 1 | 2 | -1, zod.ZodTypeDef, 0 | 1 | 2 | -1>, 0 | 1 | 2 | -1, unknown>;
            }, "strip", zod.ZodTypeAny, {
                layout_mode: 0 | 1 | 2 | -1;
            }, {
                layout_mode?: unknown;
            }>;
        }>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.ACTIVITY_LAYOUT_MODE_UPDATE>;
            data: zod.ZodObject<{
                layout_mode: zod.ZodEffects<zod.ZodType<0 | 1 | 2 | -1, zod.ZodTypeDef, 0 | 1 | 2 | -1>, 0 | 1 | 2 | -1, unknown>;
            }, "strip", zod.ZodTypeAny, {
                layout_mode: 0 | 1 | 2 | -1;
            }, {
                layout_mode?: unknown;
            }>;
        }>, zod.ZodTypeAny, "passthrough">>;
    };
    ORIENTATION_UPDATE: {
        payload: zod.ZodObject<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.ORIENTATION_UPDATE>;
            data: zod.ZodObject<{
                screen_orientation: zod.ZodEffects<zod.ZodType<0 | 1 | -1, zod.ZodTypeDef, 0 | 1 | -1>, 0 | 1 | -1, unknown>;
                /**
                 * @deprecated use screen_orientation instead
                 */
                orientation: zod.ZodNativeEnum<typeof Orientation>;
            }, "strip", zod.ZodTypeAny, {
                screen_orientation: 0 | 1 | -1;
                orientation: Orientation;
            }, {
                orientation: Orientation;
                screen_orientation?: unknown;
            }>;
        }>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.ORIENTATION_UPDATE>;
            data: zod.ZodObject<{
                screen_orientation: zod.ZodEffects<zod.ZodType<0 | 1 | -1, zod.ZodTypeDef, 0 | 1 | -1>, 0 | 1 | -1, unknown>;
                /**
                 * @deprecated use screen_orientation instead
                 */
                orientation: zod.ZodNativeEnum<typeof Orientation>;
            }, "strip", zod.ZodTypeAny, {
                screen_orientation: 0 | 1 | -1;
                orientation: Orientation;
            }, {
                orientation: Orientation;
                screen_orientation?: unknown;
            }>;
        }>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.ORIENTATION_UPDATE>;
            data: zod.ZodObject<{
                screen_orientation: zod.ZodEffects<zod.ZodType<0 | 1 | -1, zod.ZodTypeDef, 0 | 1 | -1>, 0 | 1 | -1, unknown>;
                /**
                 * @deprecated use screen_orientation instead
                 */
                orientation: zod.ZodNativeEnum<typeof Orientation>;
            }, "strip", zod.ZodTypeAny, {
                screen_orientation: 0 | 1 | -1;
                orientation: Orientation;
            }, {
                orientation: Orientation;
                screen_orientation?: unknown;
            }>;
        }>, zod.ZodTypeAny, "passthrough">>;
    };
    CURRENT_USER_UPDATE: {
        payload: zod.ZodObject<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.CURRENT_USER_UPDATE>;
            data: zod.ZodObject<{
                id: zod.ZodString;
                username: zod.ZodString;
                discriminator: zod.ZodString;
                global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                    asset: zod.ZodString;
                    sku_id: zod.ZodOptional<zod.ZodString>;
                }, "strip", zod.ZodTypeAny, {
                    asset: string;
                    sku_id?: string | undefined;
                }, {
                    asset: string;
                    sku_id?: string | undefined;
                }>>;
                bot: zod.ZodBoolean;
                flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "strip", zod.ZodTypeAny, {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            }, {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            }>;
        }>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.CURRENT_USER_UPDATE>;
            data: zod.ZodObject<{
                id: zod.ZodString;
                username: zod.ZodString;
                discriminator: zod.ZodString;
                global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                    asset: zod.ZodString;
                    sku_id: zod.ZodOptional<zod.ZodString>;
                }, "strip", zod.ZodTypeAny, {
                    asset: string;
                    sku_id?: string | undefined;
                }, {
                    asset: string;
                    sku_id?: string | undefined;
                }>>;
                bot: zod.ZodBoolean;
                flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "strip", zod.ZodTypeAny, {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            }, {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            }>;
        }>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.CURRENT_USER_UPDATE>;
            data: zod.ZodObject<{
                id: zod.ZodString;
                username: zod.ZodString;
                discriminator: zod.ZodString;
                global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                    asset: zod.ZodString;
                    sku_id: zod.ZodOptional<zod.ZodString>;
                }, "strip", zod.ZodTypeAny, {
                    asset: string;
                    sku_id?: string | undefined;
                }, {
                    asset: string;
                    sku_id?: string | undefined;
                }>>;
                bot: zod.ZodBoolean;
                flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "strip", zod.ZodTypeAny, {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            }, {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            }>;
        }>, zod.ZodTypeAny, "passthrough">>;
    };
    CURRENT_GUILD_MEMBER_UPDATE: {
        payload: zod.ZodObject<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.CURRENT_GUILD_MEMBER_UPDATE>;
            data: zod.ZodObject<{
                user_id: zod.ZodString;
                nick: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                guild_id: zod.ZodString;
                avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar_decoration_data: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                    asset: zod.ZodString;
                    sku_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                }, "strip", zod.ZodTypeAny, {
                    asset: string;
                    sku_id?: string | null | undefined;
                }, {
                    asset: string;
                    sku_id?: string | null | undefined;
                }>>>;
                color_string: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            }, "strip", zod.ZodTypeAny, {
                user_id: string;
                guild_id: string;
                avatar?: string | null | undefined;
                avatar_decoration_data?: {
                    asset: string;
                    sku_id?: string | null | undefined;
                } | null | undefined;
                nick?: string | null | undefined;
                color_string?: string | null | undefined;
            }, {
                user_id: string;
                guild_id: string;
                avatar?: string | null | undefined;
                avatar_decoration_data?: {
                    asset: string;
                    sku_id?: string | null | undefined;
                } | null | undefined;
                nick?: string | null | undefined;
                color_string?: string | null | undefined;
            }>;
        }>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.CURRENT_GUILD_MEMBER_UPDATE>;
            data: zod.ZodObject<{
                user_id: zod.ZodString;
                nick: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                guild_id: zod.ZodString;
                avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar_decoration_data: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                    asset: zod.ZodString;
                    sku_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                }, "strip", zod.ZodTypeAny, {
                    asset: string;
                    sku_id?: string | null | undefined;
                }, {
                    asset: string;
                    sku_id?: string | null | undefined;
                }>>>;
                color_string: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            }, "strip", zod.ZodTypeAny, {
                user_id: string;
                guild_id: string;
                avatar?: string | null | undefined;
                avatar_decoration_data?: {
                    asset: string;
                    sku_id?: string | null | undefined;
                } | null | undefined;
                nick?: string | null | undefined;
                color_string?: string | null | undefined;
            }, {
                user_id: string;
                guild_id: string;
                avatar?: string | null | undefined;
                avatar_decoration_data?: {
                    asset: string;
                    sku_id?: string | null | undefined;
                } | null | undefined;
                nick?: string | null | undefined;
                color_string?: string | null | undefined;
            }>;
        }>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.CURRENT_GUILD_MEMBER_UPDATE>;
            data: zod.ZodObject<{
                user_id: zod.ZodString;
                nick: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                guild_id: zod.ZodString;
                avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar_decoration_data: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                    asset: zod.ZodString;
                    sku_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                }, "strip", zod.ZodTypeAny, {
                    asset: string;
                    sku_id?: string | null | undefined;
                }, {
                    asset: string;
                    sku_id?: string | null | undefined;
                }>>>;
                color_string: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            }, "strip", zod.ZodTypeAny, {
                user_id: string;
                guild_id: string;
                avatar?: string | null | undefined;
                avatar_decoration_data?: {
                    asset: string;
                    sku_id?: string | null | undefined;
                } | null | undefined;
                nick?: string | null | undefined;
                color_string?: string | null | undefined;
            }, {
                user_id: string;
                guild_id: string;
                avatar?: string | null | undefined;
                avatar_decoration_data?: {
                    asset: string;
                    sku_id?: string | null | undefined;
                } | null | undefined;
                nick?: string | null | undefined;
                color_string?: string | null | undefined;
            }>;
        }>, zod.ZodTypeAny, "passthrough">>;
        subscribeArgs: zod.ZodObject<{
            guild_id: zod.ZodString;
        }, "strip", zod.ZodTypeAny, {
            guild_id: string;
        }, {
            guild_id: string;
        }>;
    };
    ENTITLEMENT_CREATE: {
        payload: zod.ZodObject<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.ENTITLEMENT_CREATE>;
            data: zod.ZodObject<{
                entitlement: zod.ZodObject<{
                    id: zod.ZodString;
                    sku_id: zod.ZodString;
                    application_id: zod.ZodString;
                    user_id: zod.ZodString;
                    gift_code_flags: zod.ZodNumber;
                    type: zod.ZodEffects<zod.ZodType<1 | 4 | 2 | 3 | 5 | 6 | 7 | -1, zod.ZodTypeDef, 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1>, 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1, unknown>;
                    gifter_user_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    branches: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>>;
                    starts_at: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    ends_at: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    parent_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    consumed: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                    deleted: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                    gift_code_batch_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                }, "strip", zod.ZodTypeAny, {
                    type: 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1;
                    id: string;
                    application_id: string;
                    user_id: string;
                    sku_id: string;
                    gift_code_flags: number;
                    parent_id?: string | null | undefined;
                    gifter_user_id?: string | null | undefined;
                    branches?: string[] | null | undefined;
                    starts_at?: string | null | undefined;
                    ends_at?: string | null | undefined;
                    consumed?: boolean | null | undefined;
                    deleted?: boolean | null | undefined;
                    gift_code_batch_id?: string | null | undefined;
                }, {
                    id: string;
                    application_id: string;
                    user_id: string;
                    sku_id: string;
                    gift_code_flags: number;
                    type?: unknown;
                    parent_id?: string | null | undefined;
                    gifter_user_id?: string | null | undefined;
                    branches?: string[] | null | undefined;
                    starts_at?: string | null | undefined;
                    ends_at?: string | null | undefined;
                    consumed?: boolean | null | undefined;
                    deleted?: boolean | null | undefined;
                    gift_code_batch_id?: string | null | undefined;
                }>;
            }, "strip", zod.ZodTypeAny, {
                entitlement: {
                    type: 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1;
                    id: string;
                    application_id: string;
                    user_id: string;
                    sku_id: string;
                    gift_code_flags: number;
                    parent_id?: string | null | undefined;
                    gifter_user_id?: string | null | undefined;
                    branches?: string[] | null | undefined;
                    starts_at?: string | null | undefined;
                    ends_at?: string | null | undefined;
                    consumed?: boolean | null | undefined;
                    deleted?: boolean | null | undefined;
                    gift_code_batch_id?: string | null | undefined;
                };
            }, {
                entitlement: {
                    id: string;
                    application_id: string;
                    user_id: string;
                    sku_id: string;
                    gift_code_flags: number;
                    type?: unknown;
                    parent_id?: string | null | undefined;
                    gifter_user_id?: string | null | undefined;
                    branches?: string[] | null | undefined;
                    starts_at?: string | null | undefined;
                    ends_at?: string | null | undefined;
                    consumed?: boolean | null | undefined;
                    deleted?: boolean | null | undefined;
                    gift_code_batch_id?: string | null | undefined;
                };
            }>;
        }>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.ENTITLEMENT_CREATE>;
            data: zod.ZodObject<{
                entitlement: zod.ZodObject<{
                    id: zod.ZodString;
                    sku_id: zod.ZodString;
                    application_id: zod.ZodString;
                    user_id: zod.ZodString;
                    gift_code_flags: zod.ZodNumber;
                    type: zod.ZodEffects<zod.ZodType<1 | 4 | 2 | 3 | 5 | 6 | 7 | -1, zod.ZodTypeDef, 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1>, 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1, unknown>;
                    gifter_user_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    branches: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>>;
                    starts_at: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    ends_at: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    parent_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    consumed: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                    deleted: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                    gift_code_batch_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                }, "strip", zod.ZodTypeAny, {
                    type: 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1;
                    id: string;
                    application_id: string;
                    user_id: string;
                    sku_id: string;
                    gift_code_flags: number;
                    parent_id?: string | null | undefined;
                    gifter_user_id?: string | null | undefined;
                    branches?: string[] | null | undefined;
                    starts_at?: string | null | undefined;
                    ends_at?: string | null | undefined;
                    consumed?: boolean | null | undefined;
                    deleted?: boolean | null | undefined;
                    gift_code_batch_id?: string | null | undefined;
                }, {
                    id: string;
                    application_id: string;
                    user_id: string;
                    sku_id: string;
                    gift_code_flags: number;
                    type?: unknown;
                    parent_id?: string | null | undefined;
                    gifter_user_id?: string | null | undefined;
                    branches?: string[] | null | undefined;
                    starts_at?: string | null | undefined;
                    ends_at?: string | null | undefined;
                    consumed?: boolean | null | undefined;
                    deleted?: boolean | null | undefined;
                    gift_code_batch_id?: string | null | undefined;
                }>;
            }, "strip", zod.ZodTypeAny, {
                entitlement: {
                    type: 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1;
                    id: string;
                    application_id: string;
                    user_id: string;
                    sku_id: string;
                    gift_code_flags: number;
                    parent_id?: string | null | undefined;
                    gifter_user_id?: string | null | undefined;
                    branches?: string[] | null | undefined;
                    starts_at?: string | null | undefined;
                    ends_at?: string | null | undefined;
                    consumed?: boolean | null | undefined;
                    deleted?: boolean | null | undefined;
                    gift_code_batch_id?: string | null | undefined;
                };
            }, {
                entitlement: {
                    id: string;
                    application_id: string;
                    user_id: string;
                    sku_id: string;
                    gift_code_flags: number;
                    type?: unknown;
                    parent_id?: string | null | undefined;
                    gifter_user_id?: string | null | undefined;
                    branches?: string[] | null | undefined;
                    starts_at?: string | null | undefined;
                    ends_at?: string | null | undefined;
                    consumed?: boolean | null | undefined;
                    deleted?: boolean | null | undefined;
                    gift_code_batch_id?: string | null | undefined;
                };
            }>;
        }>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.ENTITLEMENT_CREATE>;
            data: zod.ZodObject<{
                entitlement: zod.ZodObject<{
                    id: zod.ZodString;
                    sku_id: zod.ZodString;
                    application_id: zod.ZodString;
                    user_id: zod.ZodString;
                    gift_code_flags: zod.ZodNumber;
                    type: zod.ZodEffects<zod.ZodType<1 | 4 | 2 | 3 | 5 | 6 | 7 | -1, zod.ZodTypeDef, 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1>, 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1, unknown>;
                    gifter_user_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    branches: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>>;
                    starts_at: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    ends_at: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    parent_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    consumed: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                    deleted: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                    gift_code_batch_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                }, "strip", zod.ZodTypeAny, {
                    type: 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1;
                    id: string;
                    application_id: string;
                    user_id: string;
                    sku_id: string;
                    gift_code_flags: number;
                    parent_id?: string | null | undefined;
                    gifter_user_id?: string | null | undefined;
                    branches?: string[] | null | undefined;
                    starts_at?: string | null | undefined;
                    ends_at?: string | null | undefined;
                    consumed?: boolean | null | undefined;
                    deleted?: boolean | null | undefined;
                    gift_code_batch_id?: string | null | undefined;
                }, {
                    id: string;
                    application_id: string;
                    user_id: string;
                    sku_id: string;
                    gift_code_flags: number;
                    type?: unknown;
                    parent_id?: string | null | undefined;
                    gifter_user_id?: string | null | undefined;
                    branches?: string[] | null | undefined;
                    starts_at?: string | null | undefined;
                    ends_at?: string | null | undefined;
                    consumed?: boolean | null | undefined;
                    deleted?: boolean | null | undefined;
                    gift_code_batch_id?: string | null | undefined;
                }>;
            }, "strip", zod.ZodTypeAny, {
                entitlement: {
                    type: 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1;
                    id: string;
                    application_id: string;
                    user_id: string;
                    sku_id: string;
                    gift_code_flags: number;
                    parent_id?: string | null | undefined;
                    gifter_user_id?: string | null | undefined;
                    branches?: string[] | null | undefined;
                    starts_at?: string | null | undefined;
                    ends_at?: string | null | undefined;
                    consumed?: boolean | null | undefined;
                    deleted?: boolean | null | undefined;
                    gift_code_batch_id?: string | null | undefined;
                };
            }, {
                entitlement: {
                    id: string;
                    application_id: string;
                    user_id: string;
                    sku_id: string;
                    gift_code_flags: number;
                    type?: unknown;
                    parent_id?: string | null | undefined;
                    gifter_user_id?: string | null | undefined;
                    branches?: string[] | null | undefined;
                    starts_at?: string | null | undefined;
                    ends_at?: string | null | undefined;
                    consumed?: boolean | null | undefined;
                    deleted?: boolean | null | undefined;
                    gift_code_batch_id?: string | null | undefined;
                };
            }>;
        }>, zod.ZodTypeAny, "passthrough">>;
    };
    THERMAL_STATE_UPDATE: {
        payload: zod.ZodObject<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.THERMAL_STATE_UPDATE>;
            data: zod.ZodObject<{
                thermal_state: zod.ZodEffects<zod.ZodType<0 | 1 | 2 | 3 | -1, zod.ZodTypeDef, 0 | 1 | 2 | 3 | -1>, 0 | 1 | 2 | 3 | -1, unknown>;
            }, "strip", zod.ZodTypeAny, {
                thermal_state: 0 | 1 | 2 | 3 | -1;
            }, {
                thermal_state?: unknown;
            }>;
        }>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.THERMAL_STATE_UPDATE>;
            data: zod.ZodObject<{
                thermal_state: zod.ZodEffects<zod.ZodType<0 | 1 | 2 | 3 | -1, zod.ZodTypeDef, 0 | 1 | 2 | 3 | -1>, 0 | 1 | 2 | 3 | -1, unknown>;
            }, "strip", zod.ZodTypeAny, {
                thermal_state: 0 | 1 | 2 | 3 | -1;
            }, {
                thermal_state?: unknown;
            }>;
        }>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.THERMAL_STATE_UPDATE>;
            data: zod.ZodObject<{
                thermal_state: zod.ZodEffects<zod.ZodType<0 | 1 | 2 | 3 | -1, zod.ZodTypeDef, 0 | 1 | 2 | 3 | -1>, 0 | 1 | 2 | 3 | -1, unknown>;
            }, "strip", zod.ZodTypeAny, {
                thermal_state: 0 | 1 | 2 | 3 | -1;
            }, {
                thermal_state?: unknown;
            }>;
        }>, zod.ZodTypeAny, "passthrough">>;
    };
    ACTIVITY_INSTANCE_PARTICIPANTS_UPDATE: {
        payload: zod.ZodObject<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.ACTIVITY_INSTANCE_PARTICIPANTS_UPDATE>;
            data: zod.ZodObject<{
                participants: zod.ZodArray<zod.ZodObject<{
                    id: zod.ZodString;
                    username: zod.ZodString;
                    global_name: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
                    discriminator: zod.ZodString;
                    avatar: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
                    flags: zod.ZodNumber;
                    bot: zod.ZodBoolean;
                    avatar_decoration_data: zod.ZodOptional<zod.ZodUnion<[zod.ZodObject<{
                        asset: zod.ZodString;
                        skuId: zod.ZodOptional<zod.ZodString>;
                        expiresAt: zod.ZodOptional<zod.ZodNumber>;
                    }, "strip", zod.ZodTypeAny, {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    }, {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    }>, zod.ZodNull]>>;
                    premium_type: zod.ZodOptional<zod.ZodUnion<[zod.ZodNumber, zod.ZodNull]>>;
                    nickname: zod.ZodOptional<zod.ZodString>;
                }, "strip", zod.ZodTypeAny, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                    nickname?: string | undefined;
                }, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                    nickname?: string | undefined;
                }>, "many">;
            }, "strip", zod.ZodTypeAny, {
                participants: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                    nickname?: string | undefined;
                }[];
            }, {
                participants: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                    nickname?: string | undefined;
                }[];
            }>;
        }>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.ACTIVITY_INSTANCE_PARTICIPANTS_UPDATE>;
            data: zod.ZodObject<{
                participants: zod.ZodArray<zod.ZodObject<{
                    id: zod.ZodString;
                    username: zod.ZodString;
                    global_name: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
                    discriminator: zod.ZodString;
                    avatar: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
                    flags: zod.ZodNumber;
                    bot: zod.ZodBoolean;
                    avatar_decoration_data: zod.ZodOptional<zod.ZodUnion<[zod.ZodObject<{
                        asset: zod.ZodString;
                        skuId: zod.ZodOptional<zod.ZodString>;
                        expiresAt: zod.ZodOptional<zod.ZodNumber>;
                    }, "strip", zod.ZodTypeAny, {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    }, {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    }>, zod.ZodNull]>>;
                    premium_type: zod.ZodOptional<zod.ZodUnion<[zod.ZodNumber, zod.ZodNull]>>;
                    nickname: zod.ZodOptional<zod.ZodString>;
                }, "strip", zod.ZodTypeAny, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                    nickname?: string | undefined;
                }, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                    nickname?: string | undefined;
                }>, "many">;
            }, "strip", zod.ZodTypeAny, {
                participants: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                    nickname?: string | undefined;
                }[];
            }, {
                participants: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                    nickname?: string | undefined;
                }[];
            }>;
        }>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.ACTIVITY_INSTANCE_PARTICIPANTS_UPDATE>;
            data: zod.ZodObject<{
                participants: zod.ZodArray<zod.ZodObject<{
                    id: zod.ZodString;
                    username: zod.ZodString;
                    global_name: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
                    discriminator: zod.ZodString;
                    avatar: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
                    flags: zod.ZodNumber;
                    bot: zod.ZodBoolean;
                    avatar_decoration_data: zod.ZodOptional<zod.ZodUnion<[zod.ZodObject<{
                        asset: zod.ZodString;
                        skuId: zod.ZodOptional<zod.ZodString>;
                        expiresAt: zod.ZodOptional<zod.ZodNumber>;
                    }, "strip", zod.ZodTypeAny, {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    }, {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    }>, zod.ZodNull]>>;
                    premium_type: zod.ZodOptional<zod.ZodUnion<[zod.ZodNumber, zod.ZodNull]>>;
                    nickname: zod.ZodOptional<zod.ZodString>;
                }, "strip", zod.ZodTypeAny, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                    nickname?: string | undefined;
                }, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                    nickname?: string | undefined;
                }>, "many">;
            }, "strip", zod.ZodTypeAny, {
                participants: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                    nickname?: string | undefined;
                }[];
            }, {
                participants: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                    nickname?: string | undefined;
                }[];
            }>;
        }>, zod.ZodTypeAny, "passthrough">>;
    };
    RELATIONSHIP_UPDATE: {
        payload: zod.ZodObject<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.RELATIONSHIP_UPDATE>;
            data: zod.ZodObject<{
                type: zod.ZodNumber;
                user: zod.ZodObject<{
                    id: zod.ZodString;
                    username: zod.ZodString;
                    global_name: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
                    discriminator: zod.ZodString;
                    avatar: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
                    flags: zod.ZodNumber;
                    bot: zod.ZodBoolean;
                    avatar_decoration_data: zod.ZodOptional<zod.ZodUnion<[zod.ZodObject<{
                        asset: zod.ZodString;
                        skuId: zod.ZodOptional<zod.ZodString>;
                        expiresAt: zod.ZodOptional<zod.ZodNumber>;
                    }, "strip", zod.ZodTypeAny, {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    }, {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    }>, zod.ZodNull]>>;
                    premium_type: zod.ZodOptional<zod.ZodUnion<[zod.ZodNumber, zod.ZodNull]>>;
                }, "strip", zod.ZodTypeAny, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                }, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                }>;
                presence: zod.ZodOptional<zod.ZodObject<{
                    status: zod.ZodString;
                    activity: zod.ZodOptional<zod.ZodUnion<[zod.ZodObject<{
                        session_id: zod.ZodOptional<zod.ZodString>;
                        type: zod.ZodOptional<zod.ZodNumber>;
                        name: zod.ZodString;
                        url: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
                        application_id: zod.ZodOptional<zod.ZodString>;
                        status_display_type: zod.ZodOptional<zod.ZodNumber>;
                        state: zod.ZodOptional<zod.ZodString>;
                        state_url: zod.ZodOptional<zod.ZodString>;
                        details: zod.ZodOptional<zod.ZodString>;
                        details_url: zod.ZodOptional<zod.ZodString>;
                        emoji: zod.ZodOptional<zod.ZodUnion<[zod.ZodObject<{
                            name: zod.ZodString;
                            id: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
                            animated: zod.ZodOptional<zod.ZodUnion<[zod.ZodBoolean, zod.ZodNull]>>;
                        }, "strip", zod.ZodTypeAny, {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        }, {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        }>, zod.ZodNull]>>;
                        assets: zod.ZodOptional<zod.ZodObject<{
                            large_image: zod.ZodOptional<zod.ZodString>;
                            large_text: zod.ZodOptional<zod.ZodString>;
                            large_url: zod.ZodOptional<zod.ZodString>;
                            small_image: zod.ZodOptional<zod.ZodString>;
                            small_text: zod.ZodOptional<zod.ZodString>;
                            small_url: zod.ZodOptional<zod.ZodString>;
                        }, "strip", zod.ZodTypeAny, {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        }, {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        }>>;
                        timestamps: zod.ZodOptional<zod.ZodObject<{
                            start: zod.ZodOptional<zod.ZodNumber>;
                            end: zod.ZodOptional<zod.ZodNumber>;
                        }, "strip", zod.ZodTypeAny, {
                            start?: number | undefined;
                            end?: number | undefined;
                        }, {
                            start?: number | undefined;
                            end?: number | undefined;
                        }>>;
                        party: zod.ZodOptional<zod.ZodObject<{
                            id: zod.ZodOptional<zod.ZodString>;
                            size: zod.ZodOptional<zod.ZodArray<zod.ZodNumber, "many">>;
                            privacy: zod.ZodOptional<zod.ZodNumber>;
                        }, "strip", zod.ZodTypeAny, {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        }, {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        }>>;
                        secrets: zod.ZodOptional<zod.ZodObject<{
                            match: zod.ZodOptional<zod.ZodString>;
                            join: zod.ZodOptional<zod.ZodString>;
                        }, "strip", zod.ZodTypeAny, {
                            join?: string | undefined;
                            match?: string | undefined;
                        }, {
                            join?: string | undefined;
                            match?: string | undefined;
                        }>>;
                        sync_id: zod.ZodOptional<zod.ZodString>;
                        created_at: zod.ZodOptional<zod.ZodNumber>;
                        instance: zod.ZodOptional<zod.ZodBoolean>;
                        flags: zod.ZodOptional<zod.ZodNumber>;
                        metadata: zod.ZodOptional<zod.ZodObject<{}, "strip", zod.ZodTypeAny, {}, {}>>;
                        platform: zod.ZodOptional<zod.ZodString>;
                        supported_platforms: zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>;
                        buttons: zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>;
                        hangStatus: zod.ZodOptional<zod.ZodString>;
                    }, "strip", zod.ZodTypeAny, {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    }, {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    }>, zod.ZodNull]>>;
                }, "strip", zod.ZodTypeAny, {
                    status: string;
                    activity?: {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    } | null | undefined;
                }, {
                    status: string;
                    activity?: {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    } | null | undefined;
                }>>;
            }, "strip", zod.ZodTypeAny, {
                type: number;
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                };
                presence?: {
                    status: string;
                    activity?: {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    } | null | undefined;
                } | undefined;
            }, {
                type: number;
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                };
                presence?: {
                    status: string;
                    activity?: {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    } | null | undefined;
                } | undefined;
            }>;
        }>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.RELATIONSHIP_UPDATE>;
            data: zod.ZodObject<{
                type: zod.ZodNumber;
                user: zod.ZodObject<{
                    id: zod.ZodString;
                    username: zod.ZodString;
                    global_name: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
                    discriminator: zod.ZodString;
                    avatar: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
                    flags: zod.ZodNumber;
                    bot: zod.ZodBoolean;
                    avatar_decoration_data: zod.ZodOptional<zod.ZodUnion<[zod.ZodObject<{
                        asset: zod.ZodString;
                        skuId: zod.ZodOptional<zod.ZodString>;
                        expiresAt: zod.ZodOptional<zod.ZodNumber>;
                    }, "strip", zod.ZodTypeAny, {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    }, {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    }>, zod.ZodNull]>>;
                    premium_type: zod.ZodOptional<zod.ZodUnion<[zod.ZodNumber, zod.ZodNull]>>;
                }, "strip", zod.ZodTypeAny, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                }, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                }>;
                presence: zod.ZodOptional<zod.ZodObject<{
                    status: zod.ZodString;
                    activity: zod.ZodOptional<zod.ZodUnion<[zod.ZodObject<{
                        session_id: zod.ZodOptional<zod.ZodString>;
                        type: zod.ZodOptional<zod.ZodNumber>;
                        name: zod.ZodString;
                        url: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
                        application_id: zod.ZodOptional<zod.ZodString>;
                        status_display_type: zod.ZodOptional<zod.ZodNumber>;
                        state: zod.ZodOptional<zod.ZodString>;
                        state_url: zod.ZodOptional<zod.ZodString>;
                        details: zod.ZodOptional<zod.ZodString>;
                        details_url: zod.ZodOptional<zod.ZodString>;
                        emoji: zod.ZodOptional<zod.ZodUnion<[zod.ZodObject<{
                            name: zod.ZodString;
                            id: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
                            animated: zod.ZodOptional<zod.ZodUnion<[zod.ZodBoolean, zod.ZodNull]>>;
                        }, "strip", zod.ZodTypeAny, {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        }, {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        }>, zod.ZodNull]>>;
                        assets: zod.ZodOptional<zod.ZodObject<{
                            large_image: zod.ZodOptional<zod.ZodString>;
                            large_text: zod.ZodOptional<zod.ZodString>;
                            large_url: zod.ZodOptional<zod.ZodString>;
                            small_image: zod.ZodOptional<zod.ZodString>;
                            small_text: zod.ZodOptional<zod.ZodString>;
                            small_url: zod.ZodOptional<zod.ZodString>;
                        }, "strip", zod.ZodTypeAny, {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        }, {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        }>>;
                        timestamps: zod.ZodOptional<zod.ZodObject<{
                            start: zod.ZodOptional<zod.ZodNumber>;
                            end: zod.ZodOptional<zod.ZodNumber>;
                        }, "strip", zod.ZodTypeAny, {
                            start?: number | undefined;
                            end?: number | undefined;
                        }, {
                            start?: number | undefined;
                            end?: number | undefined;
                        }>>;
                        party: zod.ZodOptional<zod.ZodObject<{
                            id: zod.ZodOptional<zod.ZodString>;
                            size: zod.ZodOptional<zod.ZodArray<zod.ZodNumber, "many">>;
                            privacy: zod.ZodOptional<zod.ZodNumber>;
                        }, "strip", zod.ZodTypeAny, {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        }, {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        }>>;
                        secrets: zod.ZodOptional<zod.ZodObject<{
                            match: zod.ZodOptional<zod.ZodString>;
                            join: zod.ZodOptional<zod.ZodString>;
                        }, "strip", zod.ZodTypeAny, {
                            join?: string | undefined;
                            match?: string | undefined;
                        }, {
                            join?: string | undefined;
                            match?: string | undefined;
                        }>>;
                        sync_id: zod.ZodOptional<zod.ZodString>;
                        created_at: zod.ZodOptional<zod.ZodNumber>;
                        instance: zod.ZodOptional<zod.ZodBoolean>;
                        flags: zod.ZodOptional<zod.ZodNumber>;
                        metadata: zod.ZodOptional<zod.ZodObject<{}, "strip", zod.ZodTypeAny, {}, {}>>;
                        platform: zod.ZodOptional<zod.ZodString>;
                        supported_platforms: zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>;
                        buttons: zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>;
                        hangStatus: zod.ZodOptional<zod.ZodString>;
                    }, "strip", zod.ZodTypeAny, {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    }, {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    }>, zod.ZodNull]>>;
                }, "strip", zod.ZodTypeAny, {
                    status: string;
                    activity?: {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    } | null | undefined;
                }, {
                    status: string;
                    activity?: {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    } | null | undefined;
                }>>;
            }, "strip", zod.ZodTypeAny, {
                type: number;
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                };
                presence?: {
                    status: string;
                    activity?: {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    } | null | undefined;
                } | undefined;
            }, {
                type: number;
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                };
                presence?: {
                    status: string;
                    activity?: {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    } | null | undefined;
                } | undefined;
            }>;
        }>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.RELATIONSHIP_UPDATE>;
            data: zod.ZodObject<{
                type: zod.ZodNumber;
                user: zod.ZodObject<{
                    id: zod.ZodString;
                    username: zod.ZodString;
                    global_name: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
                    discriminator: zod.ZodString;
                    avatar: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
                    flags: zod.ZodNumber;
                    bot: zod.ZodBoolean;
                    avatar_decoration_data: zod.ZodOptional<zod.ZodUnion<[zod.ZodObject<{
                        asset: zod.ZodString;
                        skuId: zod.ZodOptional<zod.ZodString>;
                        expiresAt: zod.ZodOptional<zod.ZodNumber>;
                    }, "strip", zod.ZodTypeAny, {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    }, {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    }>, zod.ZodNull]>>;
                    premium_type: zod.ZodOptional<zod.ZodUnion<[zod.ZodNumber, zod.ZodNull]>>;
                }, "strip", zod.ZodTypeAny, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                }, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                }>;
                presence: zod.ZodOptional<zod.ZodObject<{
                    status: zod.ZodString;
                    activity: zod.ZodOptional<zod.ZodUnion<[zod.ZodObject<{
                        session_id: zod.ZodOptional<zod.ZodString>;
                        type: zod.ZodOptional<zod.ZodNumber>;
                        name: zod.ZodString;
                        url: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
                        application_id: zod.ZodOptional<zod.ZodString>;
                        status_display_type: zod.ZodOptional<zod.ZodNumber>;
                        state: zod.ZodOptional<zod.ZodString>;
                        state_url: zod.ZodOptional<zod.ZodString>;
                        details: zod.ZodOptional<zod.ZodString>;
                        details_url: zod.ZodOptional<zod.ZodString>;
                        emoji: zod.ZodOptional<zod.ZodUnion<[zod.ZodObject<{
                            name: zod.ZodString;
                            id: zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNull]>>;
                            animated: zod.ZodOptional<zod.ZodUnion<[zod.ZodBoolean, zod.ZodNull]>>;
                        }, "strip", zod.ZodTypeAny, {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        }, {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        }>, zod.ZodNull]>>;
                        assets: zod.ZodOptional<zod.ZodObject<{
                            large_image: zod.ZodOptional<zod.ZodString>;
                            large_text: zod.ZodOptional<zod.ZodString>;
                            large_url: zod.ZodOptional<zod.ZodString>;
                            small_image: zod.ZodOptional<zod.ZodString>;
                            small_text: zod.ZodOptional<zod.ZodString>;
                            small_url: zod.ZodOptional<zod.ZodString>;
                        }, "strip", zod.ZodTypeAny, {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        }, {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        }>>;
                        timestamps: zod.ZodOptional<zod.ZodObject<{
                            start: zod.ZodOptional<zod.ZodNumber>;
                            end: zod.ZodOptional<zod.ZodNumber>;
                        }, "strip", zod.ZodTypeAny, {
                            start?: number | undefined;
                            end?: number | undefined;
                        }, {
                            start?: number | undefined;
                            end?: number | undefined;
                        }>>;
                        party: zod.ZodOptional<zod.ZodObject<{
                            id: zod.ZodOptional<zod.ZodString>;
                            size: zod.ZodOptional<zod.ZodArray<zod.ZodNumber, "many">>;
                            privacy: zod.ZodOptional<zod.ZodNumber>;
                        }, "strip", zod.ZodTypeAny, {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        }, {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        }>>;
                        secrets: zod.ZodOptional<zod.ZodObject<{
                            match: zod.ZodOptional<zod.ZodString>;
                            join: zod.ZodOptional<zod.ZodString>;
                        }, "strip", zod.ZodTypeAny, {
                            join?: string | undefined;
                            match?: string | undefined;
                        }, {
                            join?: string | undefined;
                            match?: string | undefined;
                        }>>;
                        sync_id: zod.ZodOptional<zod.ZodString>;
                        created_at: zod.ZodOptional<zod.ZodNumber>;
                        instance: zod.ZodOptional<zod.ZodBoolean>;
                        flags: zod.ZodOptional<zod.ZodNumber>;
                        metadata: zod.ZodOptional<zod.ZodObject<{}, "strip", zod.ZodTypeAny, {}, {}>>;
                        platform: zod.ZodOptional<zod.ZodString>;
                        supported_platforms: zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>;
                        buttons: zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>;
                        hangStatus: zod.ZodOptional<zod.ZodString>;
                    }, "strip", zod.ZodTypeAny, {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    }, {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    }>, zod.ZodNull]>>;
                }, "strip", zod.ZodTypeAny, {
                    status: string;
                    activity?: {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    } | null | undefined;
                }, {
                    status: string;
                    activity?: {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    } | null | undefined;
                }>>;
            }, "strip", zod.ZodTypeAny, {
                type: number;
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                };
                presence?: {
                    status: string;
                    activity?: {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    } | null | undefined;
                } | undefined;
            }, {
                type: number;
                user: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    flags: number;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    avatar_decoration_data?: {
                        asset: string;
                        skuId?: string | undefined;
                        expiresAt?: number | undefined;
                    } | null | undefined;
                    premium_type?: number | null | undefined;
                };
                presence?: {
                    status: string;
                    activity?: {
                        name: string;
                        type?: number | undefined;
                        flags?: number | undefined;
                        url?: string | null | undefined;
                        session_id?: string | undefined;
                        application_id?: string | undefined;
                        status_display_type?: number | undefined;
                        state?: string | undefined;
                        state_url?: string | undefined;
                        details?: string | undefined;
                        details_url?: string | undefined;
                        emoji?: {
                            name: string;
                            id?: string | null | undefined;
                            animated?: boolean | null | undefined;
                        } | null | undefined;
                        assets?: {
                            large_image?: string | undefined;
                            large_text?: string | undefined;
                            large_url?: string | undefined;
                            small_image?: string | undefined;
                            small_text?: string | undefined;
                            small_url?: string | undefined;
                        } | undefined;
                        timestamps?: {
                            start?: number | undefined;
                            end?: number | undefined;
                        } | undefined;
                        party?: {
                            id?: string | undefined;
                            size?: number[] | undefined;
                            privacy?: number | undefined;
                        } | undefined;
                        secrets?: {
                            join?: string | undefined;
                            match?: string | undefined;
                        } | undefined;
                        sync_id?: string | undefined;
                        created_at?: number | undefined;
                        instance?: boolean | undefined;
                        metadata?: {} | undefined;
                        platform?: string | undefined;
                        supported_platforms?: string[] | undefined;
                        buttons?: string[] | undefined;
                        hangStatus?: string | undefined;
                    } | null | undefined;
                } | undefined;
            }>;
        }>, zod.ZodTypeAny, "passthrough">>;
    };
    ACTIVITY_JOIN: {
        payload: zod.ZodObject<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.ACTIVITY_JOIN>;
            data: zod.ZodObject<{
                applicationId: zod.ZodString;
                secret: zod.ZodString;
            }, "strip", zod.ZodTypeAny, {
                applicationId: string;
                secret: string;
            }, {
                applicationId: string;
                secret: string;
            }>;
        }>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.ACTIVITY_JOIN>;
            data: zod.ZodObject<{
                applicationId: zod.ZodString;
                secret: zod.ZodString;
            }, "strip", zod.ZodTypeAny, {
                applicationId: string;
                secret: string;
            }, {
                applicationId: string;
                secret: string;
            }>;
        }>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.ACTIVITY_JOIN>;
            data: zod.ZodObject<{
                applicationId: zod.ZodString;
                secret: zod.ZodString;
            }, "strip", zod.ZodTypeAny, {
                applicationId: string;
                secret: string;
            }, {
                applicationId: string;
                secret: string;
            }>;
        }>, zod.ZodTypeAny, "passthrough">>;
    };
    QUEST_ENROLLMENT_STATUS_UPDATE: {
        payload: zod.ZodObject<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.QUEST_ENROLLMENT_STATUS_UPDATE>;
            data: zod.ZodObject<{
                quest_id: zod.ZodString;
                is_enrolled: zod.ZodBoolean;
                enrolled_at: zod.ZodString;
            }, "strip", zod.ZodTypeAny, {
                quest_id: string;
                is_enrolled: boolean;
                enrolled_at: string;
            }, {
                quest_id: string;
                is_enrolled: boolean;
                enrolled_at: string;
            }>;
        }>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.QUEST_ENROLLMENT_STATUS_UPDATE>;
            data: zod.ZodObject<{
                quest_id: zod.ZodString;
                is_enrolled: zod.ZodBoolean;
                enrolled_at: zod.ZodString;
            }, "strip", zod.ZodTypeAny, {
                quest_id: string;
                is_enrolled: boolean;
                enrolled_at: string;
            }, {
                quest_id: string;
                is_enrolled: boolean;
                enrolled_at: string;
            }>;
        }>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<zod.objectUtil.extendShape<{
            cmd: zod.ZodString;
            data: zod.ZodUnknown;
            evt: zod.ZodNull;
            nonce: zod.ZodString;
        }, {
            evt: zod.ZodNativeEnum<typeof Events>;
            nonce: zod.ZodNullable<zod.ZodString>;
            cmd: zod.ZodLiteral<"DISPATCH">;
            data: zod.ZodObject<{}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{}, zod.ZodTypeAny, "passthrough">>;
        }>, {
            evt: zod.ZodLiteral<Events.QUEST_ENROLLMENT_STATUS_UPDATE>;
            data: zod.ZodObject<{
                quest_id: zod.ZodString;
                is_enrolled: zod.ZodBoolean;
                enrolled_at: zod.ZodString;
            }, "strip", zod.ZodTypeAny, {
                quest_id: string;
                is_enrolled: boolean;
                enrolled_at: string;
            }, {
                quest_id: string;
                is_enrolled: boolean;
                enrolled_at: string;
            }>;
        }>, zod.ZodTypeAny, "passthrough">>;
    };
};

// ===== output/schema/index.d.ts =====
export declare const HelloPayload: zod.ZodObject<{
    frame_id: zod.ZodString;
    platform: zod.ZodNullable<zod.ZodOptional<zod.ZodNativeEnum<typeof Platform>>>;
}, "strip", zod.ZodTypeAny, {
    frame_id: string;
    platform?: Platform | null | undefined;
}, {
    frame_id: string;
    platform?: Platform | null | undefined;
}>;
export declare const ConnectPayload: zod.ZodObject<{
    v: zod.ZodLiteral<1>;
    encoding: zod.ZodOptional<zod.ZodLiteral<"json">>;
    client_id: zod.ZodString;
    frame_id: zod.ZodString;
}, "strip", zod.ZodTypeAny, {
    v: 1;
    frame_id: string;
    client_id: string;
    encoding?: "json" | undefined;
}, {
    v: 1;
    frame_id: string;
    client_id: string;
    encoding?: "json" | undefined;
}>;
export declare const ClosePayload: zod.ZodObject<{
    code: zod.ZodNumber;
    message: zod.ZodOptional<zod.ZodString>;
}, "strip", zod.ZodTypeAny, {
    code: number;
    message?: string | undefined;
}, {
    code: number;
    message?: string | undefined;
}>;
export declare const IncomingPayload: zod.ZodObject<{
    evt: zod.ZodNullable<zod.ZodString>;
    nonce: zod.ZodNullable<zod.ZodString>;
    data: zod.ZodNullable<zod.ZodUnknown>;
    cmd: zod.ZodString;
}, "passthrough", zod.ZodTypeAny, zod.objectOutputType<{
    evt: zod.ZodNullable<zod.ZodString>;
    nonce: zod.ZodNullable<zod.ZodString>;
    data: zod.ZodNullable<zod.ZodUnknown>;
    cmd: zod.ZodString;
}, zod.ZodTypeAny, "passthrough">, zod.objectInputType<{
    evt: zod.ZodNullable<zod.ZodString>;
    nonce: zod.ZodNullable<zod.ZodString>;
    data: zod.ZodNullable<zod.ZodUnknown>;
    cmd: zod.ZodString;
}, zod.ZodTypeAny, "passthrough">>;
export declare function parseIncomingPayload<K extends keyof typeof Events.EventSchema = keyof typeof Events.EventSchema>(payload: zod.infer<typeof IncomingPayload>): zod.infer<(typeof Events.EventSchema)[K]['payload']> | zod.infer<typeof Responses.ResponseFrame> | zod.infer<typeof Events.ErrorEvent>;

// ===== output/schema/responses.d.ts =====
export declare const EmptyResponse: zod.ZodNullable<zod.ZodObject<{}, "strip", zod.ZodTypeAny, {}, {}>>;
export declare const AuthorizeResponse: zod.ZodObject<{
    code: zod.ZodString;
}, "strip", zod.ZodTypeAny, {
    code: string;
}, {
    code: string;
}>;
export declare const GetGuildsResponse: zod.ZodObject<{
    guilds: zod.ZodArray<zod.ZodObject<{
        id: zod.ZodString;
        name: zod.ZodString;
    }, "strip", zod.ZodTypeAny, {
        id: string;
        name: string;
    }, {
        id: string;
        name: string;
    }>, "many">;
}, "strip", zod.ZodTypeAny, {
    guilds: {
        id: string;
        name: string;
    }[];
}, {
    guilds: {
        id: string;
        name: string;
    }[];
}>;
export declare const GetGuildResponse: zod.ZodObject<{
    id: zod.ZodString;
    name: zod.ZodString;
    icon_url: zod.ZodOptional<zod.ZodString>;
    members: zod.ZodArray<zod.ZodObject<{
        user: zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>;
        nick: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        roles: zod.ZodArray<zod.ZodString, "many">;
        joined_at: zod.ZodString;
        deaf: zod.ZodBoolean;
        mute: zod.ZodBoolean;
    }, "strip", zod.ZodTypeAny, {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        roles: string[];
        joined_at: string;
        deaf: boolean;
        mute: boolean;
        nick?: string | null | undefined;
    }, {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        roles: string[];
        joined_at: string;
        deaf: boolean;
        mute: boolean;
        nick?: string | null | undefined;
    }>, "many">;
}, "strip", zod.ZodTypeAny, {
    id: string;
    name: string;
    members: {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        roles: string[];
        joined_at: string;
        deaf: boolean;
        mute: boolean;
        nick?: string | null | undefined;
    }[];
    icon_url?: string | undefined;
}, {
    id: string;
    name: string;
    members: {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        roles: string[];
        joined_at: string;
        deaf: boolean;
        mute: boolean;
        nick?: string | null | undefined;
    }[];
    icon_url?: string | undefined;
}>;
export declare const GetChannelResponse: zod.ZodObject<{
    id: zod.ZodString;
    type: zod.ZodEffects<zod.ZodType<0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1, zod.ZodTypeDef, 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1>, 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1, unknown>;
    guild_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    topic: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    bitrate: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    user_limit: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    position: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    voice_states: zod.ZodArray<zod.ZodObject<{
        mute: zod.ZodBoolean;
        nick: zod.ZodString;
        user: zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>;
        voice_state: zod.ZodObject<{
            mute: zod.ZodBoolean;
            deaf: zod.ZodBoolean;
            self_mute: zod.ZodBoolean;
            self_deaf: zod.ZodBoolean;
            suppress: zod.ZodBoolean;
        }, "strip", zod.ZodTypeAny, {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        }, {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        }>;
        volume: zod.ZodNumber;
    }, "strip", zod.ZodTypeAny, {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        nick: string;
        mute: boolean;
        voice_state: {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        };
        volume: number;
    }, {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        nick: string;
        mute: boolean;
        voice_state: {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        };
        volume: number;
    }>, "many">;
    messages: zod.ZodArray<zod.ZodObject<{
        id: zod.ZodString;
        channel_id: zod.ZodString;
        guild_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        author: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>>>;
        member: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            user: zod.ZodObject<{
                id: zod.ZodString;
                username: zod.ZodString;
                discriminator: zod.ZodString;
                global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                    asset: zod.ZodString;
                    sku_id: zod.ZodOptional<zod.ZodString>;
                }, "strip", zod.ZodTypeAny, {
                    asset: string;
                    sku_id?: string | undefined;
                }, {
                    asset: string;
                    sku_id?: string | undefined;
                }>>;
                bot: zod.ZodBoolean;
                flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "strip", zod.ZodTypeAny, {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            }, {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            }>;
            nick: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            roles: zod.ZodArray<zod.ZodString, "many">;
            joined_at: zod.ZodString;
            deaf: zod.ZodBoolean;
            mute: zod.ZodBoolean;
        }, "strip", zod.ZodTypeAny, {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        }, {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        }>>>;
        content: zod.ZodString;
        timestamp: zod.ZodString;
        edited_timestamp: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        tts: zod.ZodBoolean;
        mention_everyone: zod.ZodBoolean;
        mentions: zod.ZodArray<zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>, "many">;
        mention_roles: zod.ZodArray<zod.ZodString, "many">;
        mention_channels: zod.ZodArray<zod.ZodObject<{
            id: zod.ZodString;
            guild_id: zod.ZodString;
            type: zod.ZodNumber;
            name: zod.ZodString;
        }, "strip", zod.ZodTypeAny, {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }, {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }>, "many">;
        attachments: zod.ZodArray<zod.ZodObject<{
            id: zod.ZodString;
            filename: zod.ZodString;
            size: zod.ZodNumber;
            url: zod.ZodString;
            proxy_url: zod.ZodString;
            height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }, {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }>, "many">;
        embeds: zod.ZodArray<zod.ZodObject<{
            title: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            type: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            description: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            timestamp: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            color: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            footer: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                text: zod.ZodString;
                icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                proxy_icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            }, "strip", zod.ZodTypeAny, {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            }, {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            }>>>;
            image: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                proxy_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "strip", zod.ZodTypeAny, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            }, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            }>>>;
            thumbnail: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                proxy_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "strip", zod.ZodTypeAny, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            }, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            }>>>;
            video: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<Omit<{
                url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                proxy_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "proxy_url">, "strip", zod.ZodTypeAny, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            }, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            }>>>;
            provider: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            }, "strip", zod.ZodTypeAny, {
                name?: string | null | undefined;
                url?: string | null | undefined;
            }, {
                name?: string | null | undefined;
                url?: string | null | undefined;
            }>>>;
            author: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                proxy_icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            }, "strip", zod.ZodTypeAny, {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            }, {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            }>>>;
            fields: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
                name: zod.ZodString;
                value: zod.ZodString;
                inline: zod.ZodBoolean;
            }, "strip", zod.ZodTypeAny, {
                value: string;
                name: string;
                inline: boolean;
            }, {
                value: string;
                name: string;
                inline: boolean;
            }>, "many">>>;
        }, "strip", zod.ZodTypeAny, {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }, {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }>, "many">;
        reactions: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
            count: zod.ZodNumber;
            me: zod.ZodBoolean;
            emoji: zod.ZodObject<{
                id: zod.ZodString;
                name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                roles: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>>;
                user: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                    id: zod.ZodString;
                    username: zod.ZodString;
                    discriminator: zod.ZodString;
                    global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                        asset: zod.ZodString;
                        sku_id: zod.ZodOptional<zod.ZodString>;
                    }, "strip", zod.ZodTypeAny, {
                        asset: string;
                        sku_id?: string | undefined;
                    }, {
                        asset: string;
                        sku_id?: string | undefined;
                    }>>;
                    bot: zod.ZodBoolean;
                    flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                    premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                }, "strip", zod.ZodTypeAny, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                }, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                }>>>;
                require_colons: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                managed: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                animated: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                available: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
            }, "strip", zod.ZodTypeAny, {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            }, {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            }>;
        }, "strip", zod.ZodTypeAny, {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }, {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }>, "many">>>;
        nonce: zod.ZodNullable<zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNumber]>>>;
        pinned: zod.ZodBoolean;
        webhook_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        type: zod.ZodNumber;
        activity: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            type: zod.ZodNumber;
            party_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        }, "strip", zod.ZodTypeAny, {
            type: number;
            party_id?: string | null | undefined;
        }, {
            type: number;
            party_id?: string | null | undefined;
        }>>>;
        application: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            id: zod.ZodString;
            cover_image: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            description: zod.ZodString;
            icon: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            name: zod.ZodString;
        }, "strip", zod.ZodTypeAny, {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        }, {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        }>>>;
        message_reference: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            message_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            channel_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            guild_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        }, "strip", zod.ZodTypeAny, {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        }, {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        }>>>;
        flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        stickers: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodUnknown, "many">>>;
        referenced_message: zod.ZodNullable<zod.ZodOptional<zod.ZodUnknown>>;
    }, "strip", zod.ZodTypeAny, {
        type: number;
        id: string;
        content: string;
        timestamp: string;
        channel_id: string;
        tts: boolean;
        mention_everyone: boolean;
        mentions: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[];
        mention_roles: string[];
        mention_channels: {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }[];
        attachments: {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }[];
        embeds: {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }[];
        pinned: boolean;
        application?: {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        } | null | undefined;
        flags?: number | null | undefined;
        activity?: {
            type: number;
            party_id?: string | null | undefined;
        } | null | undefined;
        nonce?: string | number | null | undefined;
        guild_id?: string | null | undefined;
        author?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        member?: {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        } | null | undefined;
        edited_timestamp?: string | null | undefined;
        reactions?: {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }[] | null | undefined;
        webhook_id?: string | null | undefined;
        message_reference?: {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        } | null | undefined;
        stickers?: unknown[] | null | undefined;
        referenced_message?: unknown;
    }, {
        type: number;
        id: string;
        content: string;
        timestamp: string;
        channel_id: string;
        tts: boolean;
        mention_everyone: boolean;
        mentions: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[];
        mention_roles: string[];
        mention_channels: {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }[];
        attachments: {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }[];
        embeds: {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }[];
        pinned: boolean;
        application?: {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        } | null | undefined;
        flags?: number | null | undefined;
        activity?: {
            type: number;
            party_id?: string | null | undefined;
        } | null | undefined;
        nonce?: string | number | null | undefined;
        guild_id?: string | null | undefined;
        author?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        member?: {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        } | null | undefined;
        edited_timestamp?: string | null | undefined;
        reactions?: {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }[] | null | undefined;
        webhook_id?: string | null | undefined;
        message_reference?: {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        } | null | undefined;
        stickers?: unknown[] | null | undefined;
        referenced_message?: unknown;
    }>, "many">;
}, "strip", zod.ZodTypeAny, {
    type: 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1;
    id: string;
    voice_states: {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        nick: string;
        mute: boolean;
        voice_state: {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        };
        volume: number;
    }[];
    messages: {
        type: number;
        id: string;
        content: string;
        timestamp: string;
        channel_id: string;
        tts: boolean;
        mention_everyone: boolean;
        mentions: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[];
        mention_roles: string[];
        mention_channels: {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }[];
        attachments: {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }[];
        embeds: {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }[];
        pinned: boolean;
        application?: {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        } | null | undefined;
        flags?: number | null | undefined;
        activity?: {
            type: number;
            party_id?: string | null | undefined;
        } | null | undefined;
        nonce?: string | number | null | undefined;
        guild_id?: string | null | undefined;
        author?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        member?: {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        } | null | undefined;
        edited_timestamp?: string | null | undefined;
        reactions?: {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }[] | null | undefined;
        webhook_id?: string | null | undefined;
        message_reference?: {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        } | null | undefined;
        stickers?: unknown[] | null | undefined;
        referenced_message?: unknown;
    }[];
    name?: string | null | undefined;
    guild_id?: string | null | undefined;
    position?: number | null | undefined;
    topic?: string | null | undefined;
    bitrate?: number | null | undefined;
    user_limit?: number | null | undefined;
}, {
    id: string;
    voice_states: {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        nick: string;
        mute: boolean;
        voice_state: {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        };
        volume: number;
    }[];
    messages: {
        type: number;
        id: string;
        content: string;
        timestamp: string;
        channel_id: string;
        tts: boolean;
        mention_everyone: boolean;
        mentions: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[];
        mention_roles: string[];
        mention_channels: {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }[];
        attachments: {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }[];
        embeds: {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }[];
        pinned: boolean;
        application?: {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        } | null | undefined;
        flags?: number | null | undefined;
        activity?: {
            type: number;
            party_id?: string | null | undefined;
        } | null | undefined;
        nonce?: string | number | null | undefined;
        guild_id?: string | null | undefined;
        author?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        member?: {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        } | null | undefined;
        edited_timestamp?: string | null | undefined;
        reactions?: {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }[] | null | undefined;
        webhook_id?: string | null | undefined;
        message_reference?: {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        } | null | undefined;
        stickers?: unknown[] | null | undefined;
        referenced_message?: unknown;
    }[];
    type?: unknown;
    name?: string | null | undefined;
    guild_id?: string | null | undefined;
    position?: number | null | undefined;
    topic?: string | null | undefined;
    bitrate?: number | null | undefined;
    user_limit?: number | null | undefined;
}>;
export declare const GetChannelsResponse: zod.ZodObject<{
    channels: zod.ZodArray<zod.ZodObject<{
        id: zod.ZodString;
        type: zod.ZodEffects<zod.ZodType<0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1, zod.ZodTypeDef, 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1>, 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1, unknown>;
        guild_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        position: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        permission_overwrites: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
            id: zod.ZodString;
            type: zod.ZodEffects<zod.ZodType<0 | 1 | -1, zod.ZodTypeDef, 0 | 1 | -1>, 0 | 1 | -1, unknown>;
            allow: zod.ZodString;
            deny: zod.ZodString;
        }, "strip", zod.ZodTypeAny, {
            type: 0 | 1 | -1;
            id: string;
            allow: string;
            deny: string;
        }, {
            id: string;
            allow: string;
            deny: string;
            type?: unknown;
        }>, "many">>>;
        name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        topic: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        nsfw: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        last_message_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        bitrate: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        user_limit: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        rate_limit_per_user: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        recipients: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>, "many">>>;
        icon: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        owner_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        application_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        parent_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        last_pin_timestamp: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    }, "strip", zod.ZodTypeAny, {
        type: 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1;
        id: string;
        icon?: string | null | undefined;
        name?: string | null | undefined;
        application_id?: string | null | undefined;
        guild_id?: string | null | undefined;
        position?: number | null | undefined;
        permission_overwrites?: {
            type: 0 | 1 | -1;
            id: string;
            allow: string;
            deny: string;
        }[] | null | undefined;
        topic?: string | null | undefined;
        nsfw?: boolean | null | undefined;
        last_message_id?: string | null | undefined;
        bitrate?: number | null | undefined;
        user_limit?: number | null | undefined;
        rate_limit_per_user?: number | null | undefined;
        recipients?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[] | null | undefined;
        owner_id?: string | null | undefined;
        parent_id?: string | null | undefined;
        last_pin_timestamp?: string | null | undefined;
    }, {
        id: string;
        type?: unknown;
        icon?: string | null | undefined;
        name?: string | null | undefined;
        application_id?: string | null | undefined;
        guild_id?: string | null | undefined;
        position?: number | null | undefined;
        permission_overwrites?: {
            id: string;
            allow: string;
            deny: string;
            type?: unknown;
        }[] | null | undefined;
        topic?: string | null | undefined;
        nsfw?: boolean | null | undefined;
        last_message_id?: string | null | undefined;
        bitrate?: number | null | undefined;
        user_limit?: number | null | undefined;
        rate_limit_per_user?: number | null | undefined;
        recipients?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[] | null | undefined;
        owner_id?: string | null | undefined;
        parent_id?: string | null | undefined;
        last_pin_timestamp?: string | null | undefined;
    }>, "many">;
}, "strip", zod.ZodTypeAny, {
    channels: {
        type: 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1;
        id: string;
        icon?: string | null | undefined;
        name?: string | null | undefined;
        application_id?: string | null | undefined;
        guild_id?: string | null | undefined;
        position?: number | null | undefined;
        permission_overwrites?: {
            type: 0 | 1 | -1;
            id: string;
            allow: string;
            deny: string;
        }[] | null | undefined;
        topic?: string | null | undefined;
        nsfw?: boolean | null | undefined;
        last_message_id?: string | null | undefined;
        bitrate?: number | null | undefined;
        user_limit?: number | null | undefined;
        rate_limit_per_user?: number | null | undefined;
        recipients?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[] | null | undefined;
        owner_id?: string | null | undefined;
        parent_id?: string | null | undefined;
        last_pin_timestamp?: string | null | undefined;
    }[];
}, {
    channels: {
        id: string;
        type?: unknown;
        icon?: string | null | undefined;
        name?: string | null | undefined;
        application_id?: string | null | undefined;
        guild_id?: string | null | undefined;
        position?: number | null | undefined;
        permission_overwrites?: {
            id: string;
            allow: string;
            deny: string;
            type?: unknown;
        }[] | null | undefined;
        topic?: string | null | undefined;
        nsfw?: boolean | null | undefined;
        last_message_id?: string | null | undefined;
        bitrate?: number | null | undefined;
        user_limit?: number | null | undefined;
        rate_limit_per_user?: number | null | undefined;
        recipients?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[] | null | undefined;
        owner_id?: string | null | undefined;
        parent_id?: string | null | undefined;
        last_pin_timestamp?: string | null | undefined;
    }[];
}>;
export declare const NullableChannelResponse: zod.ZodNullable<zod.ZodObject<{
    id: zod.ZodString;
    type: zod.ZodEffects<zod.ZodType<0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1, zod.ZodTypeDef, 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1>, 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1, unknown>;
    guild_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    topic: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    bitrate: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    user_limit: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    position: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    voice_states: zod.ZodArray<zod.ZodObject<{
        mute: zod.ZodBoolean;
        nick: zod.ZodString;
        user: zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>;
        voice_state: zod.ZodObject<{
            mute: zod.ZodBoolean;
            deaf: zod.ZodBoolean;
            self_mute: zod.ZodBoolean;
            self_deaf: zod.ZodBoolean;
            suppress: zod.ZodBoolean;
        }, "strip", zod.ZodTypeAny, {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        }, {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        }>;
        volume: zod.ZodNumber;
    }, "strip", zod.ZodTypeAny, {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        nick: string;
        mute: boolean;
        voice_state: {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        };
        volume: number;
    }, {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        nick: string;
        mute: boolean;
        voice_state: {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        };
        volume: number;
    }>, "many">;
    messages: zod.ZodArray<zod.ZodObject<{
        id: zod.ZodString;
        channel_id: zod.ZodString;
        guild_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        author: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>>>;
        member: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            user: zod.ZodObject<{
                id: zod.ZodString;
                username: zod.ZodString;
                discriminator: zod.ZodString;
                global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                    asset: zod.ZodString;
                    sku_id: zod.ZodOptional<zod.ZodString>;
                }, "strip", zod.ZodTypeAny, {
                    asset: string;
                    sku_id?: string | undefined;
                }, {
                    asset: string;
                    sku_id?: string | undefined;
                }>>;
                bot: zod.ZodBoolean;
                flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "strip", zod.ZodTypeAny, {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            }, {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            }>;
            nick: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            roles: zod.ZodArray<zod.ZodString, "many">;
            joined_at: zod.ZodString;
            deaf: zod.ZodBoolean;
            mute: zod.ZodBoolean;
        }, "strip", zod.ZodTypeAny, {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        }, {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        }>>>;
        content: zod.ZodString;
        timestamp: zod.ZodString;
        edited_timestamp: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        tts: zod.ZodBoolean;
        mention_everyone: zod.ZodBoolean;
        mentions: zod.ZodArray<zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>, "many">;
        mention_roles: zod.ZodArray<zod.ZodString, "many">;
        mention_channels: zod.ZodArray<zod.ZodObject<{
            id: zod.ZodString;
            guild_id: zod.ZodString;
            type: zod.ZodNumber;
            name: zod.ZodString;
        }, "strip", zod.ZodTypeAny, {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }, {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }>, "many">;
        attachments: zod.ZodArray<zod.ZodObject<{
            id: zod.ZodString;
            filename: zod.ZodString;
            size: zod.ZodNumber;
            url: zod.ZodString;
            proxy_url: zod.ZodString;
            height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }, {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }>, "many">;
        embeds: zod.ZodArray<zod.ZodObject<{
            title: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            type: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            description: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            timestamp: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            color: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            footer: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                text: zod.ZodString;
                icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                proxy_icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            }, "strip", zod.ZodTypeAny, {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            }, {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            }>>>;
            image: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                proxy_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "strip", zod.ZodTypeAny, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            }, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            }>>>;
            thumbnail: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                proxy_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "strip", zod.ZodTypeAny, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            }, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            }>>>;
            video: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<Omit<{
                url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                proxy_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "proxy_url">, "strip", zod.ZodTypeAny, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            }, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            }>>>;
            provider: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            }, "strip", zod.ZodTypeAny, {
                name?: string | null | undefined;
                url?: string | null | undefined;
            }, {
                name?: string | null | undefined;
                url?: string | null | undefined;
            }>>>;
            author: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                proxy_icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            }, "strip", zod.ZodTypeAny, {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            }, {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            }>>>;
            fields: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
                name: zod.ZodString;
                value: zod.ZodString;
                inline: zod.ZodBoolean;
            }, "strip", zod.ZodTypeAny, {
                value: string;
                name: string;
                inline: boolean;
            }, {
                value: string;
                name: string;
                inline: boolean;
            }>, "many">>>;
        }, "strip", zod.ZodTypeAny, {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }, {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }>, "many">;
        reactions: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
            count: zod.ZodNumber;
            me: zod.ZodBoolean;
            emoji: zod.ZodObject<{
                id: zod.ZodString;
                name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                roles: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>>;
                user: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                    id: zod.ZodString;
                    username: zod.ZodString;
                    discriminator: zod.ZodString;
                    global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                        asset: zod.ZodString;
                        sku_id: zod.ZodOptional<zod.ZodString>;
                    }, "strip", zod.ZodTypeAny, {
                        asset: string;
                        sku_id?: string | undefined;
                    }, {
                        asset: string;
                        sku_id?: string | undefined;
                    }>>;
                    bot: zod.ZodBoolean;
                    flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                    premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                }, "strip", zod.ZodTypeAny, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                }, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                }>>>;
                require_colons: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                managed: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                animated: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                available: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
            }, "strip", zod.ZodTypeAny, {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            }, {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            }>;
        }, "strip", zod.ZodTypeAny, {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }, {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }>, "many">>>;
        nonce: zod.ZodNullable<zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNumber]>>>;
        pinned: zod.ZodBoolean;
        webhook_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        type: zod.ZodNumber;
        activity: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            type: zod.ZodNumber;
            party_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        }, "strip", zod.ZodTypeAny, {
            type: number;
            party_id?: string | null | undefined;
        }, {
            type: number;
            party_id?: string | null | undefined;
        }>>>;
        application: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            id: zod.ZodString;
            cover_image: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            description: zod.ZodString;
            icon: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            name: zod.ZodString;
        }, "strip", zod.ZodTypeAny, {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        }, {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        }>>>;
        message_reference: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            message_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            channel_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            guild_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        }, "strip", zod.ZodTypeAny, {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        }, {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        }>>>;
        flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        stickers: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodUnknown, "many">>>;
        referenced_message: zod.ZodNullable<zod.ZodOptional<zod.ZodUnknown>>;
    }, "strip", zod.ZodTypeAny, {
        type: number;
        id: string;
        content: string;
        timestamp: string;
        channel_id: string;
        tts: boolean;
        mention_everyone: boolean;
        mentions: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[];
        mention_roles: string[];
        mention_channels: {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }[];
        attachments: {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }[];
        embeds: {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }[];
        pinned: boolean;
        application?: {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        } | null | undefined;
        flags?: number | null | undefined;
        activity?: {
            type: number;
            party_id?: string | null | undefined;
        } | null | undefined;
        nonce?: string | number | null | undefined;
        guild_id?: string | null | undefined;
        author?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        member?: {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        } | null | undefined;
        edited_timestamp?: string | null | undefined;
        reactions?: {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }[] | null | undefined;
        webhook_id?: string | null | undefined;
        message_reference?: {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        } | null | undefined;
        stickers?: unknown[] | null | undefined;
        referenced_message?: unknown;
    }, {
        type: number;
        id: string;
        content: string;
        timestamp: string;
        channel_id: string;
        tts: boolean;
        mention_everyone: boolean;
        mentions: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[];
        mention_roles: string[];
        mention_channels: {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }[];
        attachments: {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }[];
        embeds: {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }[];
        pinned: boolean;
        application?: {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        } | null | undefined;
        flags?: number | null | undefined;
        activity?: {
            type: number;
            party_id?: string | null | undefined;
        } | null | undefined;
        nonce?: string | number | null | undefined;
        guild_id?: string | null | undefined;
        author?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        member?: {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        } | null | undefined;
        edited_timestamp?: string | null | undefined;
        reactions?: {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }[] | null | undefined;
        webhook_id?: string | null | undefined;
        message_reference?: {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        } | null | undefined;
        stickers?: unknown[] | null | undefined;
        referenced_message?: unknown;
    }>, "many">;
}, "strip", zod.ZodTypeAny, {
    type: 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1;
    id: string;
    voice_states: {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        nick: string;
        mute: boolean;
        voice_state: {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        };
        volume: number;
    }[];
    messages: {
        type: number;
        id: string;
        content: string;
        timestamp: string;
        channel_id: string;
        tts: boolean;
        mention_everyone: boolean;
        mentions: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[];
        mention_roles: string[];
        mention_channels: {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }[];
        attachments: {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }[];
        embeds: {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }[];
        pinned: boolean;
        application?: {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        } | null | undefined;
        flags?: number | null | undefined;
        activity?: {
            type: number;
            party_id?: string | null | undefined;
        } | null | undefined;
        nonce?: string | number | null | undefined;
        guild_id?: string | null | undefined;
        author?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        member?: {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        } | null | undefined;
        edited_timestamp?: string | null | undefined;
        reactions?: {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }[] | null | undefined;
        webhook_id?: string | null | undefined;
        message_reference?: {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        } | null | undefined;
        stickers?: unknown[] | null | undefined;
        referenced_message?: unknown;
    }[];
    name?: string | null | undefined;
    guild_id?: string | null | undefined;
    position?: number | null | undefined;
    topic?: string | null | undefined;
    bitrate?: number | null | undefined;
    user_limit?: number | null | undefined;
}, {
    id: string;
    voice_states: {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        nick: string;
        mute: boolean;
        voice_state: {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        };
        volume: number;
    }[];
    messages: {
        type: number;
        id: string;
        content: string;
        timestamp: string;
        channel_id: string;
        tts: boolean;
        mention_everyone: boolean;
        mentions: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[];
        mention_roles: string[];
        mention_channels: {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }[];
        attachments: {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }[];
        embeds: {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }[];
        pinned: boolean;
        application?: {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        } | null | undefined;
        flags?: number | null | undefined;
        activity?: {
            type: number;
            party_id?: string | null | undefined;
        } | null | undefined;
        nonce?: string | number | null | undefined;
        guild_id?: string | null | undefined;
        author?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        member?: {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        } | null | undefined;
        edited_timestamp?: string | null | undefined;
        reactions?: {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }[] | null | undefined;
        webhook_id?: string | null | undefined;
        message_reference?: {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        } | null | undefined;
        stickers?: unknown[] | null | undefined;
        referenced_message?: unknown;
    }[];
    type?: unknown;
    name?: string | null | undefined;
    guild_id?: string | null | undefined;
    position?: number | null | undefined;
    topic?: string | null | undefined;
    bitrate?: number | null | undefined;
    user_limit?: number | null | undefined;
}>>;
export declare const SelectVoiceChannelResponse: zod.ZodNullable<zod.ZodObject<{
    id: zod.ZodString;
    type: zod.ZodEffects<zod.ZodType<0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1, zod.ZodTypeDef, 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1>, 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1, unknown>;
    guild_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    topic: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    bitrate: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    user_limit: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    position: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    voice_states: zod.ZodArray<zod.ZodObject<{
        mute: zod.ZodBoolean;
        nick: zod.ZodString;
        user: zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>;
        voice_state: zod.ZodObject<{
            mute: zod.ZodBoolean;
            deaf: zod.ZodBoolean;
            self_mute: zod.ZodBoolean;
            self_deaf: zod.ZodBoolean;
            suppress: zod.ZodBoolean;
        }, "strip", zod.ZodTypeAny, {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        }, {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        }>;
        volume: zod.ZodNumber;
    }, "strip", zod.ZodTypeAny, {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        nick: string;
        mute: boolean;
        voice_state: {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        };
        volume: number;
    }, {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        nick: string;
        mute: boolean;
        voice_state: {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        };
        volume: number;
    }>, "many">;
    messages: zod.ZodArray<zod.ZodObject<{
        id: zod.ZodString;
        channel_id: zod.ZodString;
        guild_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        author: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>>>;
        member: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            user: zod.ZodObject<{
                id: zod.ZodString;
                username: zod.ZodString;
                discriminator: zod.ZodString;
                global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                    asset: zod.ZodString;
                    sku_id: zod.ZodOptional<zod.ZodString>;
                }, "strip", zod.ZodTypeAny, {
                    asset: string;
                    sku_id?: string | undefined;
                }, {
                    asset: string;
                    sku_id?: string | undefined;
                }>>;
                bot: zod.ZodBoolean;
                flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "strip", zod.ZodTypeAny, {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            }, {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            }>;
            nick: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            roles: zod.ZodArray<zod.ZodString, "many">;
            joined_at: zod.ZodString;
            deaf: zod.ZodBoolean;
            mute: zod.ZodBoolean;
        }, "strip", zod.ZodTypeAny, {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        }, {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        }>>>;
        content: zod.ZodString;
        timestamp: zod.ZodString;
        edited_timestamp: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        tts: zod.ZodBoolean;
        mention_everyone: zod.ZodBoolean;
        mentions: zod.ZodArray<zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>, "many">;
        mention_roles: zod.ZodArray<zod.ZodString, "many">;
        mention_channels: zod.ZodArray<zod.ZodObject<{
            id: zod.ZodString;
            guild_id: zod.ZodString;
            type: zod.ZodNumber;
            name: zod.ZodString;
        }, "strip", zod.ZodTypeAny, {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }, {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }>, "many">;
        attachments: zod.ZodArray<zod.ZodObject<{
            id: zod.ZodString;
            filename: zod.ZodString;
            size: zod.ZodNumber;
            url: zod.ZodString;
            proxy_url: zod.ZodString;
            height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }, {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }>, "many">;
        embeds: zod.ZodArray<zod.ZodObject<{
            title: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            type: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            description: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            timestamp: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            color: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            footer: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                text: zod.ZodString;
                icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                proxy_icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            }, "strip", zod.ZodTypeAny, {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            }, {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            }>>>;
            image: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                proxy_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "strip", zod.ZodTypeAny, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            }, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            }>>>;
            thumbnail: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                proxy_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "strip", zod.ZodTypeAny, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            }, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            }>>>;
            video: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<Omit<{
                url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                proxy_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "proxy_url">, "strip", zod.ZodTypeAny, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            }, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            }>>>;
            provider: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            }, "strip", zod.ZodTypeAny, {
                name?: string | null | undefined;
                url?: string | null | undefined;
            }, {
                name?: string | null | undefined;
                url?: string | null | undefined;
            }>>>;
            author: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                proxy_icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            }, "strip", zod.ZodTypeAny, {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            }, {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            }>>>;
            fields: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
                name: zod.ZodString;
                value: zod.ZodString;
                inline: zod.ZodBoolean;
            }, "strip", zod.ZodTypeAny, {
                value: string;
                name: string;
                inline: boolean;
            }, {
                value: string;
                name: string;
                inline: boolean;
            }>, "many">>>;
        }, "strip", zod.ZodTypeAny, {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }, {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }>, "many">;
        reactions: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
            count: zod.ZodNumber;
            me: zod.ZodBoolean;
            emoji: zod.ZodObject<{
                id: zod.ZodString;
                name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                roles: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>>;
                user: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                    id: zod.ZodString;
                    username: zod.ZodString;
                    discriminator: zod.ZodString;
                    global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                        asset: zod.ZodString;
                        sku_id: zod.ZodOptional<zod.ZodString>;
                    }, "strip", zod.ZodTypeAny, {
                        asset: string;
                        sku_id?: string | undefined;
                    }, {
                        asset: string;
                        sku_id?: string | undefined;
                    }>>;
                    bot: zod.ZodBoolean;
                    flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                    premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                }, "strip", zod.ZodTypeAny, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                }, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                }>>>;
                require_colons: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                managed: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                animated: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                available: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
            }, "strip", zod.ZodTypeAny, {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            }, {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            }>;
        }, "strip", zod.ZodTypeAny, {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }, {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }>, "many">>>;
        nonce: zod.ZodNullable<zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNumber]>>>;
        pinned: zod.ZodBoolean;
        webhook_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        type: zod.ZodNumber;
        activity: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            type: zod.ZodNumber;
            party_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        }, "strip", zod.ZodTypeAny, {
            type: number;
            party_id?: string | null | undefined;
        }, {
            type: number;
            party_id?: string | null | undefined;
        }>>>;
        application: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            id: zod.ZodString;
            cover_image: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            description: zod.ZodString;
            icon: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            name: zod.ZodString;
        }, "strip", zod.ZodTypeAny, {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        }, {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        }>>>;
        message_reference: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            message_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            channel_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            guild_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        }, "strip", zod.ZodTypeAny, {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        }, {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        }>>>;
        flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        stickers: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodUnknown, "many">>>;
        referenced_message: zod.ZodNullable<zod.ZodOptional<zod.ZodUnknown>>;
    }, "strip", zod.ZodTypeAny, {
        type: number;
        id: string;
        content: string;
        timestamp: string;
        channel_id: string;
        tts: boolean;
        mention_everyone: boolean;
        mentions: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[];
        mention_roles: string[];
        mention_channels: {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }[];
        attachments: {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }[];
        embeds: {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }[];
        pinned: boolean;
        application?: {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        } | null | undefined;
        flags?: number | null | undefined;
        activity?: {
            type: number;
            party_id?: string | null | undefined;
        } | null | undefined;
        nonce?: string | number | null | undefined;
        guild_id?: string | null | undefined;
        author?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        member?: {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        } | null | undefined;
        edited_timestamp?: string | null | undefined;
        reactions?: {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }[] | null | undefined;
        webhook_id?: string | null | undefined;
        message_reference?: {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        } | null | undefined;
        stickers?: unknown[] | null | undefined;
        referenced_message?: unknown;
    }, {
        type: number;
        id: string;
        content: string;
        timestamp: string;
        channel_id: string;
        tts: boolean;
        mention_everyone: boolean;
        mentions: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[];
        mention_roles: string[];
        mention_channels: {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }[];
        attachments: {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }[];
        embeds: {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }[];
        pinned: boolean;
        application?: {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        } | null | undefined;
        flags?: number | null | undefined;
        activity?: {
            type: number;
            party_id?: string | null | undefined;
        } | null | undefined;
        nonce?: string | number | null | undefined;
        guild_id?: string | null | undefined;
        author?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        member?: {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        } | null | undefined;
        edited_timestamp?: string | null | undefined;
        reactions?: {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }[] | null | undefined;
        webhook_id?: string | null | undefined;
        message_reference?: {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        } | null | undefined;
        stickers?: unknown[] | null | undefined;
        referenced_message?: unknown;
    }>, "many">;
}, "strip", zod.ZodTypeAny, {
    type: 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1;
    id: string;
    voice_states: {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        nick: string;
        mute: boolean;
        voice_state: {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        };
        volume: number;
    }[];
    messages: {
        type: number;
        id: string;
        content: string;
        timestamp: string;
        channel_id: string;
        tts: boolean;
        mention_everyone: boolean;
        mentions: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[];
        mention_roles: string[];
        mention_channels: {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }[];
        attachments: {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }[];
        embeds: {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }[];
        pinned: boolean;
        application?: {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        } | null | undefined;
        flags?: number | null | undefined;
        activity?: {
            type: number;
            party_id?: string | null | undefined;
        } | null | undefined;
        nonce?: string | number | null | undefined;
        guild_id?: string | null | undefined;
        author?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        member?: {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        } | null | undefined;
        edited_timestamp?: string | null | undefined;
        reactions?: {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }[] | null | undefined;
        webhook_id?: string | null | undefined;
        message_reference?: {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        } | null | undefined;
        stickers?: unknown[] | null | undefined;
        referenced_message?: unknown;
    }[];
    name?: string | null | undefined;
    guild_id?: string | null | undefined;
    position?: number | null | undefined;
    topic?: string | null | undefined;
    bitrate?: number | null | undefined;
    user_limit?: number | null | undefined;
}, {
    id: string;
    voice_states: {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        nick: string;
        mute: boolean;
        voice_state: {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        };
        volume: number;
    }[];
    messages: {
        type: number;
        id: string;
        content: string;
        timestamp: string;
        channel_id: string;
        tts: boolean;
        mention_everyone: boolean;
        mentions: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[];
        mention_roles: string[];
        mention_channels: {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }[];
        attachments: {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }[];
        embeds: {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }[];
        pinned: boolean;
        application?: {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        } | null | undefined;
        flags?: number | null | undefined;
        activity?: {
            type: number;
            party_id?: string | null | undefined;
        } | null | undefined;
        nonce?: string | number | null | undefined;
        guild_id?: string | null | undefined;
        author?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        member?: {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        } | null | undefined;
        edited_timestamp?: string | null | undefined;
        reactions?: {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }[] | null | undefined;
        webhook_id?: string | null | undefined;
        message_reference?: {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        } | null | undefined;
        stickers?: unknown[] | null | undefined;
        referenced_message?: unknown;
    }[];
    type?: unknown;
    name?: string | null | undefined;
    guild_id?: string | null | undefined;
    position?: number | null | undefined;
    topic?: string | null | undefined;
    bitrate?: number | null | undefined;
    user_limit?: number | null | undefined;
}>>;
export declare const SelectTextChannelResponse: zod.ZodNullable<zod.ZodObject<{
    id: zod.ZodString;
    type: zod.ZodEffects<zod.ZodType<0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1, zod.ZodTypeDef, 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1>, 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1, unknown>;
    guild_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    topic: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    bitrate: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    user_limit: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    position: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    voice_states: zod.ZodArray<zod.ZodObject<{
        mute: zod.ZodBoolean;
        nick: zod.ZodString;
        user: zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>;
        voice_state: zod.ZodObject<{
            mute: zod.ZodBoolean;
            deaf: zod.ZodBoolean;
            self_mute: zod.ZodBoolean;
            self_deaf: zod.ZodBoolean;
            suppress: zod.ZodBoolean;
        }, "strip", zod.ZodTypeAny, {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        }, {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        }>;
        volume: zod.ZodNumber;
    }, "strip", zod.ZodTypeAny, {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        nick: string;
        mute: boolean;
        voice_state: {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        };
        volume: number;
    }, {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        nick: string;
        mute: boolean;
        voice_state: {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        };
        volume: number;
    }>, "many">;
    messages: zod.ZodArray<zod.ZodObject<{
        id: zod.ZodString;
        channel_id: zod.ZodString;
        guild_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        author: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>>>;
        member: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            user: zod.ZodObject<{
                id: zod.ZodString;
                username: zod.ZodString;
                discriminator: zod.ZodString;
                global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                    asset: zod.ZodString;
                    sku_id: zod.ZodOptional<zod.ZodString>;
                }, "strip", zod.ZodTypeAny, {
                    asset: string;
                    sku_id?: string | undefined;
                }, {
                    asset: string;
                    sku_id?: string | undefined;
                }>>;
                bot: zod.ZodBoolean;
                flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "strip", zod.ZodTypeAny, {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            }, {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            }>;
            nick: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            roles: zod.ZodArray<zod.ZodString, "many">;
            joined_at: zod.ZodString;
            deaf: zod.ZodBoolean;
            mute: zod.ZodBoolean;
        }, "strip", zod.ZodTypeAny, {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        }, {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        }>>>;
        content: zod.ZodString;
        timestamp: zod.ZodString;
        edited_timestamp: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        tts: zod.ZodBoolean;
        mention_everyone: zod.ZodBoolean;
        mentions: zod.ZodArray<zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>, "many">;
        mention_roles: zod.ZodArray<zod.ZodString, "many">;
        mention_channels: zod.ZodArray<zod.ZodObject<{
            id: zod.ZodString;
            guild_id: zod.ZodString;
            type: zod.ZodNumber;
            name: zod.ZodString;
        }, "strip", zod.ZodTypeAny, {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }, {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }>, "many">;
        attachments: zod.ZodArray<zod.ZodObject<{
            id: zod.ZodString;
            filename: zod.ZodString;
            size: zod.ZodNumber;
            url: zod.ZodString;
            proxy_url: zod.ZodString;
            height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }, {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }>, "many">;
        embeds: zod.ZodArray<zod.ZodObject<{
            title: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            type: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            description: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            timestamp: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            color: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            footer: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                text: zod.ZodString;
                icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                proxy_icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            }, "strip", zod.ZodTypeAny, {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            }, {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            }>>>;
            image: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                proxy_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "strip", zod.ZodTypeAny, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            }, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            }>>>;
            thumbnail: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                proxy_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "strip", zod.ZodTypeAny, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            }, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            }>>>;
            video: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<Omit<{
                url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                proxy_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                height: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                width: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            }, "proxy_url">, "strip", zod.ZodTypeAny, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            }, {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            }>>>;
            provider: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            }, "strip", zod.ZodTypeAny, {
                name?: string | null | undefined;
                url?: string | null | undefined;
            }, {
                name?: string | null | undefined;
                url?: string | null | undefined;
            }>>>;
            author: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                proxy_icon_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            }, "strip", zod.ZodTypeAny, {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            }, {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            }>>>;
            fields: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
                name: zod.ZodString;
                value: zod.ZodString;
                inline: zod.ZodBoolean;
            }, "strip", zod.ZodTypeAny, {
                value: string;
                name: string;
                inline: boolean;
            }, {
                value: string;
                name: string;
                inline: boolean;
            }>, "many">>>;
        }, "strip", zod.ZodTypeAny, {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }, {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }>, "many">;
        reactions: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodObject<{
            count: zod.ZodNumber;
            me: zod.ZodBoolean;
            emoji: zod.ZodObject<{
                id: zod.ZodString;
                name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                roles: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>>;
                user: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
                    id: zod.ZodString;
                    username: zod.ZodString;
                    discriminator: zod.ZodString;
                    global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
                    avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                        asset: zod.ZodString;
                        sku_id: zod.ZodOptional<zod.ZodString>;
                    }, "strip", zod.ZodTypeAny, {
                        asset: string;
                        sku_id?: string | undefined;
                    }, {
                        asset: string;
                        sku_id?: string | undefined;
                    }>>;
                    bot: zod.ZodBoolean;
                    flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                    premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
                }, "strip", zod.ZodTypeAny, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                }, {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                }>>>;
                require_colons: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                managed: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                animated: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
                available: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
            }, "strip", zod.ZodTypeAny, {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            }, {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            }>;
        }, "strip", zod.ZodTypeAny, {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }, {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }>, "many">>>;
        nonce: zod.ZodNullable<zod.ZodOptional<zod.ZodUnion<[zod.ZodString, zod.ZodNumber]>>>;
        pinned: zod.ZodBoolean;
        webhook_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        type: zod.ZodNumber;
        activity: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            type: zod.ZodNumber;
            party_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        }, "strip", zod.ZodTypeAny, {
            type: number;
            party_id?: string | null | undefined;
        }, {
            type: number;
            party_id?: string | null | undefined;
        }>>>;
        application: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            id: zod.ZodString;
            cover_image: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            description: zod.ZodString;
            icon: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            name: zod.ZodString;
        }, "strip", zod.ZodTypeAny, {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        }, {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        }>>>;
        message_reference: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            message_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            channel_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            guild_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        }, "strip", zod.ZodTypeAny, {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        }, {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        }>>>;
        flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        stickers: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodUnknown, "many">>>;
        referenced_message: zod.ZodNullable<zod.ZodOptional<zod.ZodUnknown>>;
    }, "strip", zod.ZodTypeAny, {
        type: number;
        id: string;
        content: string;
        timestamp: string;
        channel_id: string;
        tts: boolean;
        mention_everyone: boolean;
        mentions: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[];
        mention_roles: string[];
        mention_channels: {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }[];
        attachments: {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }[];
        embeds: {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }[];
        pinned: boolean;
        application?: {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        } | null | undefined;
        flags?: number | null | undefined;
        activity?: {
            type: number;
            party_id?: string | null | undefined;
        } | null | undefined;
        nonce?: string | number | null | undefined;
        guild_id?: string | null | undefined;
        author?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        member?: {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        } | null | undefined;
        edited_timestamp?: string | null | undefined;
        reactions?: {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }[] | null | undefined;
        webhook_id?: string | null | undefined;
        message_reference?: {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        } | null | undefined;
        stickers?: unknown[] | null | undefined;
        referenced_message?: unknown;
    }, {
        type: number;
        id: string;
        content: string;
        timestamp: string;
        channel_id: string;
        tts: boolean;
        mention_everyone: boolean;
        mentions: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[];
        mention_roles: string[];
        mention_channels: {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }[];
        attachments: {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }[];
        embeds: {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }[];
        pinned: boolean;
        application?: {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        } | null | undefined;
        flags?: number | null | undefined;
        activity?: {
            type: number;
            party_id?: string | null | undefined;
        } | null | undefined;
        nonce?: string | number | null | undefined;
        guild_id?: string | null | undefined;
        author?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        member?: {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        } | null | undefined;
        edited_timestamp?: string | null | undefined;
        reactions?: {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }[] | null | undefined;
        webhook_id?: string | null | undefined;
        message_reference?: {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        } | null | undefined;
        stickers?: unknown[] | null | undefined;
        referenced_message?: unknown;
    }>, "many">;
}, "strip", zod.ZodTypeAny, {
    type: 0 | 10 | 1 | 4 | 2 | 3 | 5 | 6 | 11 | 12 | 13 | 14 | 15 | -1;
    id: string;
    voice_states: {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        nick: string;
        mute: boolean;
        voice_state: {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        };
        volume: number;
    }[];
    messages: {
        type: number;
        id: string;
        content: string;
        timestamp: string;
        channel_id: string;
        tts: boolean;
        mention_everyone: boolean;
        mentions: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[];
        mention_roles: string[];
        mention_channels: {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }[];
        attachments: {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }[];
        embeds: {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }[];
        pinned: boolean;
        application?: {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        } | null | undefined;
        flags?: number | null | undefined;
        activity?: {
            type: number;
            party_id?: string | null | undefined;
        } | null | undefined;
        nonce?: string | number | null | undefined;
        guild_id?: string | null | undefined;
        author?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        member?: {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        } | null | undefined;
        edited_timestamp?: string | null | undefined;
        reactions?: {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }[] | null | undefined;
        webhook_id?: string | null | undefined;
        message_reference?: {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        } | null | undefined;
        stickers?: unknown[] | null | undefined;
        referenced_message?: unknown;
    }[];
    name?: string | null | undefined;
    guild_id?: string | null | undefined;
    position?: number | null | undefined;
    topic?: string | null | undefined;
    bitrate?: number | null | undefined;
    user_limit?: number | null | undefined;
}, {
    id: string;
    voice_states: {
        user: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        };
        nick: string;
        mute: boolean;
        voice_state: {
            deaf: boolean;
            mute: boolean;
            self_mute: boolean;
            self_deaf: boolean;
            suppress: boolean;
        };
        volume: number;
    }[];
    messages: {
        type: number;
        id: string;
        content: string;
        timestamp: string;
        channel_id: string;
        tts: boolean;
        mention_everyone: boolean;
        mentions: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }[];
        mention_roles: string[];
        mention_channels: {
            type: number;
            id: string;
            name: string;
            guild_id: string;
        }[];
        attachments: {
            id: string;
            url: string;
            size: number;
            filename: string;
            proxy_url: string;
            height?: number | null | undefined;
            width?: number | null | undefined;
        }[];
        embeds: {
            type?: string | null | undefined;
            description?: string | null | undefined;
            url?: string | null | undefined;
            color?: number | null | undefined;
            title?: string | null | undefined;
            timestamp?: string | null | undefined;
            footer?: {
                text: string;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            image?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            thumbnail?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
                proxy_url?: string | null | undefined;
            } | null | undefined;
            video?: {
                height?: number | null | undefined;
                url?: string | null | undefined;
                width?: number | null | undefined;
            } | null | undefined;
            provider?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
            } | null | undefined;
            author?: {
                name?: string | null | undefined;
                url?: string | null | undefined;
                icon_url?: string | null | undefined;
                proxy_icon_url?: string | null | undefined;
            } | null | undefined;
            fields?: {
                value: string;
                name: string;
                inline: boolean;
            }[] | null | undefined;
        }[];
        pinned: boolean;
        application?: {
            id: string;
            description: string;
            name: string;
            icon?: string | null | undefined;
            cover_image?: string | null | undefined;
        } | null | undefined;
        flags?: number | null | undefined;
        activity?: {
            type: number;
            party_id?: string | null | undefined;
        } | null | undefined;
        nonce?: string | number | null | undefined;
        guild_id?: string | null | undefined;
        author?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        member?: {
            user: {
                username: string;
                discriminator: string;
                id: string;
                bot: boolean;
                avatar_decoration_data: {
                    asset: string;
                    sku_id?: string | undefined;
                } | null;
                avatar?: string | null | undefined;
                global_name?: string | null | undefined;
                flags?: number | null | undefined;
                premium_type?: number | null | undefined;
            };
            roles: string[];
            joined_at: string;
            deaf: boolean;
            mute: boolean;
            nick?: string | null | undefined;
        } | null | undefined;
        edited_timestamp?: string | null | undefined;
        reactions?: {
            emoji: {
                id: string;
                user?: {
                    username: string;
                    discriminator: string;
                    id: string;
                    bot: boolean;
                    avatar_decoration_data: {
                        asset: string;
                        sku_id?: string | undefined;
                    } | null;
                    avatar?: string | null | undefined;
                    global_name?: string | null | undefined;
                    flags?: number | null | undefined;
                    premium_type?: number | null | undefined;
                } | null | undefined;
                name?: string | null | undefined;
                animated?: boolean | null | undefined;
                roles?: string[] | null | undefined;
                require_colons?: boolean | null | undefined;
                managed?: boolean | null | undefined;
                available?: boolean | null | undefined;
            };
            count: number;
            me: boolean;
        }[] | null | undefined;
        webhook_id?: string | null | undefined;
        message_reference?: {
            guild_id?: string | null | undefined;
            message_id?: string | null | undefined;
            channel_id?: string | null | undefined;
        } | null | undefined;
        stickers?: unknown[] | null | undefined;
        referenced_message?: unknown;
    }[];
    type?: unknown;
    name?: string | null | undefined;
    guild_id?: string | null | undefined;
    position?: number | null | undefined;
    topic?: string | null | undefined;
    bitrate?: number | null | undefined;
    user_limit?: number | null | undefined;
}>>;
export declare const VoiceSettingsResponse: zod.ZodObject<{
    input: zod.ZodObject<{
        device_id: zod.ZodString;
        volume: zod.ZodNumber;
        available_devices: zod.ZodArray<zod.ZodObject<{
            id: zod.ZodString;
            name: zod.ZodString;
        }, "strip", zod.ZodTypeAny, {
            id: string;
            name: string;
        }, {
            id: string;
            name: string;
        }>, "many">;
    }, "strip", zod.ZodTypeAny, {
        volume: number;
        device_id: string;
        available_devices: {
            id: string;
            name: string;
        }[];
    }, {
        volume: number;
        device_id: string;
        available_devices: {
            id: string;
            name: string;
        }[];
    }>;
    output: zod.ZodObject<{
        device_id: zod.ZodString;
        volume: zod.ZodNumber;
        available_devices: zod.ZodArray<zod.ZodObject<{
            id: zod.ZodString;
            name: zod.ZodString;
        }, "strip", zod.ZodTypeAny, {
            id: string;
            name: string;
        }, {
            id: string;
            name: string;
        }>, "many">;
    }, "strip", zod.ZodTypeAny, {
        volume: number;
        device_id: string;
        available_devices: {
            id: string;
            name: string;
        }[];
    }, {
        volume: number;
        device_id: string;
        available_devices: {
            id: string;
            name: string;
        }[];
    }>;
    mode: zod.ZodObject<{
        type: zod.ZodEffects<zod.ZodType<-1 | "PUSH_TO_TALK" | "VOICE_ACTIVITY", zod.ZodTypeDef, -1 | "PUSH_TO_TALK" | "VOICE_ACTIVITY">, -1 | "PUSH_TO_TALK" | "VOICE_ACTIVITY", unknown>;
        auto_threshold: zod.ZodBoolean;
        threshold: zod.ZodNumber;
        shortcut: zod.ZodArray<zod.ZodObject<{
            type: zod.ZodEffects<zod.ZodType<0 | 1 | 2 | 3 | -1, zod.ZodTypeDef, 0 | 1 | 2 | 3 | -1>, 0 | 1 | 2 | 3 | -1, unknown>;
            code: zod.ZodNumber;
            name: zod.ZodString;
        }, "strip", zod.ZodTypeAny, {
            code: number;
            type: 0 | 1 | 2 | 3 | -1;
            name: string;
        }, {
            code: number;
            name: string;
            type?: unknown;
        }>, "many">;
        delay: zod.ZodNumber;
    }, "strip", zod.ZodTypeAny, {
        type: -1 | "PUSH_TO_TALK" | "VOICE_ACTIVITY";
        auto_threshold: boolean;
        threshold: number;
        shortcut: {
            code: number;
            type: 0 | 1 | 2 | 3 | -1;
            name: string;
        }[];
        delay: number;
    }, {
        auto_threshold: boolean;
        threshold: number;
        shortcut: {
            code: number;
            name: string;
            type?: unknown;
        }[];
        delay: number;
        type?: unknown;
    }>;
    automatic_gain_control: zod.ZodBoolean;
    echo_cancellation: zod.ZodBoolean;
    noise_suppression: zod.ZodBoolean;
    qos: zod.ZodBoolean;
    silence_warning: zod.ZodBoolean;
    deaf: zod.ZodBoolean;
    mute: zod.ZodBoolean;
}, "strip", zod.ZodTypeAny, {
    deaf: boolean;
    mute: boolean;
    echo_cancellation: boolean;
    noise_suppression: boolean;
    automatic_gain_control: boolean;
    input: {
        volume: number;
        device_id: string;
        available_devices: {
            id: string;
            name: string;
        }[];
    };
    output: {
        volume: number;
        device_id: string;
        available_devices: {
            id: string;
            name: string;
        }[];
    };
    mode: {
        type: -1 | "PUSH_TO_TALK" | "VOICE_ACTIVITY";
        auto_threshold: boolean;
        threshold: number;
        shortcut: {
            code: number;
            type: 0 | 1 | 2 | 3 | -1;
            name: string;
        }[];
        delay: number;
    };
    qos: boolean;
    silence_warning: boolean;
}, {
    deaf: boolean;
    mute: boolean;
    echo_cancellation: boolean;
    noise_suppression: boolean;
    automatic_gain_control: boolean;
    input: {
        volume: number;
        device_id: string;
        available_devices: {
            id: string;
            name: string;
        }[];
    };
    output: {
        volume: number;
        device_id: string;
        available_devices: {
            id: string;
            name: string;
        }[];
    };
    mode: {
        auto_threshold: boolean;
        threshold: number;
        shortcut: {
            code: number;
            name: string;
            type?: unknown;
        }[];
        delay: number;
        type?: unknown;
    };
    qos: boolean;
    silence_warning: boolean;
}>;
export declare const SubscribeResponse: zod.ZodObject<{
    evt: zod.ZodString;
}, "strip", zod.ZodTypeAny, {
    evt: string;
}, {
    evt: string;
}>;
export declare const CaptureShortcutResponse: zod.ZodObject<{
    shortcut: zod.ZodObject<{
        type: zod.ZodEffects<zod.ZodType<0 | 1 | 2 | 3 | -1, zod.ZodTypeDef, 0 | 1 | 2 | 3 | -1>, 0 | 1 | 2 | 3 | -1, unknown>;
        code: zod.ZodNumber;
        name: zod.ZodString;
    }, "strip", zod.ZodTypeAny, {
        code: number;
        type: 0 | 1 | 2 | 3 | -1;
        name: string;
    }, {
        code: number;
        name: string;
        type?: unknown;
    }>;
}, "strip", zod.ZodTypeAny, {
    shortcut: {
        code: number;
        type: 0 | 1 | 2 | 3 | -1;
        name: string;
    };
}, {
    shortcut: {
        code: number;
        name: string;
        type?: unknown;
    };
}>;
export declare const SetActivityResponse: zod.ZodObject<{
    name: zod.ZodString;
    type: zod.ZodNumber;
    url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    created_at: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
    timestamps: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        start: zod.ZodOptional<zod.ZodNumber>;
        end: zod.ZodOptional<zod.ZodNumber>;
    }, "strip", zod.ZodTypeAny, {
        start?: number | undefined;
        end?: number | undefined;
    }, {
        start?: number | undefined;
        end?: number | undefined;
    }>>>;
    application_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    details: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    details_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    state: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    state_url: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    emoji: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        id: zod.ZodString;
        name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        roles: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>>;
        user: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
            id: zod.ZodString;
            username: zod.ZodString;
            discriminator: zod.ZodString;
            global_name: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
            avatar_decoration_data: zod.ZodNullable<zod.ZodObject<{
                asset: zod.ZodString;
                sku_id: zod.ZodOptional<zod.ZodString>;
            }, "strip", zod.ZodTypeAny, {
                asset: string;
                sku_id?: string | undefined;
            }, {
                asset: string;
                sku_id?: string | undefined;
            }>>;
            bot: zod.ZodBoolean;
            flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
            premium_type: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
        }, "strip", zod.ZodTypeAny, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }, {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        }>>>;
        require_colons: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        managed: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        animated: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        available: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    }, "strip", zod.ZodTypeAny, {
        id: string;
        user?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        name?: string | null | undefined;
        animated?: boolean | null | undefined;
        roles?: string[] | null | undefined;
        require_colons?: boolean | null | undefined;
        managed?: boolean | null | undefined;
        available?: boolean | null | undefined;
    }, {
        id: string;
        user?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        name?: string | null | undefined;
        animated?: boolean | null | undefined;
        roles?: string[] | null | undefined;
        require_colons?: boolean | null | undefined;
        managed?: boolean | null | undefined;
        available?: boolean | null | undefined;
    }>>>;
    party: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        size: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodNumber, "many">>>;
    }, "strip", zod.ZodTypeAny, {
        id?: string | null | undefined;
        size?: number[] | null | undefined;
    }, {
        id?: string | null | undefined;
        size?: number[] | null | undefined;
    }>>>;
    assets: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        large_image: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
        large_text: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
        large_url: zod.ZodOptional<zod.ZodNullable<zod.ZodOptional<zod.ZodString>>>;
        small_image: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
        small_text: zod.ZodOptional<zod.ZodNullable<zod.ZodString>>;
        small_url: zod.ZodOptional<zod.ZodNullable<zod.ZodOptional<zod.ZodString>>>;
    }, "strip", zod.ZodTypeAny, {
        large_image?: string | null | undefined;
        large_text?: string | null | undefined;
        large_url?: string | null | undefined;
        small_image?: string | null | undefined;
        small_text?: string | null | undefined;
        small_url?: string | null | undefined;
    }, {
        large_image?: string | null | undefined;
        large_text?: string | null | undefined;
        large_url?: string | null | undefined;
        small_image?: string | null | undefined;
        small_text?: string | null | undefined;
        small_url?: string | null | undefined;
    }>>>;
    secrets: zod.ZodNullable<zod.ZodOptional<zod.ZodObject<{
        join: zod.ZodOptional<zod.ZodString>;
        match: zod.ZodOptional<zod.ZodString>;
    }, "strip", zod.ZodTypeAny, {
        join?: string | undefined;
        match?: string | undefined;
    }, {
        join?: string | undefined;
        match?: string | undefined;
    }>>>;
    instance: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    flags: zod.ZodNullable<zod.ZodOptional<zod.ZodNumber>>;
}, "strip", zod.ZodTypeAny, {
    type: number;
    name: string;
    flags?: number | null | undefined;
    url?: string | null | undefined;
    application_id?: string | null | undefined;
    state?: string | null | undefined;
    state_url?: string | null | undefined;
    details?: string | null | undefined;
    details_url?: string | null | undefined;
    emoji?: {
        id: string;
        user?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        name?: string | null | undefined;
        animated?: boolean | null | undefined;
        roles?: string[] | null | undefined;
        require_colons?: boolean | null | undefined;
        managed?: boolean | null | undefined;
        available?: boolean | null | undefined;
    } | null | undefined;
    assets?: {
        large_image?: string | null | undefined;
        large_text?: string | null | undefined;
        large_url?: string | null | undefined;
        small_image?: string | null | undefined;
        small_text?: string | null | undefined;
        small_url?: string | null | undefined;
    } | null | undefined;
    timestamps?: {
        start?: number | undefined;
        end?: number | undefined;
    } | null | undefined;
    party?: {
        id?: string | null | undefined;
        size?: number[] | null | undefined;
    } | null | undefined;
    secrets?: {
        join?: string | undefined;
        match?: string | undefined;
    } | null | undefined;
    created_at?: number | null | undefined;
    instance?: boolean | null | undefined;
}, {
    type: number;
    name: string;
    flags?: number | null | undefined;
    url?: string | null | undefined;
    application_id?: string | null | undefined;
    state?: string | null | undefined;
    state_url?: string | null | undefined;
    details?: string | null | undefined;
    details_url?: string | null | undefined;
    emoji?: {
        id: string;
        user?: {
            username: string;
            discriminator: string;
            id: string;
            bot: boolean;
            avatar_decoration_data: {
                asset: string;
                sku_id?: string | undefined;
            } | null;
            avatar?: string | null | undefined;
            global_name?: string | null | undefined;
            flags?: number | null | undefined;
            premium_type?: number | null | undefined;
        } | null | undefined;
        name?: string | null | undefined;
        animated?: boolean | null | undefined;
        roles?: string[] | null | undefined;
        require_colons?: boolean | null | undefined;
        managed?: boolean | null | undefined;
        available?: boolean | null | undefined;
    } | null | undefined;
    assets?: {
        large_image?: string | null | undefined;
        large_text?: string | null | undefined;
        large_url?: string | null | undefined;
        small_image?: string | null | undefined;
        small_text?: string | null | undefined;
        small_url?: string | null | undefined;
    } | null | undefined;
    timestamps?: {
        start?: number | undefined;
        end?: number | undefined;
    } | null | undefined;
    party?: {
        id?: string | null | undefined;
        size?: number[] | null | undefined;
    } | null | undefined;
    secrets?: {
        join?: string | undefined;
        match?: string | undefined;
    } | null | undefined;
    created_at?: number | null | undefined;
    instance?: boolean | null | undefined;
}>;
export declare const GetSkusResponse: zod.ZodObject<{
    skus: zod.ZodArray<zod.ZodObject<{
        id: zod.ZodString;
        name: zod.ZodString;
        type: zod.ZodEffects<zod.ZodType<1 | 4 | 2 | 3 | 5 | -1, zod.ZodTypeDef, 1 | 4 | 2 | 3 | 5 | -1>, 1 | 4 | 2 | 3 | 5 | -1, unknown>;
        price: zod.ZodObject<{
            amount: zod.ZodNumber;
            currency: zod.ZodString;
        }, "strip", zod.ZodTypeAny, {
            amount: number;
            currency: string;
        }, {
            amount: number;
            currency: string;
        }>;
        application_id: zod.ZodString;
        flags: zod.ZodNumber;
        release_date: zod.ZodNullable<zod.ZodString>;
    }, "strip", zod.ZodTypeAny, {
        type: 1 | 4 | 2 | 3 | 5 | -1;
        id: string;
        name: string;
        flags: number;
        application_id: string;
        price: {
            amount: number;
            currency: string;
        };
        release_date: string | null;
    }, {
        id: string;
        name: string;
        flags: number;
        application_id: string;
        price: {
            amount: number;
            currency: string;
        };
        release_date: string | null;
        type?: unknown;
    }>, "many">;
}, "strip", zod.ZodTypeAny, {
    skus: {
        type: 1 | 4 | 2 | 3 | 5 | -1;
        id: string;
        name: string;
        flags: number;
        application_id: string;
        price: {
            amount: number;
            currency: string;
        };
        release_date: string | null;
    }[];
}, {
    skus: {
        id: string;
        name: string;
        flags: number;
        application_id: string;
        price: {
            amount: number;
            currency: string;
        };
        release_date: string | null;
        type?: unknown;
    }[];
}>;
export declare const GetEntitlementsResponse: zod.ZodObject<{
    entitlements: zod.ZodArray<zod.ZodObject<{
        id: zod.ZodString;
        sku_id: zod.ZodString;
        application_id: zod.ZodString;
        user_id: zod.ZodString;
        gift_code_flags: zod.ZodNumber;
        type: zod.ZodEffects<zod.ZodType<1 | 4 | 2 | 3 | 5 | 6 | 7 | -1, zod.ZodTypeDef, 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1>, 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1, unknown>;
        gifter_user_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        branches: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>>;
        starts_at: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        ends_at: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        parent_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
        consumed: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        deleted: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
        gift_code_batch_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    }, "strip", zod.ZodTypeAny, {
        type: 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1;
        id: string;
        application_id: string;
        user_id: string;
        sku_id: string;
        gift_code_flags: number;
        parent_id?: string | null | undefined;
        gifter_user_id?: string | null | undefined;
        branches?: string[] | null | undefined;
        starts_at?: string | null | undefined;
        ends_at?: string | null | undefined;
        consumed?: boolean | null | undefined;
        deleted?: boolean | null | undefined;
        gift_code_batch_id?: string | null | undefined;
    }, {
        id: string;
        application_id: string;
        user_id: string;
        sku_id: string;
        gift_code_flags: number;
        type?: unknown;
        parent_id?: string | null | undefined;
        gifter_user_id?: string | null | undefined;
        branches?: string[] | null | undefined;
        starts_at?: string | null | undefined;
        ends_at?: string | null | undefined;
        consumed?: boolean | null | undefined;
        deleted?: boolean | null | undefined;
        gift_code_batch_id?: string | null | undefined;
    }>, "many">;
}, "strip", zod.ZodTypeAny, {
    entitlements: {
        type: 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1;
        id: string;
        application_id: string;
        user_id: string;
        sku_id: string;
        gift_code_flags: number;
        parent_id?: string | null | undefined;
        gifter_user_id?: string | null | undefined;
        branches?: string[] | null | undefined;
        starts_at?: string | null | undefined;
        ends_at?: string | null | undefined;
        consumed?: boolean | null | undefined;
        deleted?: boolean | null | undefined;
        gift_code_batch_id?: string | null | undefined;
    }[];
}, {
    entitlements: {
        id: string;
        application_id: string;
        user_id: string;
        sku_id: string;
        gift_code_flags: number;
        type?: unknown;
        parent_id?: string | null | undefined;
        gifter_user_id?: string | null | undefined;
        branches?: string[] | null | undefined;
        starts_at?: string | null | undefined;
        ends_at?: string | null | undefined;
        consumed?: boolean | null | undefined;
        deleted?: boolean | null | undefined;
        gift_code_batch_id?: string | null | undefined;
    }[];
}>;
export declare const StartPurchaseResponse: zod.ZodNullable<zod.ZodArray<zod.ZodObject<{
    id: zod.ZodString;
    sku_id: zod.ZodString;
    application_id: zod.ZodString;
    user_id: zod.ZodString;
    gift_code_flags: zod.ZodNumber;
    type: zod.ZodEffects<zod.ZodType<1 | 4 | 2 | 3 | 5 | 6 | 7 | -1, zod.ZodTypeDef, 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1>, 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1, unknown>;
    gifter_user_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    branches: zod.ZodNullable<zod.ZodOptional<zod.ZodArray<zod.ZodString, "many">>>;
    starts_at: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    ends_at: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    parent_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
    consumed: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    deleted: zod.ZodNullable<zod.ZodOptional<zod.ZodBoolean>>;
    gift_code_batch_id: zod.ZodNullable<zod.ZodOptional<zod.ZodString>>;
}, "strip", zod.ZodTypeAny, {
    type: 1 | 4 | 2 | 3 | 5 | 6 | 7 | -1;
    id: string;
    application_id: string;
    user_id: string;
    sku_id: string;
    gift_code_flags: number;
    parent_id?: string | null | undefined;
    gifter_user_id?: string | null | undefined;
    branches?: string[] | null | undefined;
    starts_at?: string | null | undefined;
    ends_at?: string | null | undefined;
    consumed?: boolean | null | undefined;
    deleted?: boolean | null | undefined;
    gift_code_batch_id?: string | null | undefined;
}, {
    id: string;
    application_id: string;
    user_id: string;
    sku_id: string;
    gift_code_flags: number;
    type?: unknown;
    parent_id?: string | null | undefined;
    gifter_user_id?: string | null | undefined;
    branches?: string[] | null | undefined;
    starts_at?: string | null | undefined;
    ends_at?: string | null | undefined;
    consumed?: boolean | null | undefined;
    deleted?: boolean | null | undefined;
    gift_code_batch_id?: string | null | undefined;
}>, "many">>;
export declare const SetConfigResponse: zod.ZodObject<{
    use_interactive_pip: zod.ZodBoolean;
}, "strip", zod.ZodTypeAny, {
    use_interactive_pip: boolean;
}, {
    use_interactive_pip: boolean;
}>;
export declare const UserSettingsGetLocaleResponse: zod.ZodObject<{
    locale: zod.ZodString;
}, "strip", zod.ZodTypeAny, {
    locale: string;
}, {
    locale: string;
}>;
export declare const EncourageHardwareAccelerationResponse: zod.ZodObject<{
    enabled: zod.ZodBoolean;
}, "strip", zod.ZodTypeAny, {
    enabled: boolean;
}, {
    enabled: boolean;
}>;
export declare const GetChannelPermissionsResponse: zod.ZodObject<{
    permissions: zod.ZodUnion<[zod.ZodBigInt, zod.ZodString]>;
}, "strip", zod.ZodTypeAny, {
    permissions: string | bigint;
}, {
    permissions: string | bigint;
}>;
export declare const OpenExternalLinkResponse: import("../utils/zodUtils").ZodEffectOverlayType<zod.ZodDefault<zod.ZodObject<{
    opened: zod.ZodUnion<[zod.ZodBoolean, zod.ZodNull]>;
}, "strip", zod.ZodTypeAny, {
    opened: boolean | null;
}, {
    opened: boolean | null;
}>>>;
/**
 * Because of the nature of Platform Behavior changes
 * every key/value is optional and may eventually be removed
 */
export declare const GetPlatformBehaviorsResponse: zod.ZodObject<{
    iosKeyboardResizesView: zod.ZodOptional<zod.ZodBoolean>;
}, "strip", zod.ZodTypeAny, {
    iosKeyboardResizesView?: boolean | undefined;
}, {
    iosKeyboardResizesView?: boolean | undefined;
}>;
export declare const ResponseFrame: zod.ZodObject<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    cmd: zod.ZodNativeEnum<typeof Commands>;
    evt: zod.ZodNull;
}>, "passthrough", zod.ZodTypeAny, zod.objectOutputType<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    cmd: zod.ZodNativeEnum<typeof Commands>;
    evt: zod.ZodNull;
}>, zod.ZodTypeAny, "passthrough">, zod.objectInputType<zod.objectUtil.extendShape<{
    cmd: zod.ZodString;
    data: zod.ZodUnknown;
    evt: zod.ZodNull;
    nonce: zod.ZodString;
}, {
    cmd: zod.ZodNativeEnum<typeof Commands>;
    evt: zod.ZodNull;
}>, zod.ZodTypeAny, "passthrough">>;
export declare function parseResponsePayload(payload: zod.infer<typeof ResponseFrame>): {
    data: {} | null | undefined;
    cmd: Commands;
    evt: null;
    nonce: string;
};

// ===== output/schema/types.d.ts =====
export type TSendCommandPayload<C extends Common.Commands = Common.Commands, I extends any = any> = {
    cmd: Exclude<C, Common.Commands.SUBSCRIBE | Common.Commands.UNSUBSCRIBE>;
    args?: I;
    transfer?: Transferable[];
} | {
    cmd: Common.Commands.SUBSCRIBE | Common.Commands.UNSUBSCRIBE;
    args?: I;
    evt: string;
};
export type TSendCommand<C extends Common.Commands = Common.Commands, I extends any = any, O extends any = any> = ({ cmd, args, }: TSendCommandPayload<C, I>) => Promise<O>;
export type User = zod.infer<typeof Common.User>;
export type GuildMember = zod.infer<typeof Common.GuildMember>;
export type Emoji = zod.infer<typeof Common.Emoji>;
export type VoiceState = zod.infer<typeof Common.VoiceState>;
export type Status = zod.infer<typeof Common.Status>;
export type Activity = zod.infer<typeof Common.Activity>;
export type PermissionOverwrite = zod.infer<typeof Common.PermissionOverwrite>;
export type ChannelTypes = typeof Common.ChannelTypesObject;
export type Channel = zod.infer<typeof Common.Channel>;
export type PresenceUpdate = zod.infer<typeof Common.PresenceUpdate>;
export type Role = zod.infer<typeof Common.Role>;
export type Guild = zod.infer<typeof Common.Guild>;
export type ChannelMention = zod.infer<typeof Common.ChannelMention>;
export type Attachment = zod.infer<typeof Common.Attachment>;
export type EmbedFooter = zod.infer<typeof Common.EmbedFooter>;
export type Image = zod.infer<typeof Common.Image>;
export type Video = zod.infer<typeof Common.Video>;
export type EmbedProvider = zod.infer<typeof Common.EmbedProvider>;
export type EmbedField = zod.infer<typeof Common.EmbedField>;
export type Embed = zod.infer<typeof Common.Embed>;
export type Reaction = zod.infer<typeof Common.Reaction>;
export type MessageActivity = zod.infer<typeof Common.MessageActivity>;
export type MessageReference = zod.infer<typeof Common.MessageReference>;
export type Message = zod.infer<typeof Common.Message>;
export type VoiceDevice = zod.infer<typeof Common.VoiceDevice>;
export type KeyTypes = typeof Common.KeyTypesObject;
export type ShortcutKey = zod.infer<typeof Common.ShortcutKey>;
export type VoiceSettingsMode = zod.infer<typeof Common.VoiceSettingsMode>;
export type VoiceSettingsIO = zod.infer<typeof Common.VoiceSettingsIO>;
export type CertifiedDevice = zod.infer<typeof Common.CertifiedDevice>;
export type ScopesObject = typeof Common.ScopesObject;
export type StatusObject = typeof Common.StatusObject;
export type PermissionOverwriteTypeEnum = typeof Common.PermissionOverwriteTypeObject;
export type ChannelTypesObject = typeof Common.ChannelTypesObject;
export type KeyTypesObject = typeof Common.KeyTypesObject;
export type VoiceSettingModeTypeObject = typeof Common.VoiceSettingModeTypeObject;
export type CertifiedDeviceTypeObject = typeof Common.CertifiedDeviceTypeObject;
export type SkuTypeObject = typeof Common.SkuTypeObject;
export type EntitlementTypesObject = typeof Common.EntitlementTypesObject;
export type VoiceConnectionStatusStateObject = typeof Events.VoiceConnectionStatusStateObject;
export type ActivityJoinIntentObject = typeof Events.ActivityJoinIntentObject;
export type OrientationLockStateTypeObject = typeof Common.OrientationLockStateTypeObject;
export type ThermalStateTypeObject = typeof Common.ThermalStateTypeObject;
export type OrientationTypeObject = typeof Common.OrientationTypeObject;
export type LayoutModeTypeObject = typeof Common.LayoutModeTypeObject;
export type OAuthScopes = 'bot' | 'rpc' | 'identify' | 'connections' | 'email' | 'guilds' | 'guilds.join' | 'guilds.members.read' | 'gdm.join' | 'messages.read' | 'rpc.notifications.read' | 'rpc.voice.write' | 'rpc.voice.read' | 'rpc.activities.write' | 'webhook.incoming' | 'applications.commands' | 'applications.builds.upload' | 'applications.builds.read' | 'applications.store.update' | 'applications.entitlements' | 'relationships.read' | 'activities.read' | 'activities.write' | 'dm_channels.read';
export type { GetActivityInstanceConnectedParticipantsResponse };

// ===== output/utils/BigFlagUtils.d.ts =====
/**
 * Context: Due to Discord supporting more than 32 permissions, permission calculation has become more complicated than naive
 * bit operations on `number`s. To support this generically, we have created BigFlagUtils to work with bit-flags greater
 * than 32-bits in size.
 *
 * Ideally, we would like to use BigInt, which is pretty efficient, but some JavaScript engines do not support it.
 *
 * This file is intended to be a set of lower-level operators that act directly on "BigFlags".
 *
 * If you're working with permissions, in most cases you can probably use PermissionUtils.
 */
$1export declare class HighLow {
    parts: number[];
    str: string | undefined;
    static fromString(value: string): HighLow;
    static fromBit(index: number): HighLow;
    constructor(parts: number[], str?: string);
    and({ parts }: HighLow): HighLow;
    or({ parts }: HighLow): HighLow;
    xor({ parts }: HighLow): HighLow;
    not(): HighLow;
    equals({ parts }: HighLow): boolean;
    /**
     * For the average case the string representation is provided, but
     * when we need to convert high and low to string we just let the
     * slower big-integer library do it.
     */
    toString(): string;
    toJSON(): string;
}
declare global {
    interface BigInt {
        toJSON(): string;
    }
}
/**
 * Technically, it should be one or the other, but Typescript doesn't seem
 * to have the power to express that dynamically yet.
 */
export type BigFlag = bigint | HighLow;
export declare const isBigFlag: (value: any) => value is BigFlag;
$1export declare function flagOrMultiple(...flags: BigFlag[]): BigFlag;
$1export declare function flagHas(base: BigFlag, flag: BigFlag): boolean;
$1export declare function flagHasAny(base: BigFlag, flag: BigFlag): boolean;
$1export declare function flagAdd(base: BigFlag, flag: BigFlag): BigFlag;
$1export declare function flagRemove(base: BigFlag, flag: BigFlag): BigFlag;
$1export declare const _default: {
    combine: typeof flagOrMultiple;
    add: typeof flagAdd;
    remove: typeof flagRemove;
    filter: (first: BigFlag, second: BigFlag) => BigFlag;
    invert: (first: BigFlag | undefined) => BigFlag;
    has: typeof flagHas;
    hasAny: typeof flagHasAny;
    equals: (first: BigFlag | undefined, second: BigFlag | undefined) => boolean;
    deserialize: (value: number | string | BigFlag) => BigFlag;
    getFlag: (index: number) => BigFlag;
};
export _default;

// ===== output/utils/PermissionUtils.d.ts =====
$1export declare function can(permission: BigFlag, permissions: BigFlag | string): boolean;
$1export declare const _default: {
    can: typeof can;
};
export _default;

// ===== output/utils/PriceConstants.d.ts =====
export declare enum CurrencyCodes {
    AED = "aed",
    AFN = "afn",
    ALL = "all",
    AMD = "amd",
    ANG = "ang",
    AOA = "aoa",
    ARS = "ars",
    AUD = "aud",
    AWG = "awg",
    AZN = "azn",
    BAM = "bam",
    BBD = "bbd",
    BDT = "bdt",
    BGN = "bgn",
    BHD = "bhd",
    BIF = "bif",
    BMD = "bmd",
    BND = "bnd",
    BOB = "bob",
    BOV = "bov",
    BRL = "brl",
    BSD = "bsd",
    BTN = "btn",
    BWP = "bwp",
    BYN = "byn",
    BYR = "byr",
    BZD = "bzd",
    CAD = "cad",
    CDF = "cdf",
    CHE = "che",
    CHF = "chf",
    CHW = "chw",
    CLF = "clf",
    CLP = "clp",
    CNY = "cny",
    COP = "cop",
    COU = "cou",
    CRC = "crc",
    CUC = "cuc",
    CUP = "cup",
    CVE = "cve",
    CZK = "czk",
    DJF = "djf",
    DKK = "dkk",
    DOP = "dop",
    DZD = "dzd",
    EGP = "egp",
    ERN = "ern",
    ETB = "etb",
    EUR = "eur",
    FJD = "fjd",
    FKP = "fkp",
    GBP = "gbp",
    GEL = "gel",
    GHS = "ghs",
    GIP = "gip",
    GMD = "gmd",
    GNF = "gnf",
    GTQ = "gtq",
    GYD = "gyd",
    HKD = "hkd",
    HNL = "hnl",
    HRK = "hrk",
    HTG = "htg",
    HUF = "huf",
    IDR = "idr",
    ILS = "ils",
    INR = "inr",
    IQD = "iqd",
    IRR = "irr",
    ISK = "isk",
    JMD = "jmd",
    JOD = "jod",
    JPY = "jpy",
    KES = "kes",
    KGS = "kgs",
    KHR = "khr",
    KMF = "kmf",
    KPW = "kpw",
    KRW = "krw",
    KWD = "kwd",
    KYD = "kyd",
    KZT = "kzt",
    LAK = "lak",
    LBP = "lbp",
    LKR = "lkr",
    LRD = "lrd",
    LSL = "lsl",
    LTL = "ltl",
    LVL = "lvl",
    LYD = "lyd",
    MAD = "mad",
    MDL = "mdl",
    MGA = "mga",
    MKD = "mkd",
    MMK = "mmk",
    MNT = "mnt",
    MOP = "mop",
    MRO = "mro",
    MUR = "mur",
    MVR = "mvr",
    MWK = "mwk",
    MXN = "mxn",
    MXV = "mxv",
    MYR = "myr",
    MZN = "mzn",
    NAD = "nad",
    NGN = "ngn",
    NIO = "nio",
    NOK = "nok",
    NPR = "npr",
    NZD = "nzd",
    OMR = "omr",
    PAB = "pab",
    PEN = "pen",
    PGK = "pgk",
    PHP = "php",
    PKR = "pkr",
    PLN = "pln",
    PYG = "pyg",
    QAR = "qar",
    RON = "ron",
    RSD = "rsd",
    RUB = "rub",
    RWF = "rwf",
    SAR = "sar",
    SBD = "sbd",
    SCR = "scr",
    SDG = "sdg",
    SEK = "sek",
    SGD = "sgd",
    SHP = "shp",
    SLL = "sll",
    SOS = "sos",
    SRD = "srd",
    SSP = "ssp",
    STD = "std",
    SVC = "svc",
    SYP = "syp",
    SZL = "szl",
    THB = "thb",
    TJS = "tjs",
    TMT = "tmt",
    TND = "tnd",
    TOP = "top",
    TRY = "try",
    TTD = "ttd",
    TWD = "twd",
    TZS = "tzs",
    UAH = "uah",
    UGX = "ugx",
    USD = "usd",
    USN = "usn",
    USS = "uss",
    UYI = "uyi",
    UYU = "uyu",
    UZS = "uzs",
    VEF = "vef",
    VND = "vnd",
    VUV = "vuv",
    WST = "wst",
    XAF = "xaf",
    XAG = "xag",
    XAU = "xau",
    XBA = "xba",
    XBB = "xbb",
    XBC = "xbc",
    XBD = "xbd",
    XCD = "xcd",
    XDR = "xdr",
    XFU = "xfu",
    XOF = "xof",
    XPD = "xpd",
    XPF = "xpf",
    XPT = "xpt",
    XSU = "xsu",
    XTS = "xts",
    XUA = "xua",
    YER = "yer",
    ZAR = "zar",
    ZMW = "zmw",
    ZWL = "zwl"
}
export declare const CurrencyExponents: {
    aed: number;
    afn: number;
    all: number;
    amd: number;
    ang: number;
    aoa: number;
    ars: number;
    aud: number;
    awg: number;
    azn: number;
    bam: number;
    bbd: number;
    bdt: number;
    bgn: number;
    bhd: number;
    bif: number;
    bmd: number;
    bnd: number;
    bob: number;
    bov: number;
    brl: number;
    bsd: number;
    btn: number;
    bwp: number;
    byr: number;
    byn: number;
    bzd: number;
    cad: number;
    cdf: number;
    che: number;
    chf: number;
    chw: number;
    clf: number;
    clp: number;
    cny: number;
    cop: number;
    cou: number;
    crc: number;
    cuc: number;
    cup: number;
    cve: number;
    czk: number;
    djf: number;
    dkk: number;
    dop: number;
    dzd: number;
    egp: number;
    ern: number;
    etb: number;
    eur: number;
    fjd: number;
    fkp: number;
    gbp: number;
    gel: number;
    ghs: number;
    gip: number;
    gmd: number;
    gnf: number;
    gtq: number;
    gyd: number;
    hkd: number;
    hnl: number;
    hrk: number;
    htg: number;
    huf: number;
    idr: number;
    ils: number;
    inr: number;
    iqd: number;
    irr: number;
    isk: number;
    jmd: number;
    jod: number;
    jpy: number;
    kes: number;
    kgs: number;
    khr: number;
    kmf: number;
    kpw: number;
    krw: number;
    kwd: number;
    kyd: number;
    kzt: number;
    lak: number;
    lbp: number;
    lkr: number;
    lrd: number;
    lsl: number;
    ltl: number;
    lvl: number;
    lyd: number;
    mad: number;
    mdl: number;
    mga: number;
    mkd: number;
    mmk: number;
    mnt: number;
    mop: number;
    mro: number;
    mur: number;
    mvr: number;
    mwk: number;
    mxn: number;
    mxv: number;
    myr: number;
    mzn: number;
    nad: number;
    ngn: number;
    nio: number;
    nok: number;
    npr: number;
    nzd: number;
    omr: number;
    pab: number;
    pen: number;
    pgk: number;
    php: number;
    pkr: number;
    pln: number;
    pyg: number;
    qar: number;
    ron: number;
    rsd: number;
    rub: number;
    rwf: number;
    sar: number;
    sbd: number;
    scr: number;
    sdg: number;
    sek: number;
    sgd: number;
    shp: number;
    sll: number;
    sos: number;
    srd: number;
    ssp: number;
    std: number;
    svc: number;
    syp: number;
    szl: number;
    thb: number;
    tjs: number;
    tmt: number;
    tnd: number;
    top: number;
    try: number;
    ttd: number;
    twd: number;
    tzs: number;
    uah: number;
    ugx: number;
    usd: number;
    usn: number;
    uss: number;
    uyi: number;
    uyu: number;
    uzs: number;
    vef: number;
    vnd: number;
    vuv: number;
    wst: number;
    xaf: number;
    xag: number;
    xau: number;
    xba: number;
    xbb: number;
    xbc: number;
    xbd: number;
    xcd: number;
    xdr: number;
    xfu: number;
    xof: number;
    xpd: number;
    xpf: number;
    xpt: number;
    xsu: number;
    xts: number;
    xua: number;
    yer: number;
    zar: number;
    zmw: number;
    zwl: number;
};

// ===== output/utils/PriceUtils.d.ts =====
$1export declare function formatPrice(price: {
    amount: number;
    currency: string;
}, locale?: string): string;
$1export declare const _default: {
    formatPrice: typeof formatPrice;
};
export _default;

// ===== output/utils/assertUnreachable.d.ts =====
/**
 * Assets x is statically unreachable at build-time,
 * and throws at runtime if data is dynamic.
 */
export function assertUnreachable(_x: never, runtimeError: Error): never;

// ===== output/utils/commandFactory.d.ts =====
export declare function commandFactory<Args extends any, Response extends zod.ZodTypeAny>(sendCommand: TSendCommand, cmd: Exclude<Commands, Commands.SUBSCRIBE | Commands.UNSUBSCRIBE>, response: zod.ZodTypeAny, transferTransform?: (args: Args) => Transferable[] | undefined): (args: Args) => Promise<zod.infer<Response>>;
type InferArgs<T extends Command> = zod.infer<(typeof Schemas)[T]['request']>;
type InferResponse<T extends Command> = zod.infer<(typeof Schemas)[T]['response']>;
export declare function schemaCommandFactory<T extends Command, TArgs = InferArgs<T>>(cmd: T, transferTransform?: (args: TArgs) => Transferable[] | undefined): (sendCommand: TSendCommand) => (args: TArgs) => Promise<InferResponse<T>>;

// ===== output/utils/compatCommandFactory.d.ts =====
/**
 * @args - the primary args to send with the command.
 * @fallbackArgs - the args to try the command with in the case where an old Discord
 *  client doesn't support one of the new args.
 */
export function compatCommandFactory<Args extends any, FallbackArgs extends any, Response extends zod.ZodTypeAny>({ sendCommand, cmd, response, fallbackTransform, transferTransform, }: {
    sendCommand: TSendCommand;
    cmd: Exclude<Commands, Commands.SUBSCRIBE | Commands.UNSUBSCRIBE>;
    response: zod.ZodTypeAny;
    fallbackTransform: (args: Args) => FallbackArgs;
    transferTransform?: (args: Args | FallbackArgs) => Transferable[] | undefined;
}): (args: Args) => Promise<zod.infer<Response>>;

// ===== output/utils/console.d.ts =====
export declare const consoleLevels: readonly ["log", "warn", "debug", "info", "error"];
export type ConsoleLevel = (typeof consoleLevels)[number];
export declare function wrapConsoleMethod(console: any, level: ConsoleLevel, callback: (level: ConsoleLevel, msg: string) => void): void;

// ===== output/utils/getDefaultSdkConfiguration.d.ts =====
export function getDefaultSdkConfiguration(): SdkConfiguration;

// ===== output/utils/patchUrlMappings.d.ts =====
export interface Mapping {
    prefix: string;
    target: string;
}
export interface RemapInput {
    url: URL;
    mappings: Mapping[];
}
interface PatchUrlMappingsConfig {
    patchFetch?: boolean;
    patchWebSocket?: boolean;
    patchXhr?: boolean;
    patchSrcAttributes?: boolean;
}
export declare function patchUrlMappings(mappings: Mapping[], { patchFetch, patchWebSocket, patchXhr, patchSrcAttributes }?: PatchUrlMappingsConfig): void;
export declare function attemptRemap({ url, mappings }: RemapInput): URL;

// ===== output/utils/url.d.ts =====
export interface MatchAndRewriteURLInputs {
    originalURL: URL;
    prefixHost: string;
    prefix: string;
    target: string;
}
/**
 *
 * Attempts to map the actual url (i.e. google.com) to a url path, per the url
 * mappings set up in the embedded application. If the target contains `{foo}`
 * tokens, they will be replace with the values contained in the original URL,
 * via the pattern described in the prefix
 *
 * @returns  null if URL doesn't match prefix, otherwise return rewritten URL
 */
export declare function matchAndRewriteURL({ originalURL, prefix, prefixHost, target }: MatchAndRewriteURLInputs): URL | null;
export declare function absoluteURL(url: string, protocol?: string, host?: string): URL;

// ===== output/utils/zodUtils.d.ts =====
type ValueOf<T> = T[keyof T];
interface UnhandledObject {
    readonly UNHANDLED: -1;
}
/**
 * This is a helper function which coerces an unsupported arg value to the key/value UNHANDLED: -1
 * This is necessary to handle a scenario where a new enum value is added in the Discord Client,
 * so that the sdk will not throw an error when given a (newly) valid enum value.
 *
 * To remove the requirement for consumers of this sdk to import an enum when parsing data,
 * we instead use an object cast as const (readonly). This maintains parity with the previous
 * schema (which used zod.enum), and behaves more like a union type, i.e. 'foo' | 'bar' | -1
 *
 * @param inputObject This object must include the key/value pair UNHANDLED = -1
 */
export declare function zodCoerceUnhandledValue<T extends UnhandledObject>(inputObject: T): zod.ZodEffects<zod.ZodType<ValueOf<T>, zod.ZodTypeDef, ValueOf<T>>, ValueOf<T>, unknown>;
export interface ZodEffectOverlayType<T extends ZodTypeAny> extends zod.ZodEffects<T> {
    overlayType: T;
    innerType(): never;
    _def: never;
}
/**
 * Fallback to the default zod value if parsing fails.
 */
export declare function fallbackToDefault<T extends ZodDefault<ZodTypeAny>>(schema: T): ZodEffectOverlayType<T>;

export interface DiscordEmbeddedSdkGlobalEntry {
  new (clientId: string, configuration?: SdkConfiguration): IDiscordSDK;
}
export declare const DiscordSDK: DiscordEmbeddedSdkGlobalEntry;
