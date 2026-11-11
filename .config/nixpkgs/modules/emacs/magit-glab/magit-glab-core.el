;;; magit-glab-core.el --- What magit-glab's buffers share -*- lexical-binding: t -*-

;; Author: Tore Aadland
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (magit "4.0"))
;; Keywords: vc, tools

;;; Commentary:
;; Faces, section classes, how a merge request is summed up on one line,
;; how a thread is drawn, and how a command finds the merge request it is
;; about (`magit-glab-current-key'): the one at point, the buffer's, the
;; one of the commit at point or of HEAD, or one read in the minibuffer.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'parse-time)
(require 'magit)
(require 'magit-glab-api)
(require 'magit-glab-data)

;;;; Options and faces

(defcustom magit-glab-fontify-markdown t
  "Whether comments and descriptions are fontified as markdown."
  :group 'magit-glab
  :type 'boolean)

(defcustom magit-glab-bot-users '("GitLabDuo")
  "Users whose comments are hidden unless `magit-glab-show-bots' is on."
  :group 'magit-glab
  :type '(repeat string))

(defcustom magit-glab-show-bots t
  "Whether comments by `magit-glab-bot-users' are shown."
  :group 'magit-glab
  :type 'boolean)

(defface magit-glab-author '((t :inherit magit-log-author))
  "Face of an author's name."
  :group 'magit-glab)

(defface magit-glab-mine '((t :inherit magit-branch-local))
  "Face of the current user's name, on their own comments."
  :group 'magit-glab)

(defface magit-glab-new '((t :inherit warning :weight bold))
  "Face of what is new since the merge request was last opened."
  :group 'magit-glab)

(defface magit-glab-open '((t :inherit warning))
  "Face of unresolved threads."
  :group 'magit-glab)

(defface magit-glab-resolved '((t :inherit shadow))
  "Face of resolved threads."
  :group 'magit-glab)

(defface magit-glab-draft '((t :inherit font-lock-warning-face :slant italic))
  "Face of drafts: draft merge requests and unpublished comments."
  :group 'magit-glab)

(defface magit-glab-good '((t :inherit success))
  "Face of an approval or a passing pipeline."
  :group 'magit-glab)

(defface magit-glab-bad '((t :inherit error))
  "Face of a failed pipeline or a merge conflict."
  :group 'magit-glab)

(defface magit-glab-thread '((t :inherit magit-diff-context-highlight :extend t))
  "Face of a thread shown inside a diff."
  :group 'magit-glab)

(defface magit-glab-thread-border '((t :inherit magit-glab-open))
  "Face of the border of an unresolved thread shown inside a diff."
  :group 'magit-glab)

;;;; Section classes

(defclass magit-glab-mr-section (magit-section)
  ((keymap :initform 'magit-glab-mr-section-map))
  "A merge request; its value is the key, (PROJECT . IID).")

(defclass magit-glab-thread-section (magit-section)
  ((keymap :initform 'magit-glab-thread-section-map))
  "A discussion; its value is the discussion id.")

(defclass magit-glab-note-section (magit-section)
  ((keymap :initform 'magit-glab-thread-section-map))
  "A note; its value is (DISCUSSION-ID . NOTE-ID).")

(defclass magit-glab-draft-section (magit-section)
  ((keymap :initform 'magit-glab-thread-section-map))
  "An unpublished note; its value is the draft's id.")

(defclass magit-glab-patchset-section (magit-section)
  ((keymap :initform 'magit-glab-patchset-section-map))
  "A patchset; its value is the patchset number.")

(defclass magit-glab-todo-section (magit-section)
  ((keymap :initform 'magit-glab-mr-section-map))
  "A to-do; its value is the merge request key, the to-do id is in
the text property `magit-glab-todo'.")

;; The keymaps are filled in by the libraries whose commands they bind.
(defvar-keymap magit-glab-mr-section-map
  :doc "Keys on a merge request line, also in Magit's own buffers.")

(defvar-keymap magit-glab-thread-section-map
  :doc "Keys on a thread or a note.")

(defvar-keymap magit-glab-patchset-section-map
  :doc "Keys on a patchset.")

;;;; The merge request of a buffer

(defvar-local magit-glab-buffer-key nil
  "The key of the merge request this buffer is about, if any.")
(put 'magit-glab-buffer-key 'permanent-local t)

(defun magit-glab--section-key ()
  "Return the merge request key of the section at point or a parent."
  (let ((section (magit-current-section)))
    (while (and section
                (not (cl-typep section '(or magit-glab-mr-section
                                            magit-glab-todo-section))))
      (setq section (oref section parent)))
    (and section (oref section value))))

(defun magit-glab--commit-key (rev)
  "Return the key of the cached merge request of commit REV, or nil."
  (when-let* ((project (magit-glab-project))
              (mr (magit-glab-mr-for-change-id project (magit-glab-change-id rev))))
    (magit-glab-mr-key mr)))

(defun magit-glab--worktree-key ()
  "Return the key of the merge request this worktree was made for, or nil."
  (when-let* ((top (magit-toplevel))
              ((string-match "[/-]mr-\\([0-9]+\\)/\\'" top))
              (project (magit-glab-project)))
    (cons project (string-to-number (match-string 1 top)))))

(defun magit-glab-read-key (&optional prompt)
  "Read a merge request in the minibuffer; return its key.
Offer the cached ones; a number is a merge request of this repository's
project."
  (let* ((candidates
          (let (list)
            (maphash (lambda (key mr)
                       (when (equal (magit-glab-mr-state mr) "opened")
                         (push (cons (format "!%d %s  (%s)" (cdr key)
                                             (magit-glab-mr-title mr) (car key))
                                     key)
                               list)))
                     magit-glab--mrs)
            (sort list :key #'car)))
         (answer (completing-read (or prompt "Merge request (! or number): ")
                                  candidates)))
    (or (cdr (assoc answer candidates))
        (and (string-match "\\`!?\\([0-9]+\\)\\'" answer)
             (cons (or (magit-glab-project)
                       (read-string "GitLab project (group/name): "))
                   (string-to-number (match-string 1 answer))))
        (user-error "Not a merge request: %s" answer))))

(defun magit-glab-current-key (&optional no-ask)
  "Return the key of the merge request a command is about.
That is the one at point, the buffer's, that of the commit at point,
of the worktree, or of HEAD.  Otherwise read one, unless NO-ASK."
  (or (magit-glab--section-key)
      magit-glab-buffer-key
      (and (derived-mode-p 'magit-mode)
           (or (when-let* ((commit (magit-section-value-if 'commit)))
                 (magit-glab--commit-key commit))
               (magit-glab--worktree-key)
               (magit-glab--commit-key "HEAD")))
      (unless no-ask
        (magit-glab-read-key))))

;;;; One line per merge request

(defun magit-glab-age (time)
  "Return how long ago TIME, an ISO 8601 string, was: \"5m\", \"2d\"."
  (if (not time)
      ""
    (let ((seconds (float-time (time-subtract nil (parse-iso8601-time-string time)))))
      (cond ((< seconds 60) "now")
            ((< seconds 3600) (format "%dm" (/ seconds 60)))
            ((< seconds 86400) (format "%dh" (/ seconds 3600)))
            ((< seconds (* 60 86400)) (format "%dd" (/ seconds 86400)))
            ((format "%dmo" (/ seconds (* 30 86400))))))))

(defun magit-glab--approvals (mr)
  "Return MR's approvals as \"1/2\", in the success face once approved."
  (let* ((given (length (magit-glab-mr-approved-by mr)))
         (needed (+ given (or (magit-glab-mr-approvals-left mr) 0))))
    (propertize (format "%d/%d" given needed)
                'face (if (magit-glab-mr-approved mr) 'magit-glab-good 'shadow)
                'help-echo (format "Approved by: %s"
                                   (string-join (magit-glab-mr-approved-by mr) ", ")))))

(defun magit-glab--pipeline (mr)
  "Return MR's pipeline status as a short string."
  (let ((status (magit-glab-mr-pipeline-status mr)))
    (pcase status
      ('nil (propertize "ci -" 'face 'shadow))
      ("success" (propertize "ci ok" 'face 'magit-glab-good))
      ((or "failed" "canceled") (propertize (concat "ci " status) 'face 'magit-glab-bad))
      (_ (propertize (concat "ci " status) 'face 'magit-glab-open)))))

(defconst magit-glab--merge-problems
  '(("conflict" . "conflict") ("need_rebase" . "needs rebase")
    ("blocked_status" . "blocked") ("requested_changes" . "changes requested")
    ("ci_must_pass" . "ci must pass") ("mergeable" . "ready to merge"))
  "Merge statuses worth showing, and what to call them.")

(defconst magit-glab--silent-statuses
  '("mergeable" "need_rebase" "blocked_status" "unchecked" "checking"
    "approvals_syncing" "preparing"
    ;; Said by `magit-glab-landing-problem' from the fields themselves:
    "not_open" "draft_status" "not_approved" "ci_must_pass" "ci_still_running"
    "discussions_not_resolved" "conflict" "requested_changes")
  "Merge statuses that add nothing to what the fields say.
GitLab says \"blocked\" of every merge request above the bottom of a
stack, until those below land -- the submit bot lands them together.
It says \"unchecked\" until something asks it to work the status out.
And GitLab and the bot rebase what they land, so a needed rebase does
not stop them.")

(defun magit-glab--merge-status (mr)
  "Return MR's merge status if worth showing, else nil.
A stacked merge request that is ready is \"ready to submit\": GitLab
calls it ready to merge, but its Merge button would merge it into the
branch below, not the main branch.  Statuses that say no more than the
approvals, pipeline and threads columns are left out."
  (let* ((status (magit-glab-mr-merge-status mr))
         (name (cond ((not (equal (magit-glab-mr-state mr) "opened")) nil)
                     ((not (magit-glab-landing-problem mr))
                      (propertize (if (magit-glab-mr-stacked-p mr) "ready to submit" "ready to merge")
                                  'face 'magit-glab-good))
                     ((and status (not (member status magit-glab--silent-statuses)))
                      (propertize (or (cdr (assoc status magit-glab--merge-problems))
                                      (string-replace "_" " " status))
                                  'face 'magit-glab-bad))
                     ((magit-glab-mr-conflicts mr)
                      (propertize "conflict" 'face 'magit-glab-bad))))
         (labelled (and (magit-glab-mr-submit-p mr)
                        (propertize (concat "label " magit-glab-submit-label)
                                    'face 'magit-glab-new)))
         (parts (delq nil (list name labelled))))
    (and parts (string-join parts ", "))))

(defun magit-glab-landing-problem (mr)
  "Return why MR cannot land now, as a few words, or nil if it can.
What the Merge button would need: approvals (code owners' too), a passed
build, no open threads or requested changes, and no conflict.  From
those fields, not GitLab's merge status alone, which says \"blocked\" of
a merge request higher in a stack and \"unchecked\" of many."
  (let* ((status (magit-glab-mr-merge-status mr))
         (pipeline (magit-glab-mr-pipeline-status mr))
         (problems
          (if (not (equal (magit-glab-mr-state mr) "opened"))
              (list (magit-glab-mr-state mr))
            (delq nil
                  (list (and (magit-glab-mr-draft mr) "draft")
                        (and (not (magit-glab-mr-approved mr)) "not approved")
                        (and (not (equal pipeline "success"))
                             (concat "ci " (or pipeline "none")))
                        (and (or (magit-glab-mr-threads-blocking mr)
                                 (> (magit-glab-mr-open-threads mr) 0))
                             "open threads")
                        (and (seq-some (lambda (reviewer)
                                         (equal (plist-get reviewer :state) "requested_changes"))
                                       (magit-glab-mr-reviewers mr))
                             "changes requested")
                        (and (magit-glab-mr-conflicts mr) "conflict")
                        (and status (not (member status magit-glab--silent-statuses))
                             (or (cdr (assoc status magit-glab--merge-problems))
                                 (string-replace "_" " " status))))))))
    (and problems (string-join problems ", "))))

(defun magit-glab-chain-string (chain)
  "Return the merge requests of CHAIN as \"!1 !2 !3\"."
  (mapconcat (lambda (mr) (format "!%d" (magit-glab-mr-iid mr))) chain " "))

(defun magit-glab-landing-string (mr)
  "Return how MR lands, for its buffer's header, or nil if it is not open."
  (when (equal (magit-glab-mr-state mr) "opened")
    (let* ((chain (magit-glab-mr-chain mr))
           (problems (delq nil (mapcar (lambda (m)
                                         (when-let* ((problem (magit-glab-landing-problem m)))
                                           (format "!%d %s" (magit-glab-mr-iid m) problem)))
                                       chain)))
           (when-ready (if problems
                           (propertize (concat ", once ready: " (string-join problems ", "))
                                       'face 'magit-glab-bad)
                         "")))
      (if (not (magit-glab-mr-stacked-p mr))
          (concat (format "M merges it into %s" (magit-glab-mr-target-branch mr)) when-ready)
        (concat (format "M labels it %s, and the bot lands %s%s"
                        magit-glab-submit-label (magit-glab-chain-string chain)
                        (if (magit-glab-mr-stacked-p (car chain)) " and those below" ""))
                when-ready "\n" (make-string 11 ?\s)
                (propertize (format "Not GitLab's Merge button: it would merge into %s"
                                    (truncate-string-to-width
                                     (magit-glab-mr-target-branch mr) 20 nil nil "..."))
                            'face 'shadow))))))

(defun magit-glab-format-mr (mr &optional show-author)
  "Return a line summing up MR.  With SHOW-AUTHOR, say who wrote it."
  (let* ((open (magit-glab-mr-open-threads mr))
         (new (magit-glab-new-notes-count mr))
         (title (magit-glab-mr-title mr)))
    (concat
     (propertize (format "%-5s" (format "!%d" (magit-glab-mr-iid mr))) 'face 'magit-hash)
     " " (string-pad (magit-glab--approvals mr) 5)
     " " (string-pad (magit-glab--pipeline mr) 9)
     " " (string-pad (if (> open 0)
                         (propertize (format "%d open" open) 'face 'magit-glab-open)
                       "")
                     7)
     " " (if (magit-glab-mr-draft mr) (propertize title 'face 'magit-glab-draft) title)
     (if (and new (> new 0))
         (propertize (format "  %d new" new) 'face 'magit-glab-new)
       "")
     (if-let* ((problem (magit-glab--merge-status mr))) (concat "  " problem) "")
     (if show-author
         (concat "  " (propertize (magit-glab-mr-author mr) 'face 'magit-glab-author))
       "")
     (propertize (concat "  " (magit-glab-age (magit-glab-mr-updated-at mr)))
                 'face 'shadow))))

(defun magit-glab-insert-mr-line (mr &optional show-author indent)
  "Insert a section of MR on one line, INDENT columns in.
With SHOW-AUTHOR, say who wrote it."
  (magit-insert-section (magit-glab-mr-section (magit-glab-mr-key mr))
    (magit-insert-heading
      (concat (make-string (or indent 0) ?\s)
              (magit-glab-format-mr mr show-author)))))

;;;; Text

(defun magit-glab-fontify-markdown (text)
  "Return TEXT fontified as GitLab markdown, if that is enabled."
  (if (not (and magit-glab-fontify-markdown (require 'markdown-mode nil t)))
      text
    (with-current-buffer (get-buffer-create " *magit-glab-markdown*")
      (let ((inhibit-read-only t))
        (unless (derived-mode-p 'gfm-mode)
          (delay-mode-hooks (gfm-mode)))
        (erase-buffer)
        (insert text)
        (font-lock-ensure)
        (buffer-string)))))

(defun magit-glab-adopt-faces (&optional beg end)
  "Give text from BEG to END its `face' as `font-lock-face' too.
Magit section buffers run font-lock, which strips plain `face'
properties; `font-lock-face' survives it.  Text that already has a
`font-lock-face' keeps it."
  (with-silent-modifications
    (let ((pos (or beg (point-min)))
          (end (or end (point-max))))
      (while (< pos end)
        (let ((next (min (next-single-property-change pos 'face nil end)
                         (next-single-property-change pos 'font-lock-face nil end)))
              (face (get-text-property pos 'face)))
          (when (and face (not (get-text-property pos 'font-lock-face)))
            (put-text-property pos next 'font-lock-face face))
          (setq pos next))))))

(defun magit-glab-insert-indented (text indent)
  "Insert TEXT with every line INDENT columns in, ending in a newline."
  (let ((prefix (make-string indent ?\s)))
    (dolist (line (split-string (string-trim-right text) "\n"))
      (insert (if (string-empty-p line) "" prefix) line "\n"))))

(defun magit-glab-first-line (text &optional width)
  "Return TEXT's first non-empty line, truncated to WIDTH."
  (let ((line (or (seq-find (lambda (line) (not (string-blank-p line)))
                            (split-string text "\n"))
                  "")))
    (truncate-string-to-width (string-trim line) (or width 70) nil nil "...")))

(defun magit-glab-author-string (author)
  "Return AUTHOR propertized, as the current user or someone else."
  (propertize author 'face (if (equal author (magit-glab-username))
                               'magit-glab-mine
                             'magit-glab-author)))

;;;; Threads

(defun magit-glab-bot-p (discussion)
  "Return non-nil if DISCUSSION was started by one of `magit-glab-bot-users'."
  (member (magit-glab-note-author (magit-glab-discussion-first discussion))
          magit-glab-bot-users))

(defun magit-glab-visible-discussions (mr)
  "Return MR's discussions that are comments, minding `magit-glab-show-bots'."
  (seq-remove (lambda (discussion)
                (or (magit-glab-discussion-system-p discussion)
                    (and (not magit-glab-show-bots) (magit-glab-bot-p discussion))))
              (magit-glab-mr-discussions mr)))

(defun magit-glab-position-label (position)
  "Return \"file:line\" for the diff POSITION."
  (let ((file (or (plist-get position :new-path) (plist-get position :old-path))))
    (format "%s:%s" (file-name-nondirectory file)
            (or (plist-get position :new-line)
                (format "-%s" (plist-get position :old-line))))))

(defun magit-glab-note-new-p (note seen-note)
  "Return non-nil if NOTE is someone else's and newer than SEEN-NOTE.
SEEN-NOTE is the highest note id seen, or nil if none ever was."
  (and seen-note
       (> (magit-glab-note-id note) seen-note)
       (not (equal (magit-glab-note-author note) (magit-glab-username)))))

(defun magit-glab-discussion-heading (discussion)
  "Return the one-line heading of DISCUSSION."
  (let* ((first (magit-glab-discussion-first discussion))
         (position (magit-glab-discussion-position discussion))
         (replies (1- (length (magit-glab-discussion-notes discussion))))
         (resolved (magit-glab-discussion-resolved discussion)))
    (concat (cond (resolved (propertize "resolved " 'face 'magit-glab-resolved))
                  ((magit-glab-discussion-resolvable discussion)
                   (propertize "open     " 'face 'magit-glab-open)))
            (cond (position
                   (concat (propertize (magit-glab-position-label position) 'face 'magit-filename)
                           "  "))
                  ;; Plain comments can't be resolved; "general" only
                  ;; tells a thread apart from inline ones.
                  ((magit-glab-discussion-resolvable discussion)
                   (concat (propertize "general" 'face 'shadow) "  ")))
            (magit-glab-author-string (magit-glab-note-author first)) ": "
            (magit-glab-first-line (magit-glab-note-body first) 60)
            (if (> replies 0)
                (propertize (format "  +%d" replies) 'face 'shadow)
              ""))))

(defun magit-glab-insert-note (note seen-note &optional indent)
  "Insert a section of NOTE, INDENT columns in.
SEEN-NOTE is the highest note id seen before; newer ones are marked."
  (let ((indent (or indent 2)))
    (magit-insert-section (magit-glab-note-section
                           (cons (magit-glab-note-discussion-id note)
                                 (magit-glab-note-id note)))
      (magit-insert-heading
        (concat (make-string indent ?\s)
                (magit-glab-author-string (magit-glab-note-author note))
                (propertize (concat "  " (magit-glab-age (magit-glab-note-created note)))
                            'face 'shadow)
                (if (magit-glab-note-new-p note seen-note)
                    (propertize "  new" 'face 'magit-glab-new)
                  "")
                (if (and (magit-glab-note-resolved note) (magit-glab-note-resolved-by note))
                    (propertize (format "  resolved by %s" (magit-glab-note-resolved-by note))
                                'face 'magit-glab-resolved)
                  "")))
      (magit-glab-insert-indented
       (magit-glab-fontify-markdown (magit-glab-note-body note)) (+ indent 2)))))

(defun magit-glab-insert-discussion (discussion seen-note &optional hide)
  "Insert a section of DISCUSSION, its notes as child sections.
SEEN-NOTE is passed to `magit-glab-insert-note'.  HIDE collapses it."
  (magit-insert-section (magit-glab-thread-section
                         (magit-glab-discussion-id discussion) hide)
    (magit-insert-heading
      (let ((heading (concat "  " (magit-glab-discussion-heading discussion))))
        (if (and (magit-glab-discussion-resolvable discussion)
                 (not (magit-glab-discussion-resolved discussion)))
            (propertize heading 'magit-glab-open t)
          heading)))
    (dolist (note (magit-glab-discussion-notes discussion))
      (magit-glab-insert-note note seen-note 4))))

(defun magit-glab-discussion-string (discussion)
  "Return DISCUSSION drawn as a block of lines, for showing in a diff."
  (let ((border (propertize "  ┃ " 'face (if (magit-glab-discussion-resolved discussion)
                                            'magit-glab-resolved
                                          'magit-glab-thread-border))))
    (with-temp-buffer
      (dolist (note (magit-glab-discussion-notes discussion))
        (insert border
                (magit-glab-author-string (magit-glab-note-author note))
                (propertize (concat "  " (magit-glab-age (magit-glab-note-created note)))
                            'face 'shadow)
                (if (and (eq note (magit-glab-discussion-first discussion))
                         (magit-glab-discussion-resolved discussion))
                    (propertize "  resolved" 'face 'magit-glab-resolved)
                  "")
                "\n")
        (dolist (line (split-string (string-trim-right
                                     (magit-glab-fontify-markdown
                                      (magit-glab-note-body note)))
                                    "\n"))
          (insert border "  " line "\n")))
      (add-face-text-property (point-min) (point-max) 'magit-glab-thread t)
      (buffer-string))))

;;;; Re-rendering

(defmacro magit-glab-with-rerender (&rest body)
  "Erase this section buffer, run BODY to fill it, and keep point.
Point goes back to the section it was in, or else to its old line."
  (declare (indent 0) (debug t))
  `(let* ((inhibit-read-only t)
          (section (magit-current-section))
          (ident (and section (magit-section-ident section)))
          (line (line-number-at-pos))
          (offset (and section (- (line-number-at-pos)
                                  (line-number-at-pos (oref section start)))))
          (window-start (and (get-buffer-window) (window-start (get-buffer-window)))))
     (erase-buffer)
     (setq magit-root-section nil)
     ;; A buffer left without a root section breaks every later command
     ;; in it, so a failed render leaves one that says what went wrong.
     (condition-case-unless-debug err
         (progn ,@body)
       (error
        (erase-buffer)
        (setq magit-root-section nil)
        (magit-insert-section (magit-glab-error-root)
          (insert (format "magit-glab could not draw this buffer: %s\ng tries again.\n"
                          (error-message-string err))))
        (message "magit-glab: %s" (error-message-string err))))
     (magit-glab-adopt-faces)
     (let ((target (and ident (magit-get-section ident))))
       (if target
           (progn (goto-char (oref target start))
                  (forward-line offset))
         (goto-char (point-min))
         (forward-line (1- line))))
     (when-let* ((window (get-buffer-window)))
       (when window-start
         (set-window-start window (min window-start (point-max)) t)))))

(provide 'magit-glab-core)
;;; magit-glab-core.el ends here
