import { cpSync, existsSync, mkdirSync, readdirSync, rmSync, statSync } from 'node:fs';
import { basename, extname, join } from 'node:path';

const root = process.cwd();
const outDir = join(root, 'www');

const rootFileExtensions = new Set(['.html', '.js', '.css', '.webmanifest']);
const rootFiles = new Set(['favicon.ico']);
const runtimeDirs = ['assets', 'ai'];
const excludedNames = new Set([
  '.git',
  '.github',
  'android',
  'docs',
  'ios',
  'node_modules',
  'runners',
  'scripts',
  'www'
]);

function copyFileOrDir(from, to) {
  const stat = statSync(from);
  if (stat.isDirectory()) {
    cpSync(from, to, {
      recursive: true,
      filter: source => !excludedNames.has(basename(source))
    });
    return;
  }
  cpSync(from, to);
}

rmSync(outDir, { recursive: true, force: true });
mkdirSync(outDir, { recursive: true });

for (const entry of readdirSync(root)) {
  if (excludedNames.has(entry)) continue;
  const source = join(root, entry);
  const stat = statSync(source);
  if (stat.isDirectory()) {
    if (runtimeDirs.includes(entry)) copyFileOrDir(source, join(outDir, entry));
    continue;
  }

  if (rootFileExtensions.has(extname(entry)) || rootFiles.has(entry)) {
    copyFileOrDir(source, join(outDir, entry));
  }
}

for (const dir of runtimeDirs) {
  const source = join(root, dir);
  const target = join(outDir, dir);
  if (existsSync(source) && !existsSync(target)) copyFileOrDir(source, target);
}

console.log(`Prepared Capacitor web assets in ${outDir}`);
