;;; magit-glab-mr.el --- One buffer per merge request -*- lexical-binding: t -*-

;; Author: Tore Aadland
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (magit "4.0"))
;; Keywords: vc, tools

;;; Commentary:
;; `magit-glab-mr-visit' shows everything about a merge request in one
;; buffer: where it stands, its description, its threads -- open ones
;; first, inline ones by file and line -- your drafts, its patchsets and
;; GitLab's activity log.  Notes newer than the last visit are marked new.
;;
;; RET on a thread goes to its line in the diff; on a patchset, diffs it
;; against the one before.  The thread keys (r reply, R resolve, D done,
;; e edit, k delete) and the rest are listed by `magit-glab-mr-mode'.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'magit)
(require 'magit-glab-core)
(require 'magit-glab-threads)
(require 'magit-glab-compose)
(require 'magit-glab-versions)
(require 'magit-glab-worktree)

(defcustom magit-glab-done-todos-on-visit t
  "Whether visiting a merge request marks its GitLab to-dos done."
  :group 'magit-glab
  :type 'boolean)

(declare-function magit-glab-dispatch "magit-glab")
(declare-function magit-glab-approve "magit-glab")
(declare-function magit-glab-land "magit-glab")
(declare-function magit-glab-browse "magit-glab")
(declare-function magit-glab-copy-url "magit-glab")
(declare-function magit-glab-todos-done "magit-glab")

(defvar-keymap magit-glab-mr-mode-map
  :doc "Keys in a merge request buffer."
  "g"   #'magit-glab-mr-refresh
  "q"   #'quit-window
  "RET" #'magit-glab-visit
  "r"   #'magit-glab-reply
  "c"   #'magit-glab-comment
  "e"   #'magit-glab-edit-note
  "k"   #'magit-glab-delete-note
  "R"   #'magit-glab-toggle-resolved
  "D"   #'magit-glab-done
  "]"   #'magit-glab-next-thread
  "["   #'magit-glab-previous-thread
  "d"   #'magit-glab-mr-diff
  "v"   #'magit-glab-diff-since-seen
  "V"   #'magit-glab-diff-patchsets
  "W"   #'magit-glab-worktree
  "a"   #'magit-glab-approve
  "M"   #'magit-glab-land
  "o"   #'magit-glab-browse
  "w"   #'magit-glab-copy-url
  "s"   #'magit-glab-review-start
  "P"   #'magit-glab-review-publish
  "B"   #'magit-glab-toggle-bots
  "@"   #'magit-glab-dispatch)

(define-derived-mode magit-glab-mr-mode magit-section-mode "GitLab MR"
  "A GitLab merge request: its state, description, threads and patchsets.

\\{magit-glab-mr-mode-map}"
  :interactive nil
  (setq-local revert-buffer-function (lambda (&rest _) (magit-glab-mr-refresh)))
  ;; Comments are paragraphs on one line; wrap them, indented as they are.
  (visual-line-mode)
  (when (fboundp 'visual-wrap-prefix-mode)
    (visual-wrap-prefix-mode)))

(defvar-local magit-glab-mr--seen-note nil
  "The highest note id seen before this visit, so new notes stay marked.")

(defun magit-glab--mr-buffer (key)
  "Return the buffer of merge request KEY, creating it."
  (or (seq-find (lambda (buffer)
                  (and (eq (buffer-local-value 'major-mode buffer) 'magit-glab-mr-mode)
                       (equal (buffer-local-value 'magit-glab-buffer-key buffer) key)))
                (buffer-list))
      (let ((buffer (generate-new-buffer
                     (format "*magit-glab !%d %s*" (cdr key)
                             (file-name-nondirectory (car key))))))
        (with-current-buffer buffer
          (magit-glab-mr-mode)
          (setq magit-glab-buffer-key key)
          (setq default-directory
                (or (magit-glab-project-directory (car key))
                    (if (file-remote-p default-directory)
                        (expand-file-name "~/")
                      default-directory)))
          (setq magit-glab-mr--seen-note (plist-get (magit-glab-seen key) :note))
          (magit-glab-subscribe #'magit-glab--mr-changed))
        buffer)))

;;;###autoload
(defun magit-glab-mr-visit (key)
  "Show merge request KEY in its own buffer."
  (interactive (list (magit-glab-current-key)))
  (let ((buffer (magit-glab--mr-buffer key)))
    (pop-to-buffer-same-window buffer)
    (magit-glab-mr--render)
    (magit-glab-refresh-mr key)
    (when (and magit-glab-done-todos-on-visit (fboundp 'magit-glab-todos-done))
      (magit-glab-todos-done key))))

(defun magit-glab-mr-refresh ()
  "Fetch this merge request again."
  (interactive nil magit-glab-mr-mode)
  ;; The callback runs from a process sentinel, in some other buffer.
  (let ((key magit-glab-buffer-key))
    (message "Fetching !%d..." (cdr key))
    (magit-glab-refresh-mr key (lambda (ok) (when ok (message "Fetching !%d...done" (cdr key)))))))

(defun magit-glab-toggle-bots ()
  "Show or hide comments by `magit-glab-bot-users'."
  (interactive)
  (setq magit-glab-show-bots (not magit-glab-show-bots))
  (message "Comments by %s %s" (string-join magit-glab-bot-users ", ")
           (if magit-glab-show-bots "shown" "hidden"))
  (magit-glab--changed magit-glab-buffer-key))

(defun magit-glab--mr-changed (key)
  "Render this buffer again if KEY is its merge request, or a patch id."
  (when (or (equal key magit-glab-buffer-key)
            (eq (car-safe key) 'patch-id))
    (magit-glab-refresh-soon nil #'magit-glab-mr--render)))

;;;; Rendering

(defun magit-glab--field (name value)
  "Insert a header line: NAME, then VALUE."
  (when (and value (not (equal value "")))
    (insert (propertize (string-pad name 11) 'face 'magit-section-heading) value "\n")))

(defun magit-glab--reviewer-string (reviewer)
  "Return REVIEWER, a plist, with their review state."
  (let ((state (plist-get reviewer :state)))
    (concat (magit-glab-author-string (plist-get reviewer :username))
            (cond ((plist-get reviewer :approved) (propertize " (approved)" 'face 'magit-glab-good))
                  ((equal state "requested_changes")
                   (propertize " (requested changes)" 'face 'magit-glab-bad))
                  ((member state '("reviewed" "review_started"))
                   (propertize (format " (%s)" (string-replace "_" " " state)) 'face 'shadow))
                  ("")))))

(defun magit-glab--sorted-threads (discussions)
  "Return DISCUSSIONS sorted: inline ones by file and line, then general ones."
  (sort (copy-sequence discussions)
        :key (lambda (discussion)
               (let ((position (magit-glab-discussion-position discussion)))
                 (if position
                     (list 0 (or (plist-get position :new-path) "")
                           (or (plist-get position :new-line) (plist-get position :old-line) 0))
                   (list 1 "" 0))))
        :lessp (lambda (a b)
                 (cond ((/= (nth 0 a) (nth 0 b)) (< (nth 0 a) (nth 0 b)))
                       ((not (equal (nth 1 a) (nth 1 b))) (string< (nth 1 a) (nth 1 b)))
                       (t (< (nth 2 a) (nth 2 b)))))))

(defun magit-glab--insert-header (mr)
  "Insert the header lines of MR."
  (let* ((key (magit-glab-mr-key mr))
         (patchsets (magit-glab-mr-patchsets mr))
         (newest (car (last patchsets)))
         (local (and (magit-glab-mr-full-p mr) (magit-glab-local-patchset mr)))
         (drafts (magit-glab-mr-drafts mr)))
    (magit-glab--field "Author" (magit-glab-author-string (magit-glab-mr-author mr)))
    (magit-glab--field "Branch" (format "%s -> %s"
                                        (propertize (magit-glab-mr-source-branch mr)
                                                    'face 'magit-branch-remote)
                                        (propertize (magit-glab-mr-target-branch mr)
                                                    'face 'magit-branch-remote)))
    (magit-glab--field "Status"
                       (string-join (delq nil (list (magit-glab-mr-state mr)
                                                    (and (magit-glab-mr-draft mr)
                                                         (propertize "draft" 'face 'magit-glab-draft))
                                                    (magit-glab--pipeline mr)
                                                    (magit-glab--merge-status mr)))
                                    ", "))
    (magit-glab--field "Land" (magit-glab-landing-string mr))
    (magit-glab--field "Approvals"
                       (concat (magit-glab--approvals mr) "  "
                               (mapconcat #'magit-glab-author-string
                                          (magit-glab-mr-approved-by mr) ", ")))
    (magit-glab--field "Reviewers" (mapconcat #'magit-glab--reviewer-string
                                              (magit-glab-mr-reviewers mr) ", "))
    (magit-glab--field "Patchset"
                       (concat (if newest
                                   (format "PS%d (%s)" (magit-glab-patchset-number newest)
                                           (substring (magit-glab-patchset-head newest) 0 8))
                                 "")
                               (if local
                                   (propertize (format "  local commit %s is newer: push it"
                                                       (substring (magit-glab-patchset-head local) 0 8))
                                               'face 'magit-glab-new)
                                 "")))
    (when (or drafts (magit-glab-reviewing-p key))
      (magit-glab--field "Review"
                         (propertize (format "%s%d draft%s; P publishes"
                                             (if (magit-glab-reviewing-p key)
                                                 "in progress, comments are drafts; " "")
                                             (length drafts) (if (= (length drafts) 1) "" "s"))
                                     'face 'magit-glab-draft)))
    (let ((url (magit-glab-mr-web-url mr)))
      (magit-glab--field "URL" (propertize (buttonize url #'browse-url url "Open in browser")
                                           'font-lock-face 'link)))))

(defun magit-glab--insert-draft (mr draft)
  "Insert a section of DRAFT, a draft note on MR."
  (let* ((reply-to (and (magit-glab-draft-discussion-id draft)
                        (seq-find (lambda (d) (equal (magit-glab-discussion-id d)
                                                     (magit-glab-draft-discussion-id draft)))
                                  (magit-glab-mr-discussions mr))))
         (where (cond (reply-to (format "reply to %s"
                                        (magit-glab-note-author
                                         (magit-glab-discussion-first reply-to))))
                      ((magit-glab-draft-position draft)
                       (magit-glab-position-label (magit-glab-draft-position draft)))
                      ("new thread"))))
    (magit-insert-section (magit-glab-draft-section (magit-glab-draft-id draft))
      (magit-insert-heading
        (concat "  " (propertize "draft" 'face 'magit-glab-draft) "  " where
                (if (magit-glab-draft-resolve draft) (propertize "  + resolve" 'face 'shadow) "")))
      (magit-glab-insert-indented
       (magit-glab-fontify-markdown (magit-glab-draft-body draft)) 4))))

(defun magit-glab-mr--render ()
  "Fill this merge request buffer from the cache."
  (let* ((key magit-glab-buffer-key)
         (mr (magit-glab-get-mr key)))
    (magit-glab-with-rerender
      (magit-insert-section (magit-glab-mr-root)
        (if (not mr)
            (insert (format "Fetching !%d of %s...\n" (cdr key) (car key)))
          (magit-insert-heading
            (concat (propertize (format "!%d " (cdr key)) 'face 'magit-hash)
                    (propertize (magit-glab-mr-title mr)
                                'face (if (magit-glab-mr-draft mr)
                                          '(magit-glab-draft magit-section-heading)
                                        'magit-section-heading))))
          (magit-glab--insert-header mr)
          (insert "\n")
          (if (not (magit-glab-mr-full-p mr))
              (insert (if (magit-glab-fetching-p key) "Fetching threads...\n"
                        "Could not fetch everything; g to try again.\n"))
            (magit-glab--insert-body mr)))))
    (when (and mr (magit-glab-mr-full-p mr) (get-buffer-window))
      (magit-glab--mark-visited mr))))

(defun magit-glab--insert-body (mr)
  "Insert the description, drafts, threads and patchsets of MR."
  (let* ((seen magit-glab-mr--seen-note)
         (discussions (magit-glab-visible-discussions mr))
         (threads (seq-filter #'magit-glab-discussion-resolvable discussions))
         (open (magit-glab--sorted-threads
                (seq-remove #'magit-glab-discussion-resolved threads)))
         (resolved (magit-glab--sorted-threads
                    (seq-filter #'magit-glab-discussion-resolved threads)))
         (comments (seq-remove #'magit-glab-discussion-resolvable discussions))
         (activity (seq-filter #'magit-glab-discussion-system-p
                               (magit-glab-mr-discussions mr)))
         (description (magit-glab-mr-description mr)))
    (magit-insert-section (magit-glab-description)
      (magit-insert-heading "Description")
      (magit-glab-insert-indented
       (if (string-blank-p (or description ""))
           (propertize "No description." 'face 'shadow)
         (magit-glab-fontify-markdown description))
       2)
      (insert "\n"))
    (when-let* ((drafts (magit-glab-mr-drafts mr)))
      (magit-insert-section (magit-glab-drafts)
        (magit-insert-heading (propertize (format "Your drafts (%d)" (length drafts))
                                          'face '(magit-glab-draft magit-section-heading)))
        (dolist (draft drafts)
          (magit-glab--insert-draft mr draft))
        (insert "\n")))
    (magit-insert-section (magit-glab-open-threads)
      (magit-insert-heading (format "Open threads (%d)" (length open)))
      (dolist (discussion open)
        (magit-glab-insert-discussion discussion seen))
      (insert "\n"))
    (when resolved
      (magit-insert-section (magit-glab-resolved-threads nil t)
        (magit-insert-heading (format "Resolved threads (%d)" (length resolved)))
        (dolist (discussion resolved)
          (magit-glab-insert-discussion discussion seen t))
        (insert "\n")))
    (when comments
      (magit-insert-section (magit-glab-comments)
        (magit-insert-heading (format "Comments (%d)" (length comments)))
        (dolist (discussion comments)
          (magit-glab-insert-discussion discussion seen))
        (insert "\n")))
    (magit-glab-insert-patchsets mr)
    (insert "\n")
    (when activity
      (magit-insert-section (magit-glab-activity nil t)
        (magit-insert-heading (format "Activity (%d)" (length activity)))
        (dolist (discussion activity)
          (let ((note (magit-glab-discussion-first discussion)))
            (insert (propertize (string-pad (magit-glab-age (magit-glab-note-created note)) 6)
                                'face 'shadow)
                    (magit-glab-author-string (magit-glab-note-author note)) " "
                    (magit-glab-first-line (magit-glab-note-body note) 100) "\n")))))))

(defun magit-glab--mark-visited (mr)
  "Record that MR's notes were seen, as of now."
  (let ((ids (mapcan (lambda (discussion)
                       (mapcar #'magit-glab-note-id (magit-glab-discussion-notes discussion)))
                     (magit-glab-mr-discussions mr))))
    (magit-glab-mark-seen (magit-glab-mr-key mr)
                          :note (apply #'max 0 ids)
                          :count (magit-glab-mr-notes-count mr))))

;;;; Visiting what is at point

(defun magit-glab--goto-diff-line (buffer path side line)
  "In the diff BUFFER, go to LINE of PATH on SIDE."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when-let* ((pos (magit-glab--find-line (magit-glab--file-sections) path side line)))
        (goto-char pos)
        (when-let* ((window (get-buffer-window buffer)))
          (set-window-point window pos)
          (with-selected-window window (recenter)))))))

(defun magit-glab--visit-position (key position)
  "Show POSITION of merge request KEY in the diff of its patchset."
  (let* ((mr (magit-glab-full-mr key))
         (patchset (seq-find (lambda (p) (equal (magit-glab-patchset-head p)
                                                (plist-get position :head)))
                             (magit-glab-mr-patchsets mr)))
         (newest (car (last (magit-glab-mr-patchsets mr))))
         (buffer (if (or (not patchset) (eq patchset newest))
                     (magit-glab-mr-diff key)
                   (magit-glab-diff-patchsets key 'base patchset))))
    (if (plist-get position :new-line)
        (magit-glab--goto-diff-line buffer (plist-get position :new-path) 'new
                                    (plist-get position :new-line))
      (magit-glab--goto-diff-line buffer (plist-get position :old-path) 'old
                                  (plist-get position :old-line)))))

(defun magit-glab-visit ()
  "Visit what is at point.
A thread or a draft on a line: that line in the diff.  A patchset: its
diff against the one before.  A merge request: its buffer."
  (interactive)
  (let ((section (magit-current-section)))
    (while (and section
                (not (cl-typep section '(or magit-glab-thread-section
                                            magit-glab-draft-section
                                            magit-glab-patchset-section
                                            magit-glab-mr-section
                                            magit-glab-todo-section))))
      (setq section (oref section parent)))
    (cond
     ((null section) (user-error "Nothing to visit here"))
     ((magit-glab-thread-section-p section)
      (pcase-let ((`(,key . ,discussion) (magit-glab-discussion-at-point)))
        (if-let* ((position (magit-glab-discussion-position discussion)))
            (magit-glab--visit-position key position)
          (magit-section-toggle section))))
     ((magit-glab-draft-section-p section)
      (if-let* ((draft (cdr (magit-glab--draft-at-point)))
                (position (magit-glab-draft-position draft)))
          (magit-glab--visit-position magit-glab-buffer-key position)
        (magit-section-toggle section)))
     ((magit-glab-patchset-section-p section)
      (let* ((key magit-glab-buffer-key)
             (mr (magit-glab-full-mr key))
             (all (magit-glab-all-patchsets mr t))
             (number (oref section value))
             (patchset (seq-find (lambda (p) (= (magit-glab-patchset-number p) number)) all))
             (previous (seq-find (lambda (p) (= (magit-glab-patchset-number p) (1- number))) all)))
        (magit-glab-diff-patchsets key (or previous 'base) patchset)))
     ((magit-glab-todo-section-p section)
      (magit-glab-mr-visit (oref section value)))
     ((magit-glab-mr-section-p section)
      (magit-glab-mr-visit (oref section value))))))

(keymap-set magit-glab-mr-section-map "RET" #'magit-glab-visit)
(keymap-set magit-glab-mr-section-map "<remap> <magit-visit-thing>" #'magit-glab-visit)
(keymap-set magit-glab-patchset-section-map "RET" #'magit-glab-visit)

(provide 'magit-glab-mr)
;;; magit-glab-mr.el ends here
