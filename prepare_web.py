#!/usr/bin/env python3
"""Idempotent localized, safe-area-aware shell around a fresh Godot export."""

import argparse
import html
import hashlib
import io
import json
import struct
import base64
import os
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
START = '<!-- arrowflow:managed-head:start -->'
END = '<!-- arrowflow:managed-head:end -->'
LOADER_START = '<!-- arrowflow:loader:start -->'
LOADER_END = '<!-- arrowflow:loader:end -->'


def replace_once(source: str, pattern: str, replacement: str, label: str) -> str:
    source, count = re.subn(pattern, replacement, source, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f'Could not find the Godot {label} hook in the export.')
    return source


def patch_godot_loader(source: str) -> str:
    # These hook only Godot's generated status code and tolerate a prior managed pass.
    # Observe slow engine-script transfer before its blocking request starts.
    source = re.sub(r'<script data-arrowflow-startup>.*?</script>\s*', '', source, flags=re.S)
    def early_start(match):
        engine_script = match[1].replace(' onerror="window.ArrowflowLoader?.failure()"', '')
        engine_script = engine_script.replace('<script', '<script onerror="window.ArrowflowLoader?.failure()"', 1)
        return '<script data-arrowflow-startup>window.ArrowflowLoader?.begin();</script>\n' + engine_script + match[3]
    source, count = re.subn(
        r'(<script\b[^>]*\bsrc=(["\'])[^"\']+\2[^>]*>\s*</script>\s*)(<script\b[^>]*>\s*const GODOT_CONFIG)',
        early_start, source, count=1,
    )
    if count != 1:
        raise RuntimeError('Could not find the Godot engine-script startup hook in the export.')
    source = replace_once(
        source,
        r'function setStatusMode\(mode\) \{.*?(?=\n\s*function setStatusNotice)',
        r"""function setStatusMode(mode) {
        if (statusMode === mode || !initializing) {
            return;
        }
        if (mode === 'hidden') {
            // The engine is ready; allow Arrowflow's progress card to finish its fade.
            statusMode = mode;
            const finished = window.ArrowflowLoader?.ready();
            Promise.resolve(finished).then((completed) => {
                if (completed === false || !initializing || statusMode !== 'hidden') return;
                statusOverlay.remove();
                initializing = false;
            });
            return;
        }
        statusOverlay.style.visibility = 'visible';
        // The custom shell owns visible progress and player-facing errors.
        statusProgress.style.display = 'none';
        statusNotice.style.display = 'none';
        statusMode = mode;
    }""",
        'setStatusMode',
    )
    source = replace_once(
        source,
        r'function displayFailureNotice\(err\) \{.*?(?=\n\s*const missing)',
        r"""function displayFailureNotice(err) {
        // Preserve the technical diagnostic while giving players a clear recovery.
        console.error(err);
        statusOverlay.style.visibility = 'visible';
        setStatusNotice(t('loader.error'));
        setStatusMode('notice');
        window.ArrowflowLoader?.failure();
        initializing = false;
    }""",
        'displayFailureNotice',
    )
    source = replace_once(
        source,
        r"setStatusMode\('progress'\);\s*(?:window\.ArrowflowLoader\?\.(?:begin|scriptReady)\(\);\s*)?engine\.startGame\(\{\s*'onProgress': function \(current, total\) \{.*?\n\s*\},\s*\}\)\.then\(\(\) => \{\s*.*?\}, displayFailureNotice\);",
        r"""setStatusMode('progress');
            window.ArrowflowLoader?.scriptReady();
            engine.startGame({
                'onProgress': function (current, total) {
                    // Godot reports bytes when known; unknown totals remain indeterminate.
                    window.ArrowflowLoader?.progress(current, total);
                },
            }).then(() => {
                // A completed transfer still prepares the engine; never fake ready.
                setStatusMode('hidden');
            }, displayFailureNotice);""",
        'onProgress',
    )
    return source


def font_styles(copy: dict, encode=None) -> str:
    """Embed one loader face covering only loader glyphs; runtime fonts stay unchanged."""
    characters = ''.join(str(value) for entries in copy.values() for value in entries.values())
    # The rotation guard also owns a localized message outside the dictionaries.
    # Include non-ASCII source literals so those glyphs survive every rebuild.
    for relative in ('ui/mobile/runtime.js', 'ui/mobile/loader.js'):
        source = (ROOT / relative).read_text()
        source = re.sub(r'/\*.*?\*/', '', source, flags=re.S)
        source = re.sub(r'\\u\{([0-9a-fA-F]+)\}|\\u([0-9a-fA-F]{4})',
                        lambda match: chr(int(match[1] or match[2], 16)), source)
        characters += ''.join(char for char in source if ord(char) > 127)
    wanted = {ord(char) for char in characters if not char.isspace()} | set(range(0x20, 0x7f))
    if encode is None:
        cached = (ROOT / 'ui/web/loader-fonts.css').read_text()
        metadata = json.loads((ROOT / 'ui/web/loader-fonts.json').read_text())
        if hashlib.sha256(cached.encode()).hexdigest() != metadata['sha256']:
            raise RuntimeError('Cached loader font bytes changed; rebuild from pinned loader sources')
        missing = wanted - set(metadata['codepoints'])
        if missing:
            raise RuntimeError('Cached loader fonts lack new characters; rebuild from pinned loader sources: ' + repr(sorted(missing)))
        return cached
    # Maintenance passes the shared encoder for the approved runtime face
    # (scripts/build-game-loader-fonts.py); it verifies source bytes and coverage.
    data = base64.b64encode(encode(wanted)).decode('ascii')
    return '@font-face{font-family:"Noto Sans SC";font-style:normal;font-weight:400 700;font-display:swap;src:url(data:font/woff2;base64,' + data + ') format("woff2")}'


def render_shell(source: str, installable: bool = True, loader_image=None) -> str:
    # Replace an earlier managed head regardless of the title used by that export.
    source = re.sub(
        r'<!-- (?P<brand>[a-z][a-z0-9-]*):managed-head:start -->.*?<!-- (?P=brand):managed-head:end -->',
        '',
        source,
        flags=re.S,
    )
    source = re.sub(r'<div id="rotate-hint".*?</div></div>', '', source, flags=re.S)
    source = re.sub(r'<meta name="viewport"[^>]*>', '', source)
    source = re.sub(r'<a id="sound-lab-link".*?</a>', '', source, flags=re.S)
    source = re.sub(r'<!-- arrowflow:mobile:start -->.*?<!-- arrowflow:mobile:end -->', '', source, flags=re.S)
    source = re.sub(r'<!-- arrowflow:loader:start -->.*?<!-- arrowflow:loader:end -->', '', source, flags=re.S)
    source = source.replace("        document.getElementById('loading-label')?.remove();\n", '')
    dictionaries = {
        locale: json.loads((ROOT / 'localization' / f'{locale}.json').read_text()) for locale in ('en', 'zh_CN')
    }
    ui = {
        locale: {
            key: value
            for key, value in entries.items()
            if key.startswith(('loader.', 'mobile.')) or key in ('app.title', 'app.tagline')
        }
        for locale, entries in dictionaries.items()
    }
    font_css = font_styles(ui)
    mobile_css = (ROOT / 'ui/mobile/runtime.css').read_text()
    mobile_js = (ROOT / 'ui/mobile/runtime.js').read_text()
    loader_css = (ROOT / 'ui/mobile/loader.css').read_text()
    loader_js = (ROOT / 'ui/mobile/loader.js').read_text()
    endpoint = os.environ.get('MANUS_ANALYTICS_ENDPOINT', '').strip().rstrip('/')
    website = os.environ.get('MANUS_ANALYTICS_WEBSITE_ID', '').strip()
    tracker = '<!-- Manus analytics pending provisioning -->'
    if endpoint and website:
        tracker = f'<script defer src="{html.escape(endpoint, quote=True)}/script.js" data-website-id="{html.escape(website, quote=True)}"></script>'
    sharing_path = ROOT / 'game-sharing.json'
    sharing = json.loads(sharing_path.read_text()) if sharing_path.is_file() else {}
    title = str(sharing.get('title') or ui['en']['app.title'])
    description = str(sharing.get('description') or ui['en'].get('app.tagline') or title)
    source = re.sub(r'<title>.*?</title>', lambda _: '<title>' + html.escape(title) + '</title>', source, flags=re.S)
    source = re.sub(r'<meta name="description"[^>]*>', '', source, count=1)
    source = re.sub(r'<meta name="theme-color"[^>]*>', '', source, count=1)
    head = f"""{START}
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="manus-game-loading-screen" content="1">
<meta name="theme-color" content="#f6f5ef">
<meta name="description" content="{html.escape(description, quote=True)}">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="{html.escape(title, quote=True)}">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<link rel="manifest" href="arrowflow.webmanifest">
<!-- Embedded font: Noto Sans SC loader subset (SIL Open Font License 1.1).
License text: assets/template/fonts/NotoSansSC-OFL.txt; the export's Open Source Licenses page lists it.
-->
<style>
{font_css}
html,body {{ margin:0; width:100%; height:100%; overflow:hidden; background:#f6f5ef; font-family:"Nunito","Avenir Next",system-ui,sans-serif; }}
#canvas {{ position:fixed; left:env(safe-area-inset-left); top:env(safe-area-inset-top); width:calc(100% - env(safe-area-inset-left) - env(safe-area-inset-right)) !important; height:calc(100% - env(safe-area-inset-top) - env(safe-area-inset-bottom)) !important; display:block; outline:none; touch-action:none; }}
#status {{ background:#f6f5ef; color:#172b3a; font:40px/1.45 "Nunito","Avenir Next",system-ui,sans-serif; }}
#status-splash {{ max-width:192px; object-fit:contain; }}
{mobile_css}
{loader_css}
</style>
<script>
const ARROWFLOW_COPY={json.dumps(ui, ensure_ascii=False)};
let arrowflowLocale = String((navigator.languages && navigator.languages[0]) || navigator.language || '').toLowerCase().startsWith('zh') ? 'zh_CN' : 'en';
try {{ const saved = localStorage.getItem('arrowflow_locale'); if(saved in ARROWFLOW_COPY) arrowflowLocale=saved; }} catch {{}}
function t(key, placeholders={{}}) {{ let value=ARROWFLOW_COPY[arrowflowLocale][key] ?? ARROWFLOW_COPY.en[key] ?? key; for(const [name,text] of Object.entries(placeholders)) value=value.replaceAll('{{'+name+'}}',String(text)); return value; }}
document.documentElement.lang=arrowflowLocale==='zh_CN'?'zh-CN':'en';
document.title=t('app.title');
window.arrowflowSetLocale = locale => {{
 if (locale in ARROWFLOW_COPY) arrowflowLocale=locale;
 document.title=t('app.title');
 document.documentElement.lang=arrowflowLocale==='zh_CN'?'zh-CN':'en';
 for (const [id,key] of Object.entries({{'portrait-title':'mobile.rotate_title','portrait-body':'mobile.rotate_body','portrait-action':'mobile.enter_portrait'}})) {{
  const node=document.getElementById(id); if(node) node.textContent=t(key);
 }}
 document.getElementById('canvas')?.setAttribute('aria-label',t('app.title'));
 window.ArrowflowLoader?.refresh();
}};
document.addEventListener('DOMContentLoaded',()=>{{
 window.arrowflowSetLocale(arrowflowLocale);
 document.querySelector('#canvas').setAttribute('aria-label',t('app.title'));
}});
{mobile_js}
{loader_js}
</script>
{tracker}
{END}"""
    source = re.sub(r'\s*</head>', '\n</head>', source)
    source = source.replace('</head>', head + '\n</head>', 1)
    source = re.sub(r'[ \t]*<canvas', '<canvas', source)
    guard = '<!-- arrowflow:mobile:start --><section id="portrait-guard" role="dialog" aria-modal="true" aria-labelledby="portrait-title" hidden><div><h1 id="portrait-title"></h1><p id="portrait-body"></p><button id="portrait-action" type="button"></button></div></section><!-- arrowflow:mobile:end -->'
    source = source.replace('<canvas', guard + '\n<canvas', 1)
    loader = f"""{LOADER_START}<section id="arrowflow-loader" role="status" aria-live="polite" aria-atomic="true" hidden><div id="arrowflow-loader-card"><div id="arrowflow-loader-arrows" aria-hidden="true"><span class="arrowflow-loader-arrow" data-arrowflow-direction="up"></span><span class="arrowflow-loader-arrow" data-arrowflow-direction="right"></span><span class="arrowflow-loader-arrow" data-arrowflow-direction="down"></span><span class="arrowflow-loader-arrow" data-arrowflow-direction="left"></span></div><h1 id="arrowflow-loader-message"></h1><p id="arrowflow-loader-detail" hidden></p><progress id="arrowflow-loader-progress" max="100" aria-label="Loading game"></progress><button id="arrowflow-loader-retry" type="button" hidden></button></div></section>{LOADER_END}"""
    source = re.sub(r'\s*(<img\b[^>]*\bid="status-splash"[^>]*>)', r'\n\1', source, count=1)
    source, count = re.subn(
        r'(<img\b[^>]*\bid="status-splash"[^>]*>)', lambda match: loader + '\n' + match.group(1), source, count=1
    )
    if count != 1:
        raise RuntimeError('Could not find the Godot status splash hook in the export.')
    source = source.replace(
        'Your browser does not support the canvas tag.',
        ui['en']['loader.no_canvas'] + ' / ' + ui['zh_CN']['loader.no_canvas'],
    )
    source = source.replace(
        'Your browser does not support JavaScript.', ui['en']['loader.no_js'] + ' / ' + ui['zh_CN']['loader.no_js']
    )
    if '<!-- arrowflow:custom-loading-loop -->' not in source:
        source = patch_godot_loader(source)
    if not installable:
        source = source.replace('<link rel="manifest" href="arrowflow.webmanifest">', '')
    return '\n'.join(line.rstrip() for line in source.splitlines() if line.strip()) + '\n'


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', default='web')
    args = parser.parse_args()
    index = ROOT / args.directory / 'index.html'
    index.write_text(render_shell(index.read_text()))
    sharing = json.loads((ROOT / 'game-sharing.json').read_text())
    icon_relative = sharing.get('assets', {}).get('favicon', 'assets/share/favicon.png')
    icon_path = Path(icon_relative)
    if icon_path.is_absolute() or '..' in icon_path.parts:
        raise RuntimeError('Arrowflow favicon must be a project-relative asset path')
    icon_source = ROOT / icon_path
    if not icon_source.is_file():
        raise RuntimeError('Arrowflow favicon is missing; restore the game-specific sharing asset first')
    icon_bytes = icon_source.read_bytes()
    if len(icon_bytes) < 24 or icon_bytes[:8] != b'\x89PNG\r\n\x1a\n':
        raise RuntimeError('Arrowflow favicon must be a valid PNG')
    icon_width, icon_height = struct.unpack('>II', icon_bytes[16:24])
    icon_name = 'arrowflow-icon.png'
    shutil.copyfile(icon_source, index.parent / icon_name)
    icons = [{'src': icon_name, 'sizes': f'{icon_width}x{icon_height}', 'type': 'image/png'}]
    default_title = str(sharing.get('title') or json.loads((ROOT / 'localization/en.json').read_text())['app.title'])
    (index.parent / 'arrowflow.webmanifest').write_text(
        json.dumps(
            {
                'name': default_title,
                'short_name': default_title,
                'start_url': './',
                'display': 'fullscreen',
                'orientation': 'portrait',
                'background_color': '#f6f5ef',
                'theme_color': '#f6f5ef',
                'icons': icons,
            },
            indent=2,
        )
        + '\n'
    )
    # Clean only the retired generated review route; original audio/source is retained.
    retired = index.parent / 'sfx'
    if retired.is_dir():
        shutil.rmtree(retired)
    print('Prepared Arrowflow Web shell:', index)


if __name__ == '__main__':
    main()
