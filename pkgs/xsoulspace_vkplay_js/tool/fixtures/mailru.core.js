(function (global) {
  global.iframeApi = {
    init: function init(options) { return Promise.resolve(options); },
    getLoginStatus: function getLoginStatus() { return Promise.resolve({ authorized: true, userId: 'stub' }); },
    userInfo: function userInfo() { return Promise.resolve({ id: 'stub', name: 'Stub' }); },
    userProfile: function userProfile() { return Promise.resolve({ id: 'stub', displayName: 'Stub' }); },
    userFriends: function userFriends() { return Promise.resolve([]); },
    userSocialFriends: function userSocialFriends() { return Promise.resolve([]); },
    showInviteBox: function showInviteBox(payload) { return Promise.resolve(payload); },
    postToFeed: function postToFeed(payload) { return Promise.resolve(payload); }
  };
})(globalThis);
