/**
 * converse-domainchat — live messages from bare-domain roster contacts
 *
 * Converse ≤ v14 assumes any message whose sender JID has no '@' is a server
 * announcement ("headline"): `isServerMessage()` in shared/parsers.js routes
 * it away from the chat pipeline, and the headlines handler then refuses to
 * render it because a private chatbox for that JID already exists. Net
 * effect: replies from a XEP-0100 gateway bot you deliberately chat with
 * (cheogram.com — the JMP account-management bot) never appear live; they
 * only show up after a page reload, when the chatbox pulls them from MAM.
 *
 * Upstream fixed this on master after v14 (conversejs/converse.js#1509: a
 * bare-host JID in your roster is someone you asked to talk to, so its
 * declared stanza type wins over the headline guess), but no release carries
 * the fix yet. This plugin backports the behavior: a Strophe handler catches
 * chat/normal messages from bare-domain senders that are in the roster and
 * feeds them to the exported `handleMessageStanza`, the same entry point
 * Converse's own handler uses for ordinary chats. Converse's handler ignores
 * these stanzas (the isServerMessage guard runs in the caller, not in
 * handleMessageStanza), so each message is processed exactly once.
 *
 * Registration mirrors the core chat plugin: handlers go on the connection
 * at `presencesInitialized`, which re-fires on reconnect after Strophe has
 * cleared the previous session's handlers — no duplicate registration.
 *
 * Pairs with blacklisting converse-headlines/-view in index.html: their
 * handler would race this one for the same stanzas, and this deployment is
 * a texting UI with no use for a server-announcements pane. Drop both this
 * plugin and the blacklist once the vendored Converse includes the upstream
 * fix. Verified against Converse.js v14.
 */

const PLUGIN_NAME = 'converse-domainchat';

/**
 * Register the plugin on a Converse.js instance. Called automatically
 * against `window.converse` when this module is loaded via a script tag
 * after the Converse bundle; call it yourself when bundling.
 *
 * @param {object} converse the global Converse.js API object
 */
export function registerDomainChatPlugin(converse) {
    converse.plugins.add(PLUGIN_NAME, {
        dependencies: ['converse-chat', 'converse-roster'],
        initialize() {
            const _converse = this._converse;
            const { api } = _converse;
            const { Strophe } = converse.env;

            /**
             * A stanza takes the chat route when it's a live chat/normal
             * message from a bare-domain JID we have in the roster. MAM
             * results are excluded — history sync already renders those
             * through the chatbox, and double-handling would duplicate.
             *
             * @param {Element} stanza
             * @returns {boolean}
             */
            function wantsChatRoute(stanza) {
                const from = stanza.getAttribute('from');
                if (!from || from.includes('@')) return false;
                const type = stanza.getAttribute('type') ?? 'normal';
                if (type !== 'chat' && type !== 'normal') return false;
                if (stanza.querySelector(`:scope > result[xmlns="${Strophe.NS.MAM}"]`)) {
                    return false;
                }
                const bare = Strophe.getBareJidFromJid(from);
                return !!_converse.state.roster?.get(bare);
            }

            api.listen.on('presencesInitialized', () => {
                api.connection.get().addHandler(
                    (stanza) => {
                        try {
                            if (wantsChatRoute(stanza)) {
                                _converse.exports.handleMessageStanza(stanza);
                            }
                        } catch (e) {
                            // A plugin bug must never take down message
                            // handling for everything else.
                            console.warn(`[${PLUGIN_NAME}] failed to route stanza:`, e);
                        }
                        return true; // keep the handler installed
                    },
                    null,
                    'message'
                );
            });
        },
    });
}

if (typeof window !== 'undefined' && window.converse?.plugins) {
    registerDomainChatPlugin(window.converse);
}

export default registerDomainChatPlugin;
