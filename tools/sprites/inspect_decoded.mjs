// Fallback for a stalled Chrome PNG decoder. Uses the skill's unmodified audit
// function and review template, with pixels decoded independently by Pillow.
// Usage: node tools/sprites/inspect_decoded.mjs image.png frames.json output-prefix
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const [image, manifest, output] = process.argv.slice(2);
if (!output) throw new Error('Expected image, manifest and output prefix');
const skill = path.join(os.homedir(), '.local/opt/sprite-animation-skill/scripts/inspect-sheet.mjs');
const { auditPixels } = await import(pathToFileURL(skill));
const python = path.join(os.homedir(), '.local/opt/northgate-venv/bin/python');
const decoded = spawnSync(python, ['-c',
  'from PIL import Image;import sys,struct;im=Image.open(sys.argv[1]).convert("RGBA");sys.stdout.buffer.write(struct.pack("<II",*im.size)+im.tobytes())', image],
  { maxBuffer: 128 * 1024 * 1024 });
if (decoded.status !== 0) throw new Error(decoded.stderr.toString());
const width = decoded.stdout.readUInt32LE(0), height = decoded.stdout.readUInt32LE(4);
const declared = JSON.parse(fs.readFileSync(manifest));
const frames = Array.isArray(declared) ? declared : declared.frames;
const report = auditPixels(decoded.stdout.subarray(8), width, height, frames);
const source = fs.readFileSync(skill, 'utf8');
const template = source.slice(source.indexOf('function htmlReview'), source.indexOf('async function run'));
const htmlReview = vm.runInNewContext(template + ';htmlReview');
const html = htmlReview(path.basename(image), {
  source: 'data:image/png;base64,' + fs.readFileSync(image).toString('base64'), frames,
}, report);
fs.writeFileSync(output + '-audit.json', JSON.stringify(report, null, 2) + '\n');
fs.writeFileSync(output + '-review.html', html);
console.log(JSON.stringify({ decoder: 'Pillow RGBA', inspector: skill, warnings: report.warnings }));
