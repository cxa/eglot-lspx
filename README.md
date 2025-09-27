# eglot-lspx

Automatically run multiple LSP servers simultaneously with [lspx](https://github.com/thefrontside/lspx) for Eglot. Currently supports `tailwindcss-language-server`, `biome`, and `vscode-eslint-language-server`.

**Important**: The built-in Eglot has a bug that prevents `tailwindcss-language-server` from working. You must install the development version of Eglot from <https://elpa.gnu.org/devel/index.html> if you're working with Tailwind CSS.

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
