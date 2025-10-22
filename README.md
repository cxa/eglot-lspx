# eglot-lspx

Automatically run multiple LSP servers simultaneously with [lspx](https://github.com/thefrontside/lspx) for Eglot. Currently supports `tailwindcss-language-server`, `biome`, and `vscode-eslint-language-server`.

**Important:** The built-in Eglot in Emacs 30 has a bug that prevents the `tailwindcss-language-server` from working. If you use Tailwind CSS, either upgrade Eglot by running `eglot-upgrade-eglot`, or use Emacs 31 or later.

## Install

First, ensure that `lspx`, `tailwindcss-language-server`, `biome`, and `vscode-eslint-language-server` are installed and discoverable by Emacs.

### `use-package`

```elisp
(use-package eglot-lspx
  :vc (:url "https://github.com/cxa/eglot-lspx"))
```

### Manual

Clone this repository, add the `eglot-lspx.el` file (or the package directory) to your Emacs `load-path`, and then load it:

```elisp
(add-to-list 'load-path "/path/to/eglot-lspx")
```

## Note

- To make published diagnostics work, you must use the `lspx` fork at <https://github.com/cxa/lspx>
- Speed up Tailwind CSS completion: <https://github.com/cxa/cape-tailwindcss>
