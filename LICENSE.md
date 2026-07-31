# License

This project uses different license terms for different parts of it. Read the
section that applies to the part you're interested in.

---

## 1. Addon Code (MIT License)

Applies to all `.lua`, `.toc`, and `.xml` files in this repository, **except**
the contents of the `Textures/` folder and the third-party libraries in
`libs/` (see sections 2 and 3 below).

```
MIT License

Copyright (c) 2026 XalaMental

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

**In plain terms:** you're free to use, copy, modify, redistribute, or build
your own addon on top of this code — including for commercial purposes — as
long as you keep the copyright notice above intact somewhere in your
copy/fork. That's the only requirement.

---

## 2. Custom Art Assets (All Rights Reserved)

Applies to every file inside the `Textures/` folder (addon icon, compass
arrow art, glow texture, and any other custom artwork bundled with this
addon).

Copyright (c) 2026 XalaMental. All rights reserved.

These assets are **not** covered by the MIT license above. They may not be
copied, redistributed, modified, or reused in another project without
explicit permission from the author. If you fork this addon's code under the
MIT license, you'll need to supply your own art for anything in this
category, or ask first.

---

## 3. Bundled Third-Party Libraries

This addon bundles the following libraries, embedded under their own
original licenses (not the MIT terms above, since this project didn't write
them):

*   **`libs/LibStub/`** — LibStub, released into the public domain by its
    original authors (Kaelten, Cladhaire, ckknight, Mikk, Ammo, Nevcairiel,
    joshborke).
*   **`libs/CallbackHandler/`** — CallbackHandler-1.0, part of Ace3, released
    under the BSD (2-clause) license.

Both are redistributed here exactly as their own licenses permit, unmodified.
See each library's own file header for its full license text.

---

## Summary

| Content | License | Can I fork/reuse it? |
|---|---|---|
| Addon code (`.lua`, `.toc`, `.xml`) | MIT | Yes — just keep the copyright notice |
| Custom art (`Textures/`) | All Rights Reserved | No — ask the author first |
| `libs/LibStub/` | Public Domain | Yes — no restrictions |
| `libs/CallbackHandler/` | BSD (2-clause) | Yes — under BSD's terms |
