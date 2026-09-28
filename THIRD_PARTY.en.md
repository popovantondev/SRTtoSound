# Third-party components and notices

English version · [Deutsch](THIRD_PARTY.de.md) · [Русский](THIRD_PARTY.ru.md)

This inventory is specific to SRT to Sound. It is not a license for this project and does not replace terms supplied by third-party authors. The application release candidate does not bundle FFmpeg, Python packages, Silero, or model weights.

## Application and Apple components

The source uses Apple-provided macOS frameworks and command-line facilities, including AppKit, AVFoundation, Swift, and Ruby. These are supplied by Apple/macOS and are not copied into this source export. Their use is governed by Apple's applicable terms.

The project icon assets and scripts are project materials. This repository grants only the limited permissions in [RIGHTS.en.md](RIGHTS.en.md); no project-wide open-source license is granted.

## FFmpeg

The app invokes an executable installed separately by the user. No FFmpeg executable or library is included in the repository or candidate archive. FFmpeg states that most of its code is LGPL 2.1 or later, while enabling optional GPL components changes the applicable license to GPL 2 or later. The license of a particular user-installed build depends on its configuration and included components. See [FFmpeg legal considerations](https://ffmpeg.org/legal.html) and [FFmpeg license details](https://ffmpeg.org/doxygen/trunk/md_LICENSE.html).

## Silero and model weights

The source calls the Silero TTS Python package and expects a locally supplied model file named `v5_5_ru.pt`; neither is bundled. At upstream commit [`639eade`](https://github.com/snakers4/silero-models/tree/639eade0329fd0d99aa15dcfd204239a10c9be7e), the README documents the Russian V5 model as `v5_ru` with speakers `aidar`, `baya`, `kseniya`, `xenia`, and `eugene`, and says that only the separate `v5_cis_base` models use MIT. The installed Silero 0.5.5 loader and the verified artifact use the local filename/loader identifier `v5_5_ru`; the pinned upstream README and model index do not explicitly document that exact alias-to-artifact mapping. The locally tested file had SHA-256 `50081637b602126ee06cb3bc8a744d25651d2da149ee8864b9a379bfdd934437`. That checksum identifies the tested bytes; it does not independently establish who published them or the applicable license.

There is also an upstream license-label discrepancy at that commit: the README badge says “CC BY-NC 4.0” and its license section calls the general terms “CC-NC-BY”, while the actual pinned [`LICENSE` file](https://github.com/snakers4/silero-models/blob/639eade0329fd0d99aa15dcfd204239a10c9be7e/LICENSE) contains the full Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International terms (CC BY-NC-SA 4.0). This project adopts the strictest confirmed usage scope: **personal, non-commercial use only**. Do not use the Silero model for commercial work, and do not redistribute model weights in this project. The exact mapping of the locally tested `v5_5_ru.pt` artifact to the pinned upstream model/license has not been independently confirmed; this notice is a conservative project restriction, not a legal conclusion or a resolution of that discrepancy. Obtain written clarification or permission from the rights holder before relying on broader rights.

References: [pinned Silero README](https://github.com/snakers4/silero-models/blob/639eade0329fd0d99aa15dcfd204239a10c9be7e/README.md), [pinned upstream LICENSE](https://github.com/snakers4/silero-models/blob/639eade0329fd0d99aa15dcfd204239a10c9be7e/LICENSE), [pinned model index](https://github.com/snakers4/silero-models/blob/639eade0329fd0d99aa15dcfd204239a10c9be7e/models.yml), and [official model artifact URL](https://models.silero.ai/models/tts/ru/v5_5_ru.pt).

## Python dependencies

PyTorch, SoundFile, NumPy, and other Python packages are not included. `requirements-silero.txt` records dependency versions, not a complete third-party license grant. Each package retains its own license and notices; users installing the optional environment should review the package metadata for the versions they obtain.

The isolated Python 3.12.14 ARM64 QA environment installed these exact runtime pins. License labels below summarize the installed distributions' `License-Expression`, `License`, classifier, and included license-file metadata where available; they are an inventory aid, not a legal opinion. Dependencies are installed by the user and are not copied into our app or release archive. Some binary wheels, notably NumPy, PyTorch, and setuptools, may contain additional third-party components with their own notices; consult the notices shipped inside the installed package.

| Package | Pinned version | Declared license |
|---|---:|---|
| antlr4-python3-runtime | 4.9.3 | BSD |
| cffi | 2.0.0 | MIT |
| filelock | 3.19.1 | Unlicense |
| fsspec | 2025.10.0 | BSD-3-Clause |
| Jinja2 | 3.1.6 | BSD |
| MarkupSafe | 3.0.3 | BSD-3-Clause |
| mpmath | 1.3.0 | BSD |
| networkx | 3.2.1 | BSD |
| numpy | 2.0.2 | BSD; wheel includes additional licensed components |
| omegaconf | 2.3.1 | BSD |
| pycparser | 2.23 | BSD-3-Clause |
| PyYAML | 6.0.3 | MIT |
| setuptools | 84.0.0 | MIT |
| silero (Python package) | 0.5.5 | MIT metadata; separate model weights have different terms above |
| soundfile | 0.13.1 | BSD-3-Clause |
| sympy | 1.14.0 | BSD |
| torch | 2.8.0 | BSD-3-Clause; inspect wheel notices for bundled components |
| typing_extensions | 4.16.0 | PSF-2.0 |

## Audit scope

This is a source and dependency-path audit for the candidate, not a legal opinion or a full bill of materials for a specific locally installed environment. No third-party model or media asset is authorized for inclusion by this notice.
