/**
 * converse-tel — phone numbers in the Converse.js add-contact form
 *
 * Lets you type a phone number ("(615) 555-1212") into Converse's add-contact
 * modal and have it translated to the correct gateway JID before submission.
 *
 * Provider-agnostic by design: translation uses the XEP-0100 address lookup
 * protocol (`jabber:iq:gateway`) — the client asks a gateway "what JID does
 * this phone number map to?" and uses whatever it answers. No gateway domain
 * is hardcoded; candidates come from the `tel_gateways` setting, or failing
 * that, from domain-only JIDs in your roster (a gateway subscription like
 * `cheogram.com` appears in the roster as a bare domain). Swap SMS providers,
 * or self-host a gateway, and this plugin needs no changes.
 *
 * Converse has no official hook for the add-contact flow, so this patches
 * `addContactFromForm` on the `converse-add-contact-modal` custom element's
 * prototype: phone-shaped input is translated and written back into the form,
 * then the original handler runs unchanged. Anything that isn't phone-shaped
 * (a real JID, a bare username) bypasses the plugin entirely. Verified
 * against Converse.js v14.
 *
 * https://github.com/cwage/converse-tel — MIT license.
 */

const PLUGIN_NAME = 'converse-tel';
const NS_GATEWAY = 'jabber:iq:gateway';

/**
 * A string is "phone-shaped" when it has no '@' and, once separators
 * ( ) - . and spaces are stripped, is 7-15 digits with an optional leading +.
 * A valid JID never matches; a phone number in any common formatting does.
 *
 * @param {string} input
 * @returns {boolean}
 */
export function isPhoneLike(input) {
    if (!input || input.includes('@')) return false;
    const digits = input.replace(/[\s().-]/g, '');
    return /^\+?\d{7,15}$/.test(digits);
}

/**
 * Register the plugin on a Converse.js instance. Called automatically against
 * `window.converse` when this module is loaded via a script tag after the
 * Converse bundle; call it yourself when bundling.
 *
 * @param {object} converse the global Converse.js API object
 */
export function registerTelPlugin(converse) {
    converse.plugins.add(PLUGIN_NAME, {
        initialize() {
            const _converse = this._converse;
            const { api } = _converse;
            const { $iq } = converse.env;

            api.settings.extend({
                // Gateways to ask, in order. Empty means auto-discover from
                // the roster (domain-only JIDs).
                tel_gateways: [],
                tel_debug: false,
            });

            const debug = (...args) =>
                api.settings.get('tel_debug') && console.debug(`[${PLUGIN_NAME}]`, ...args);

            // The first gateway that successfully answers is remembered and
            // asked first next time.
            let known_gateway = null;

            function candidateGateways() {
                const configured = api.settings.get('tel_gateways');
                const candidates = configured?.length
                    ? [...configured]
                    : (_converse.state?.roster?.map((m) => m.get('jid')) || []).filter(
                          (jid) => jid && !jid.includes('@')
                      );
                if (known_gateway && candidates.includes(known_gateway)) {
                    candidates.splice(candidates.indexOf(known_gateway), 1);
                    candidates.unshift(known_gateway);
                }
                return candidates;
            }

            /**
             * XEP-0100 §6: <iq type="set"><query xmlns="jabber:iq:gateway">
             * <prompt>NUMBER</prompt></query></iq> → <jid>…</jid>. The number
             * is sent as typed — normalizing input is the gateway's job (the
             * XEP's own example prompt is "(415) 555-1212"). Legacy gateways
             * answer with <prompt> instead of <jid>, so accept both.
             *
             * @param {string} gateway
             * @param {string} number
             * @returns {Promise<string>} the translated JID
             */
            async function translate(gateway, number) {
                const iq = $iq({ type: 'set', to: gateway })
                    .c('query', { xmlns: NS_GATEWAY })
                    .c('prompt')
                    .t(number);
                const result = await api.sendIQ(iq);
                const jid =
                    result?.querySelector('jid')?.textContent?.trim() ||
                    result?.querySelector('prompt')?.textContent?.trim();
                if (!jid || !jid.includes('@')) {
                    throw new Error(`gateway ${gateway} returned no usable JID`);
                }
                return jid;
            }

            customElements.whenDefined('converse-add-contact-modal').then(() => {
                const Modal = customElements.get('converse-add-contact-modal');
                const original = Modal?.prototype?.addContactFromForm;

                // Bail rather than patch if the method isn't where we expect —
                // a future Converse refactor, or another plugin patching first,
                // would otherwise leave us calling undefined and breaking the
                // very form this is supposed to improve.
                if (typeof original !== 'function') {
                    console.warn(
                        `[${PLUGIN_NAME}] addContactFromForm not found on converse-add-contact-modal; ` +
                            'leaving add-contact untouched.'
                    );
                    return;
                }

                Modal.prototype.addContactFromForm = async function (ev) {
                    ev.preventDefault();
                    try {
                        // xhr_user_search_url repurposes the jid field as
                        // "Name <jid>" — don't second-guess that mode.
                        if (!api.settings.get('xhr_user_search_url')) {
                            const input = /** @type {HTMLInputElement} */ (
                                /** @type {HTMLFormElement} */ (ev.target)?.querySelector('input[name="jid"]')
                            );
                            const raw = (input?.value || '').trim();
                            if (input && isPhoneLike(raw)) {
                                const gateways = candidateGateways();
                                if (!gateways.length) {
                                    this.alert(
                                        'No gateway available to look up phone numbers. ' +
                                            'Set tel_gateways or add a gateway to your roster.',
                                        'danger',
                                        false
                                    );
                                    return;
                                }
                                let jid = null;
                                for (const gateway of gateways) {
                                    try {
                                        jid = await translate(gateway, raw);
                                        known_gateway = gateway;
                                        debug(`${raw} → ${jid} (via ${gateway})`);
                                        break;
                                    } catch (e) {
                                        debug(`lookup failed via ${gateway}:`, e);
                                    }
                                }
                                if (!jid) {
                                    this.alert(
                                        `Could not resolve "${raw}" to an address ` +
                                            `(asked: ${gateways.join(', ')}).`,
                                        'danger',
                                        false
                                    );
                                    return;
                                }
                                input.value = jid;
                            }
                        }
                    } catch (e) {
                        // A plugin bug must never make add-contact unusable —
                        // fall through and let Converse handle the raw input.
                        console.warn(`[${PLUGIN_NAME}] failed, submitting input as typed:`, e);
                    }
                    return original.call(this, ev);
                };
            });
        },
    });
}

if (typeof window !== 'undefined' && window.converse?.plugins) {
    registerTelPlugin(window.converse);
}

export default registerTelPlugin;
