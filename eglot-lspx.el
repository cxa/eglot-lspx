;;; eglot-lspx.el --- Run multiple LSP servers simultaneously for Eglot with lspx  -*- lexical-binding:t -*-

;; Copyright (C) 2025-present CHEN Xian'an (a.k.a `realazy').

;; Maintainer: CHEN Xian'an <xianan.chen@gmail.com>

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; See <https://www.gnu.org/licenses/> for GNU General Public License.

;;; Commentary:

;; 

;;; Code:

(require 'ht)

(defun eglot-lspx--locate-dominating-file (dir regexp)
  "Locate REGEXP in DIR."
  (locate-dominating-file dir
                          (lambda (parent)
                            (file-expand-wildcards (expand-file-name regexp parent) t t))))

(defun eglot-lspx--tailwindcss-project-p (project-root-dir)
  "Whether PROJECT-ROOT-DIR is a Tailwind CSS project,
 by checking the 'tailwindcss' field existing in packages.json."
  (let ((key 'eglot-lspx--tailwindcss-project-p))
    (pcase (get-text-property 0 key project-root-dir)
      (1 t)
      (0 nil)
      (_ (put-text-property
          0 1 key
          (if-let* (;; Locate the package.json file
                    ;; which may be outside project-root-dir within a monorepo
                    (dominating-dir (eglot-lspx--locate-dominating-file project-root-dir
                                                                        "package.json"))
                    (file (f-join dominating-dir "package.json"))
                    (data (condition-case _err
                              (if (fboundp 'json-parse-file)
                                  (json-parse-file file :object-type 'alist)
                                (json-read-file file))
                            (error nil)))
                    (get (lambda (k a) (when a (alist-get k a)))))
              (cl-loop for field in '(dependencies devDependencies)
                       for deps = (funcall get field data)
                       when (funcall get 'tailwindcss deps) return 1
                       finally return 0)
            0)
          project-root-dir)
         (eglot-lspx--tailwindcss-project-p project-root-dir)))))

(defun eglot-lspx--biome-project-p (project-root-dir)
  "Check whether PROJECT-ROOT-DIR is a Biome project."
  (let ((key 'eglot-lspx--biome-project-p))
    (pcase (get-text-property 0 key project-root-dir)
      (1 t)
      (0 nil)
      (_ (put-text-property
          0 1 key
          (if (eglot-lspx--locate-dominating-file project-root-dir "biome.jsonc?") 1 0)
          project-root-dir)
         (eglot-lspx--biome-project-p project-root-dir)))))

(defun eglot-lspx--find-biome-executable (project-root-dir)
  "Find the `biome` executable in PROJECT-ROOT-DIR,
fall back to the system-installed location if not found."
  (let ((key 'eglot-lspx--find-biome-executable))
    (pcase (get-text-property 0 key project-root-dir)
      ('not-found nil)
      ('nil (put-text-property
             0 1 key
             (or (let* ((dir (eglot-lspx--locate-dominating-file project-root-dir
                                                                 "biome.jsonc?"))
                        (bin (f-join dir "node_modules/@biomejs/biome/bin/biome")))
                   (if (file-executable-p bin) bin (executable-find "biome")))
                 'not-found)
             project-root-dir)
            (eglot-lspx--find-biome-executable project-root-dir))
      (x x))))

(defun eglot-lspx--eslint-project-p (project-root-dir)
  "Check whether PROJECT-ROOT-DIR is an ESLint project."
  (let ((key 'eglot-lspx--eslint-project-p))
    (pcase (get-text-property 0 key project-root-dir)
      (1 t)
      (0 nil)
      (_ (put-text-property
          0 1 key
          (if (eglot-lspx--locate-dominating-file project-root-dir "\\.?eslint.*") 1 0)
          project-root-dir)
         (eglot-lspx--eslint-project-p project-root-dir)))))

(defun eglot-lspx--eslint-server-p (server)
  "Check whether SERVER is running ESLint."
  (seq-some (lambda (item) (string-prefix-p "eslint" item))
            (plist-get (plist-get (eglot--capabilities server) :executeCommandProvider)
                       :commands)))

(defun eglot-lspx/eglot--connect/filter-args (args)
  "Composite arguments for lspx."
  (cl-destructuring-bind (managed-modes project _class contact _language-ids) args
    (when (and contact
               ;; skip reconnection
               (not (keywordp (car contact))))
      (let ((can-inject (and (stringp (car contact))
                             (not (cl-find-if (lambda (x)
                                                (or (eq x :autoport)
                                                    (eq (car-safe x) :autoport)))
                                              contact))))
            (dir (project-root project))
            (is-prog-mode (seq-some (lambda (m) (provided-mode-derived-p m 'prog-mode))
                                    managed-modes))
            (lspx))
        (if (not can-inject)
            (message "Can't use lspx with the contact: %s" contact)

          ;; css modes are also derived from `prog-mode'
          (when (and (eglot-lspx--tailwindcss-project-p dir) is-prog-mode)
            (add-to-list 'lspx "tailwindcss-language-server --stdio"))
          (when (and (eglot-lspx--biome-project-p dir) is-prog-mode)
            (add-to-list 'lspx (concat (eglot-lspx--find-biome-executable dir) " lsp-proxy")))
          (when (and (eglot-lspx--eslint-project-p dir) is-prog-mode)
            (add-to-list 'lspx "vscode-eslint-language-server --stdio"))
          
          (when lspx
            (let* ((initopts (memq :initializationOptions contact))
                   (progargs (if initopts (butlast contact (length initopts)) contact)))
              (add-to-list 'lspx (string-join progargs " "))
              (setq lspx (mapcan (lambda (x) (list "--lsp" x)) lspx))
              (add-to-list 'lspx "lspx")
              (when initopts (setq lspx (append lspx initopts)))
              (setf (nth 3 args) lspx)))))))
  args)

;; Some LSP servers (e.g. Biome) do not follow the specs,
;; ':pattern' is required to extract from within.
(defun eglot-lspx/eglot--glob-parse/filter-args (args)
  (when (plistp (car args))
    (setf (car args) (plist-get (car args) :pattern)))
  args)

;; https://github.com/microsoft/vscode-eslint/blob/main/%24shared/settings.ts#L166
(defun eglot-lspx--eslint-workspace-configuration (orig-resp)
  "Add the required configurations to ORIG for `vscode-eslint`,
which is not a standard LSP server but is tailored to VS Code."
  ;; TODO: make customizations?
  (append (list :validate "probe"
                :packageManager "npm" ;; Seems not relevant.
                :useESLintClass t
                :useRealpaths t
                
                :codeAction (list :disableRuleComment (list :enable t
                                                            :location "separateLine")
                                  :showDocumentation (list :enable t))

                :codeActionOnSave (list :enable t :mode "all")
                :format t
                :quiet :json-false
                :onIgnoredFiles "off"
                :options  (ht)
                :rulesCustomizations []
                :run "onType"
                :problems (list :shortenToSingleLine t)
                :nodePath (executable-find "node")

                :workspaceFolder
                (list :uri (eglot-path-to-uri
                            (project-root (eglot--project (eglot-current-server))))
                      :name (eglot--project-nickname (eglot-current-server)))
                
                ;; required even empty
                :experimental (ht))
          orig-resp))

;; Steal `find-it' from eglot.el
(defun eglot-lspx--find-it (path server)
  "Find butter with PATH in SERVER.
PATH can be an uri or absolute path."
  (when (string-prefix-p "file:" path)
    (setq path (eglot-uri-to-path path)))
  (cl-loop for b in (eglot--managed-buffers server)
           when (with-current-buffer b
                  (equal (car eglot--TextDocumentIdentifier-cache) path))
           return b))

(defvar-local eglot-lspx--diagnostics nil
  "Store diagnostics from different agents.")

(with-eval-after-load 'eglot
  (advice-add 'eglot--connect :filter-args #'eglot-lspx/eglot--connect/filter-args)
  (advice-add 'eglot--glob-parse :filter-args #'eglot-lspx/eglot--glob-parse/filter-args)

  ;; We must provide a complete 'workspace/configuration' configuration
  ;; to 'vscode-eslint', otherwise it will refuse to start.
  (cl-defmethod eglot-handle-request :around
    (server (_method (eql workspace/configuration)) &key items)
    (let ((resps (cl-call-next-method)))
      (if (and (eglot-lspx--eslint-server-p server)
               (seq-some (lambda (item)
                           (and-let* ((uri (plist-get item :scopeUri))
                                      ((eglot-lspx--find-it uri server)))))
                         items))
          (apply #'vector (seq-map #'eglot-lspx--eslint-workspace-configuration resps))
        resps)))

  ;; `textDocument/publishDiagnostics' comes from different agents, we
  ;; need to combine them to avoid overlaps.  To make this work, you
  ;; must use the lspx fork at https://github.com/cxa/lspx
  (cl-defmethod eglot-handle-notification :around
    (server (method (eql textDocument/publishDiagnostics)) &rest keys)
    (if-let* ((lspx-agent (plist-get keys :_lspx_agent))
              (uri (plist-get keys :uri))
              (diagnostics (plist-get keys :diagnostics))
              (buffer (eglot-lspx--find-it uri server)))
        (with-current-buffer buffer
          (setq-local eglot-lspx--diagnostics
                      (plist-put eglot-lspx--diagnostics lspx-agent diagnostics #'string=))
          (funcall #'cl-call-next-method server method
                   :uri uri
                   :diagnostics (apply #'vconcat
                                       (cl-loop for (_agent diagnostics)
                                                on eglot-lspx--diagnostics by #'cddr
                                                collect diagnostics))))
      (cl-call-next-method))))


(provide 'eglot-lspx)
;;; eglot-lspx.el ends here
