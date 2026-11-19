// The `fish-pocket` model route: DeepSeek models paid with Fish Pocket credits,
// over OpenAI Chat Completions through the Fish Pocket gateway. It is the third
// way to reach a model, beside the DeepSeek account and the user's own API keys,
// and it shares nothing with either.
//
// In particular it is not a profile in the `llm-pi-ai` settings, where the
// Models page keeps the user's own providers: a profile written there from the
// --patch overlay overrides that whole section, so the user's providers vanish
// and every write to it is refused. So this entry runs pi-ai's request code on
// its own, with a fixed profile, and keeps out of what `llm-pi-ai` owns: no
// settings form, no entry in the configurable-provider directory, no model
// discovery, no pi-ai sign-in flows. The stock `llm-pi-ai` entry still does all
// of those for the user's providers.
//
// The app passes the API origin as FISH_POCKET_API_URL and stores the runtime
// key after sign-in; without the key the route offers no models (and without the
// URL it points nowhere). The gateway is not api.deepseek.com, so pi-ai cannot
// detect DeepSeek's dialect: thinking.type, reasoning_content replay and
// max_tokens are set here.
import * as PiAi from '@deepseek-ai/dsh-llm-pi-ai';

export const name = 'fish-pocket';
export const inject = ['llm'];

export const ROUTE = 'fish-pocket';
export const KEY_REF = 'FISH_POCKET_RUNTIME_KEY';

/** The route's pi-ai profile for the gateway at `origin` (FISH_POCKET_API_URL). */
export function profile(origin = process.env.FISH_POCKET_API_URL) {
  return {
    displayName: 'Fish Pocket',
    apiKeyEnv: KEY_REF,
    api: 'openai-completions',
    baseURL: `${(origin || 'https://fish-pocket.invalid').replace(/\/+$/, '')}/v1`,
    compat: {
      thinkingFormat: 'deepseek',
      maxTokensField: 'max_tokens',
      requiresReasoningContentOnAssistantMessages: true,
      supportsStore: false,
      supportsDeveloperRole: false,
    },
    models: [{
      id: 'deepseek-flash',
      name: 'DeepSeek-V4.1-Flash',
      contextWindow: 1048576,
      maxTokens: 393216,
      input: ['text', 'image'],
      reasoningEfforts: { off: 'off', high: 'high' },
    }],
  };
}

/**
 * The part of `ctx` pi-ai's `apply` may use here: the route's adapter goes to the
 * real LLM registry, credentials and request hooks are read as usual, and the
 * things that belong to the `llm-pi-ai` entry are dropped. The profile is fixed,
 * so there is no config to watch either.
 */
function routeOnly(ctx) {
  return {
    fiber: ctx.fiber,
    logger: ctx.logger,
    get: (service) => ctx.get(service),
    waterfall: (...args) => ctx.waterfall(...args),
    inject() {},
    on: () => () => {},
    llm: {
      registerAdapter: (routes, adapter) => ctx.llm.registerAdapter(routes, adapter),
      registerConfigurableProviders: () => ({ replace() {}, dispose() {} }),
      registerModelDiscovery: () => () => {},
    },
  };
}

export function apply(ctx) {
  PiAi.apply(routeOnly(ctx), PiAi.Config({ providers: { [ROUTE]: profile() } }));
}
