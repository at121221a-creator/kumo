// `open` (macOS) and `xdg-open` (Linux) for the execution world: desktop code
// that hands a link to the system browser — a plugin's OAuth sign-in, a CLI's
// "open the docs" — spawns one of these two, and without them the spawn fails
// and the user is left copying a URL by hand. Here they pass the URL to the
// app's `open.url` capability (native/ios-native/caps_open.m), which keeps its
// own scheme allowlist; nothing is decided on this side.
//
// Only URLs: there is no Finder or default-application table to hand a file to.
import { binding, invoke } from '../plugins/ios-native/binding.mjs';

export const OPEN_COMMANDS = ['open', 'xdg-open'];

const URL_WITH_SCHEME = /^[a-z][a-z0-9+.-]*:/i;

/** Available when the app links the native addon (never on a development machine). */
export function openAvailable() {
  return binding() !== null;
}

/**
 * Open the URL operands of one `open` / `xdg-open` command line.
 * @param name - the command as invoked, for messages.
 * @param args - its arguments; options are ignored, every URL operand is opened.
 * @param open - the capability call (injectable for tests).
 * @returns {{ stdout: string, stderr: string, exitCode: number }}
 */
export async function runOpen(name, args, open = (url) => invoke('open', 'url', { url })) {
  const urls = args.filter((arg) => URL_WITH_SCHEME.test(arg));
  if (urls.length === 0) {
    return { stdout: '', stderr: `${name}: only URLs can be opened on iOS (got: ${args.join(' ') || 'nothing'})\n`, exitCode: 1 };
  }
  let stderr = '';
  for (const url of urls) {
    try {
      await open(url);
    } catch (error) {
      stderr += `${name}: ${error?.message ?? error}\n`;
    }
  }
  return { stdout: '', stderr, exitCode: stderr === '' ? 0 : 1 };
}

/** The two commands as just-bash commands. */
export function openShellCommands(defineCommand) {
  return OPEN_COMMANDS.map((name) => defineCommand(name, async (args) => runOpen(name, args)));
}
