;;; rustic-popup.el --- Cargo popup -*-lexical-binding: t-*-

;;; Commentary:

;; Provides magit like popup.

;;; Code:

(require 'rustic-compile)

;;; Customization

(defcustom rustic-popup-commands
  '((?b "build"    build)
    (?f "fmt"      fmt)
    (?r "run"      run)
    (?c "clippy"   clippy)
    (?o "outdated" outdated)
    (?e "clean"    clean)
    (?k "check"    check)
    (?t "test"     test)
    (?d "doc"      doc))
  "List of commands that are displayed in the popup.
The first element of each list contains a command's binding."
  :type 'list
  :group 'rustic-popup)

(defface rustic-popup-key-face
  '((t (:foreground "DeepSkyBlue")))
  "Face used for command shortcuts."
  :group 'rustic)

(defface rustic-popup-section-face
  '((t (:foreground "#f74c00")))
  "Face used for popup section description."
  :group 'rustic)

;;; Popup Mode

(defvar rustic-popup-buffer-name "rustic-popup-buffer"
  "Buffer name for rustic popup buffers.")

(defvar rustic-popup-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [remap self-insert-command] 'rustic-popup-invoke-popup-action)
    (define-key map (kbd "g") 'rustic-recompile)
    (define-key map (kbd "RET") 'rustic-popup-default-action)
    (define-key map (kbd "<tab>") 'rustic-popup-default-action)
    (define-key map (kbd "h") 'rustic-popup-cargo-command-help)
    (define-key map (kbd "q") 'kill-buffer-and-window)
    map)
  "Keymap for rustic popup buffers.")

(define-derived-mode rustic-popup-mode fundamental-mode "RusticPopup"
  "Mode for rustic popup buffers."
  (setq truncate-lines t)
  (setq buffer-read-only t)
  (setq-local scroll-margin 0))

(defun rustic-popup-insert-backtrace ()
  "Insert backtrace section."
  (let ((inhibit-read-only t)
        (prop (lambda (s)
                (propertize s 'face 'rustic-popup-section-face))))
    (insert (funcall prop "Backtrace: "))
    (cond
     ((string= rustic-compile-backtrace "0")
      (insert " " (funcall prop "0") " | 1 | full"))
     ((string= rustic-compile-backtrace "1")
      (insert " 0 | " (funcall prop "1") " | full"))
     ((string= rustic-compile-backtrace "full")
      (insert " 0 | 1 | " (funcall prop "full")))))
  (insert "\n\n"))

(defun rustic-popup-insert-contents (buf)
  "Insert popup buffer contents."
  (let ((inhibit-read-only t))
    (with-current-buffer buf
      (erase-buffer)
      (rustic-popup-mode)
      (rustic-popup-insert-backtrace)
      (insert (propertize "Commands: " 'face 'rustic-popup-section-face) "\n")
      (insert " " (propertize "g" 'face 'rustic-popup-key-face)
              "      " "recompile" "   " "\""
              (or compilation-arguments rustic-compile-command)
              "\"" "\n\n")
      (dolist (command rustic-popup-commands)
        (insert "\s")
        (insert (propertize (char-to-string (nth 0 command)) 'face 'rustic-popup-key-face))
        (insert "\s\s\s\s\s\s")
        (insert (nth 1 command))
        (when (and (string= (nth 1 command) "test")
                   (> (length rustic-test-arguments) 0))
          (insert "        " "\"" rustic-test-arguments "\""))
        (insert "\n"))
      (goto-char (point-min)))))

(defun rustic-popup ()
  "Setup popup.
If directory is not in a rust project call `read-directory-name'."
  (interactive)
  (let ((func (lambda ()
                (let ((buf (get-buffer-create rustic-popup-buffer-name))
                      (win (split-window-below))
                      (inhibit-read-only t))
                  (rustic-popup-insert-contents buf)
                  (set-window-buffer win buf)
                  (select-window win)
                  (fit-window-to-buffer)
                  (set-window-text-height win (+ (window-height) 1))))))
    (if (rustic-buffer-workspace t)
        (funcall func)
      (let ((dir (read-directory-name "Rust project:")))
        (let ((default-directory dir))
          (if (rustic-buffer-workspace t)
              (funcall func)
            (message "Not a rust project.")))))))

;;; Interactive

(defun rustic-popup-invoke-popup-action (event)
  "Execute commands which are listed in `rustic-popup-commands'."
  (interactive (list last-command-event))
  (save-excursion
    (let ((char (char-to-string event)))
      (save-match-data
        (goto-char (point-min))
        (when (re-search-forward (concat "\s" char "\s"))
          (goto-char (match-beginning 0)))))
    (let* ((command (cadr (split-string
                           (buffer-substring-no-properties
                            (point) (line-end-position)))))
           (c (intern (concat "rustic-cargo-" command))))
      (if (commandp c)
          (call-interactively c)
        (call-interactively 'rustic-compile (concat "cargo " command))))))

(defun rustic-popup-default-action ()
  "Change backtrace and `compilation-arguments' when executed on
corresponding line."
  (interactive)
  (let ((inhibit-read-only t))
    (save-excursion
      (goto-char (line-beginning-position))
      (cond
       ((looking-at "Backtrace:")
        (cond
         ((string= rustic-compile-backtrace "0")
          (setq rustic-compile-backtrace "1"))
         ((string= rustic-compile-backtrace "1")
          (setq rustic-compile-backtrace "full"))
         ((string= rustic-compile-backtrace "full")
          (setq rustic-compile-backtrace "0")))
        (rustic-popup-insert-contents (current-buffer)))
       ((search-forward-regexp "\srecompile\s" (line-end-position) t)
        (setq compilation-arguments
              (read-string "Compilation arguments: "
                           (or compilation-arguments rustic-compile-command)))
        (rustic-popup-insert-contents (current-buffer)))
       ((search-forward-regexp "\stest" (line-end-position) t)
        (setq rustic-test-arguments
              (read-string "Cargo test arguments: " rustic-test-arguments))
        (rustic-popup-insert-contents (current-buffer)))
       (t
        (message "No default action for line."))))))

;;; Help Popup

(defvar rustic-popup-help-buffer-name "rustic-popup-help-buffer"
  "Buffer name for rustic popup help buffers.")

(defvar rustic-popup-help-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") 'rustic-popup-kill-help-buffer)
    map)
  "Keymap for rustic popup help buffers.")

(define-derived-mode rustic-popup-help-mode fundamental-mode "RusticHelpPopup"
  "Mode for rustic popup help buffers."
  (setq truncate-lines t)
  (setq buffer-read-only t)
  (setq-local scroll-margin 0))

(defun rustic-popup-cargo-command-help ()
  "Display help buffer for cargo command at point."
  (interactive)
  (let (command)
    (save-excursion
      (goto-char (line-beginning-position))
      (setq command (cadr (split-string
                           (buffer-substring-no-properties (line-beginning-position)
                                                           (line-end-position))))))
    (let* ((string (rustic-popup-help-flags command))
           (inhibit-read-only t))
      (if (not (and (> (length command) 0)
                    (> (length (split-string string "\n")) 0)))
          (message "No help information for command at point.")
        (rustic-popup-setup-help-popup string)))))

(defun rustic-popup-help-flags (command)
  "Get flags of COMMAND."
  (let ((string (shell-command-to-string (format "cargo %s -h" command)))
        flags)
    (dolist (s (split-string string "\n"))
      (when (and (not (string-match "^\s+\-h" s))
                 (string-match "^\s+\-" s))
        (setq flags (concat flags s "\n"))))
    flags))

(defun rustic-popup-setup-help-popup (string)
  "Switch to help buffer."
  (let ((len (length (split-string string "\n")))
        (buf (get-buffer-create rustic-popup-help-buffer-name)))
    (switch-to-buffer buf)
    (erase-buffer)
    (rustic-popup-help-mode)
    (insert string)
    (fit-window-to-buffer)
    (set-window-text-height (selected-window) (+ (window-height) 1))
    (goto-char (point-min))))

(defun rustic-popup-kill-help-buffer ()
  "Kill popup help buffer and switch to popup buffer."
  (interactive)
  (switch-to-buffer rustic-popup-buffer-name)
  (fit-window-to-buffer)
  (set-window-text-height (selected-window) (+ (window-height) 1)))

;;; _
(provide 'rustic-popup)
;;; rustic-popup.el ends here
