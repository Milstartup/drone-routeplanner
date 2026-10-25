// Guards the design rule: the planner core knows nothing about the UI or a drone.
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const coreDir = join(process.cwd(), 'src', 'core');
const files = readdirSync(coreDir).filter((f) => f.endsWith('.ts') && !f.endsWith('.test.ts'));

describe('core separation', () => {
  it.each(files)('%s imports only other core files', (file) => {
    const source = readFileSync(join(coreDir, file), 'utf8');
    const imports = [...source.matchAll(/from\s+['"]([^'"]+)['"]/g)].map((m) => m[1]);
    for (const spec of imports) expect(spec.startsWith('./')).toBe(true);
    expect(source).not.toMatch(/\bDJI[A-Z]\w*|dji-sdk|virtualStick/i);
  });
});
