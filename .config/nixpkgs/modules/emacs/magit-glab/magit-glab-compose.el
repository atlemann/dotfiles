;;; magit-glab-compose.el --- Comment, reply, resolve, review -*- lexical-binding: t -*-

;; Author: Tore Aadland
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (magit "4.0"))
;; Keywords: vc, tools

;;; Commentary:
;; Writing to GitLab.  Every comment is written in a compose buffer
;; (markdown), sent with C-c C-c and abandoned with C-c C-k.  A comment
;; that fails to send stays in its buffer, and an abandoned one can be
;; brought back with `magit-glab-compose-restore': written text is never
;; lost.
;;
;;   `magit-glab-reply'         reply to the thread at point
;;   `magit-glab-comment'       start a thread on the merge request
;;   `magit-glab-comment-line'  start a thread on the diff line at point
;;   `magit-glab-edit-note'     edit one of your notes
;;   `magit-glab-delete-note'   delete one of your notes
;;   `magit-glab-toggle-resolved'  resolve or unresolve the thread at point
;;   `magit-glab-done'          reply "Done" and resolve, in one go
;;
;; Reviews, as in Gerrit: `magit-glab-review-start' makes what is
;; written on a merge request a draft -- GitLab's draft notes, visible
;; only to you -- until `magit-glab-review-publish' publishes them all
;; at once, optionally approving.
;;
;; A new inline comment is positioned on the diff it is written in, so
;; that has to be the merge request's newest diff: the buffer of
;; `magit-glab-mr-diff', or the revision buffer of the newest patchset
;; of a one-commit merge request (any push-stack one).

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'magit)
(require 'magit-glab-core)
(require 'magit-glab-threads)
(require 'markdown-mode nil t)

(defcustom magit-glab-done-text "Done"
  "What `magit-glab-done' replies before resolving."
  :group 'magit-glab
  :type 'string)

;;;; Sending

(defun magit-glab--after-write (key &optional message)
  "Refetch merge request KEY and the dashboard after writing to it.
Show MESSAGE once the write is done."
  (when message (message "%s" message))
  (magit-glab-refresh-mr key)
  (when magit-glab--dashboard
    (magit-glab-refresh-dashboard)))

(defun magit-glab--write (key suffix method body &optional callback errback)
  "Send BODY to merge request KEY's endpoint SUFFIX with METHOD.
Then call CALLBACK with the response; on failure, ERRBACK with the
message, or show it."
  (magit-glab-api (magit-glab--mr-endpoint key suffix)
                  :method method :body body
                  :callback (or callback #'ignore)
                  :errback (or errback #'magit-glab-default-errback)))

(defun magit-glab--position-body (position)
  "Return POSITION, a plist, as the JSON object GitLab expects."
  `((position_type . "text")
    (base_sha . ,(plist-get position :base))
    (start_sha . ,(plist-get position :start))
    (head_sha . ,(plist-get position :head))
    (old_path . ,(plist-get position :old-path))
    (new_path . ,(plist-get position :new-path))
    ,@(and (plist-get position :old-line) `((old_line . ,(plist-get position :old-line))))
    ,@(and (plist-get position :new-line) `((new_line . ,(plist-get position :new-line))))))

;;;; Reviews

(defvar magit-glab--reviewing (make-hash-table :test #'equal)
  "Merge requests in review mode: comments on them are drafts.")

(defun magit-glab-reviewing-p (key)
  "Return non-nil if comments on merge request KEY become drafts."
  (gethash key magit-glab--reviewing))

;;;###autoload
(defun magit-glab-review-start (key)
  "Make comments on merge request KEY drafts, until the review is published."
  (interactive (list (magit-glab-current-key)))
  (puthash key t magit-glab--reviewing)
  (magit-glab--changed key)
  (message "Reviewing !%d: comments are drafts until `magit-glab-review-publish'"
           (cdr key)))

;;;###autoload
(defun magit-glab-review-stop (key)
  "Stop making comments on merge request KEY drafts; drafts stay drafts."
  (interactive (list (magit-glab-current-key)))
  (remhash key magit-glab--reviewing)
  (magit-glab--changed key)
  (message "Comments on !%d are sent at once again" (cdr key)))

;;;###autoload
(defun magit-glab-review-publish (key &optional approve)
  "Publish all draft comments on merge request KEY.
With APPROVE (a prefix argument, or answered when asked), approve it
too."
  (interactive
   (let* ((key (magit-glab-current-key))
          (mr (magit-glab-full-mr key)))
     (list key
           (or current-prefix-arg
               (and (not (magit-glab-mr-mine-p mr))
                    (not (member (magit-glab-username) (magit-glab-mr-approved-by mr)))
                    (y-or-n-p (format "Approve !%d too? " (cdr key))))))))
  (let* ((mr (magit-glab-full-mr key))
         (drafts (magit-glab-mr-drafts mr)))
    (if (null drafts)
        (message "No drafts on !%d" (cdr key))
      (magit-glab--write
       key "/draft_notes/bulk_publish" "POST" nil
       (lambda (_)
         (remhash key magit-glab--reviewing)
         (if approve
             (magit-glab--write key "/approve" "POST" nil
                                (lambda (_)
                                  (magit-glab--after-write
                                   key (format "Published %d comments on !%d and approved it"
                                               (length drafts) (cdr key)))))
           (magit-glab--after-write
            key (format "Published %d comments on !%d" (length drafts) (cdr key)))))))))

;;;; The compose buffer

(defalias 'magit-glab--compose-parent-mode
  (if (fboundp 'gfm-mode) #'gfm-mode #'text-mode))

(defvar-local magit-glab-compose--spec nil
  "What this compose buffer is for, a plist:
:type     `reply', `thread', `note', `inline' or `edit'
:key      the merge request
:discussion-id, :note-id, :draft-id  what it replies to or edits
:position the diff position of an inline comment
:lines    the diff lines it is about, for suggestions
:resolve  resolve the thread when sending a reply
:draft    send as a draft
:label    what to say in the header line")

(defvar-local magit-glab-compose--windows nil
  "The window configuration before the compose buffer was shown.")

(defvar magit-glab--compose-ring nil
  "Comments abandoned in compose buffers, newest first.")

(defvar-keymap magit-glab-compose-mode-map
  "C-c C-c" #'magit-glab-compose-send
  "C-c C-k" #'magit-glab-compose-cancel
  "C-c C-r" #'magit-glab-compose-toggle-resolve
  "C-c C-d" #'magit-glab-compose-toggle-draft
  "C-c C-s" #'magit-glab-compose-insert-suggestion)

(define-derived-mode magit-glab-compose-mode magit-glab--compose-parent-mode "GitLab comment"
  "Write a GitLab comment.
\\<magit-glab-compose-mode-map>\
\\[magit-glab-compose-send] sends it, \\[magit-glab-compose-cancel] abandons it,
\\[magit-glab-compose-toggle-resolve] toggles resolving the thread,
\\[magit-glab-compose-toggle-draft] toggles sending it as a draft, and
\\[magit-glab-compose-insert-suggestion] inserts a suggestion for the lines \
it is about."
  (setq-local header-line-format '(:eval (magit-glab-compose--header))))

(defun magit-glab-compose--header ()
  "Return the header line of a compose buffer."
  (let ((spec magit-glab-compose--spec))
    (concat (plist-get spec :label)
            (if (plist-get spec :draft) (propertize "  [draft]" 'face 'magit-glab-draft) "")
            (if (plist-get spec :resolve) (propertize "  [resolve]" 'face 'magit-glab-good) "")
            (substitute-command-keys
             "  \\<magit-glab-compose-mode-map>\\[magit-glab-compose-send] send, \
\\[magit-glab-compose-cancel] cancel"))))

(defun magit-glab-compose (spec &optional initial)
  "Pop up a compose buffer for SPEC, a `magit-glab-compose--spec' plist.
INITIAL is the text to start with."
  (let* ((key (plist-get spec :key))
         (buffer (generate-new-buffer (format "*magit-glab-comment !%d*" (cdr key))))
         (windows (current-window-configuration))
         (directory default-directory))
    (unless (plist-member spec :draft)
      (setq spec (plist-put spec :draft (and (magit-glab-reviewing-p key)
                                             (not (eq (plist-get spec :type) 'edit))))))
    (with-current-buffer buffer
      (magit-glab-compose-mode)
      (setq default-directory directory)
      (setq magit-glab-compose--spec spec)
      (setq magit-glab-compose--windows windows)
      (when initial (insert initial)))
    (pop-to-buffer buffer '((display-buffer-below-selected)
                            (window-height . 12)))
    (message "%s" (substitute-command-keys
                   "\\<magit-glab-compose-mode-map>\\[magit-glab-compose-send] to send, \
\\[magit-glab-compose-cancel] to cancel"))))

(defun magit-glab-compose--close ()
  "Kill this compose buffer and restore the windows from before it."
  (let ((windows magit-glab-compose--windows))
    (kill-buffer (current-buffer))
    (when windows
      (set-window-configuration windows))))

(defun magit-glab-compose-cancel ()
  "Abandon this comment; `magit-glab-compose-restore' brings it back."
  (interactive nil magit-glab-compose-mode)
  (let ((text (string-trim (buffer-string))))
    (when (or (string-empty-p text)
              (y-or-n-p "Abandon this comment? "))
      (unless (string-empty-p text)
        (push text magit-glab--compose-ring))
      (magit-glab-compose--close))))

;;;###autoload
(defun magit-glab-compose-restore ()
  "Insert the most recently abandoned or unsent comment."
  (interactive)
  (unless magit-glab--compose-ring
    (user-error "No abandoned comments"))
  (insert (car magit-glab--compose-ring)))

(defun magit-glab-compose-toggle-resolve ()
  "Toggle resolving the thread when this reply is sent."
  (interactive nil magit-glab-compose-mode)
  (unless (memq (plist-get magit-glab-compose--spec :type) '(reply))
    (user-error "Only a reply can resolve a thread"))
  (setq magit-glab-compose--spec
        (plist-put magit-glab-compose--spec :resolve
                   (not (plist-get magit-glab-compose--spec :resolve))))
  (force-mode-line-update))

(defun magit-glab-compose-toggle-draft ()
  "Toggle sending this comment as a draft, to publish with a review."
  (interactive nil magit-glab-compose-mode)
  (when (eq (plist-get magit-glab-compose--spec :type) 'edit)
    (user-error "An edit is sent as it is"))
  (setq magit-glab-compose--spec
        (plist-put magit-glab-compose--spec :draft
                   (not (plist-get magit-glab-compose--spec :draft))))
  (force-mode-line-update))

(defun magit-glab-compose-insert-suggestion ()
  "Insert a GitLab suggestion replacing the diff lines this comment is on."
  (interactive nil magit-glab-compose-mode)
  (let ((lines (or (plist-get magit-glab-compose--spec :lines)
                   (user-error "This comment is not on diff lines"))))
    (unless (bolp) (insert "\n"))
    (insert (format "```suggestion:-%d+0\n" (1- (length lines)))
            (mapconcat #'identity lines "\n")
            "\n```\n")
    (forward-line -2)
    (end-of-line)))

(defun magit-glab-compose-send ()
  "Send this comment to GitLab."
  (interactive nil magit-glab-compose-mode)
  (let* ((spec magit-glab-compose--spec)
         (key (plist-get spec :key))
         (body (string-trim (buffer-string)))
         (buffer (current-buffer)))
    (when (string-empty-p body)
      (user-error "Nothing to send"))
    (message "Sending...")
    (magit-glab--send
     spec body
     (lambda (what)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (magit-glab-compose--close)))
       (magit-glab--after-write key what))
     (lambda (message)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (push body magit-glab--compose-ring)))
       (message "Not sent, the comment is still there: %s" message)))))

(defun magit-glab--send (spec body done failed)
  "Send BODY as SPEC says; call DONE with what was done, or FAILED."
  (let* ((key (plist-get spec :key))
         (discussion (plist-get spec :discussion-id))
         (draft (plist-get spec :draft))
         (resolve (plist-get spec :resolve))
         (position (plist-get spec :position)))
    (pcase (plist-get spec :type)
      ((guard draft)
       (magit-glab--write
        key "/draft_notes" "POST"
        `((note . ,body)
          ,@(and discussion `((in_reply_to_discussion_id . ,discussion)))
          ,@(and resolve `((resolve_discussion . t)))
          ,@(and position `((position . ,(magit-glab--position-body position)))))
        (lambda (_) (funcall done "Saved as a draft"))
        failed))
      ('reply
       (magit-glab--write
        key (format "/discussions/%s/notes" discussion) "POST" `((body . ,body))
        (lambda (_)
          (if resolve
              (magit-glab--set-resolved key discussion t
                                        (lambda () (funcall done "Replied and resolved"))
                                        failed)
            (funcall done "Replied")))
        failed))
      ('thread
       (magit-glab--write key "/discussions" "POST" `((body . ,body))
                          (lambda (_) (funcall done "Commented")) failed))
      ('note
       (magit-glab--write key "/notes" "POST" `((body . ,body))
                          (lambda (_) (funcall done "Commented")) failed))
      ('inline
       (magit-glab--write key "/discussions" "POST"
                          `((body . ,body)
                            (position . ,(magit-glab--position-body position)))
                          (lambda (_) (funcall done "Commented on the line")) failed))
      ('edit
       (if-let* ((draft-id (plist-get spec :draft-id)))
           (magit-glab--write key (format "/draft_notes/%s" draft-id) "PUT"
                              `((note . ,body))
                              (lambda (_) (funcall done "Draft edited")) failed)
         (magit-glab--write key (format "/discussions/%s/notes/%s" discussion
                                        (plist-get spec :note-id))
                            "PUT" `((body . ,body))
                            (lambda (_) (funcall done "Edited")) failed))))))

;;;; Commands

(defun magit-glab--discussion-or-error ()
  "Return (KEY . DISCUSSION) at point, or signal an error."
  (or (magit-glab-discussion-at-point)
      (user-error "No thread here")))

;;;###autoload
(defun magit-glab-reply ()
  "Reply to the thread at point.
With a region inside a note of the thread, quote it."
  (interactive)
  (pcase-let ((`(,key . ,discussion) (magit-glab--discussion-or-error)))
    (let ((quote (and (use-region-p)
                      (concat (mapconcat (lambda (line) (concat "> " (string-trim line)))
                                         (split-string (buffer-substring-no-properties
                                                        (region-beginning) (region-end))
                                                       "\n" t)
                                         "\n")
                              "\n\n")))
          (first (magit-glab-discussion-first discussion)))
      (deactivate-mark)
      (magit-glab-compose
       (list :type 'reply :key key
             :discussion-id (magit-glab-discussion-id discussion)
             :label (format "Reply to %s: %s" (magit-glab-note-author first)
                            (magit-glab-first-line (magit-glab-note-body first) 40)))
       quote))))

;;;###autoload
(defun magit-glab-comment (key &optional plain)
  "Start a thread on merge request KEY.
With a prefix argument PLAIN, a comment that cannot be resolved."
  (interactive (list (magit-glab-current-key) current-prefix-arg))
  (magit-glab-compose (list :type (if plain 'note 'thread) :key key
                            :label (format "%s on !%d" (if plain "Comment" "New thread")
                                           (cdr key)))))

(defun magit-glab--commentable-position (line)
  "Return the GitLab position of the diff LINE in this buffer, or signal why not.
LINE is a plist from `magit-glab-diff-line-at-point'.  Return (KEY .
POSITION)."
  (let* ((context (magit-glab--diff-context))
         (key (or (plist-get context :key)
                  (and (derived-mode-p 'magit-revision-mode) magit-glab-buffer-key)
                  (user-error "This diff is not a merge request's")))
         (mr (magit-glab-full-mr key))
         (refs (or (magit-glab-mr-diff-refs mr)
                   (user-error "GitLab has no diff for !%d" (cdr key)))))
    (cond
     (context
      (unless (plist-get context :commentable)
        (user-error "Comment in the merge request's own diff (`magit-glab-mr-diff')"))
      (unless (equal (plist-get context :new-head) (plist-get refs :head))
        (user-error "!%d has a newer patchset; refresh its diff first" (cdr key))))
     (t
      (let ((rev magit-buffer-revision-oid))
        (unless (equal rev (plist-get refs :head))
          (user-error "This commit is not !%d's newest patchset, %s"
                      (cdr key) (substring (plist-get refs :head) 0 8)))
        (unless (equal (magit-rev-parse (concat rev "^")) (plist-get refs :base))
          (user-error "!%d is not just this commit; comment in `magit-glab-mr-diff'"
                      (cdr key))))))
    (cons key (append (list :base (plist-get refs :base) :start (plist-get refs :start)
                            :head (plist-get refs :head))
                      line))))

;;;###autoload
(defun magit-glab-comment-line ()
  "Start a thread on the diff line at point.
With an active region, on its last line; then
\\<magit-glab-compose-mode-map>\\[magit-glab-compose-insert-suggestion] \
in the compose buffer suggests a replacement for all
its lines."
  (interactive)
  (let* ((lines (or (magit-glab-hunk-region-lines)
                    (when-let* ((line (magit-glab-diff-line-at-point))) (list line))
                    (user-error "Not on a diff line")))
         (line (car (last lines))))
    (pcase-let ((`(,key . ,position) (magit-glab--commentable-position line)))
      (deactivate-mark)
      (magit-glab-compose
       (list :type 'inline :key key :position position
             :lines (mapcar (lambda (l) (plist-get l :text))
                            (seq-filter (lambda (l) (plist-get l :new-line)) lines))
             :label (format "Comment on %s" (magit-glab-position-label position)))))))

(defun magit-glab--own-note ()
  "Return (KEY DISCUSSION NOTE) of the note at point, if the user wrote it."
  (pcase-let* ((`(,key . ,discussion) (magit-glab--discussion-or-error))
               (`(,_ . ,note-id) (magit-glab-note-at-point))
               (notes (magit-glab-discussion-notes discussion))
               (note (if note-id
                         (seq-find (lambda (n) (equal (magit-glab-note-id n) note-id)) notes)
                       (let ((mine (seq-filter (lambda (n) (equal (magit-glab-note-author n)
                                                                  (magit-glab-username)))
                                               notes)))
                         (car (last mine))))))
    (unless (and note (equal (magit-glab-note-author note) (magit-glab-username)))
      (user-error "Not your note"))
    (list key discussion note)))

(defun magit-glab--draft-at-point ()
  "Return (KEY . DRAFT) for the draft section at point, or nil."
  (let ((section (magit-current-section)))
    (when (magit-glab-draft-section-p section)
      (let* ((key (magit-glab-current-key t))
             (mr (magit-glab-get-mr key)))
        (cons key (seq-find (lambda (d) (equal (magit-glab-draft-id d) (oref section value)))
                            (magit-glab-mr-drafts mr)))))))

;;;###autoload
(defun magit-glab-edit-note ()
  "Edit your note, or draft, at point."
  (interactive)
  (if-let* ((draft (magit-glab--draft-at-point)))
      (magit-glab-compose (list :type 'edit :key (car draft)
                                :draft-id (magit-glab-draft-id (cdr draft))
                                :label "Edit draft")
                          (magit-glab-draft-body (cdr draft)))
    (pcase-let ((`(,key ,discussion ,note) (magit-glab--own-note)))
      (magit-glab-compose (list :type 'edit :key key
                                :discussion-id (magit-glab-discussion-id discussion)
                                :note-id (magit-glab-note-id note)
                                :label "Edit note")
                          (magit-glab-note-body note)))))

;;;###autoload
(defun magit-glab-delete-note ()
  "Delete your note, or draft, at point."
  (interactive)
  (if-let* ((draft (magit-glab--draft-at-point)))
      (when (y-or-n-p "Delete this draft? ")
        (magit-glab--write (car draft) (format "/draft_notes/%s" (magit-glab-draft-id (cdr draft)))
                           "DELETE" nil
                           (lambda (_) (magit-glab--after-write (car draft) "Draft deleted"))))
    (pcase-let ((`(,key ,discussion ,note) (magit-glab--own-note)))
      (when (yes-or-no-p (format "Delete your note \"%s\"? "
                                 (magit-glab-first-line (magit-glab-note-body note) 40)))
        (magit-glab--write key (format "/discussions/%s/notes/%s"
                                       (magit-glab-discussion-id discussion)
                                       (magit-glab-note-id note))
                           "DELETE" nil
                           (lambda (_) (magit-glab--after-write key "Note deleted")))))))

;;;; Resolving

(defun magit-glab--set-resolved (key discussion-id resolved &optional done failed)
  "Mark DISCUSSION-ID of merge request KEY RESOLVED or not.
The cached thread changes at once and buffers show it; the merge
request is refetched when GitLab has answered, which also undoes the
change if GitLab refused it.  Then call DONE, or FAILED with the error."
  (when-let* ((mr (magit-glab-get-mr key))
              (discussion (seq-find (lambda (d) (equal (magit-glab-discussion-id d) discussion-id))
                                    (magit-glab-mr-discussions mr))))
    (dolist (note (magit-glab-discussion-notes discussion))
      (when (magit-glab-note-resolvable note)
        (setf (magit-glab-note-resolved note) resolved)
        (setf (magit-glab-note-resolved-by note) (and resolved (magit-glab-username)))))
    (magit-glab--changed key))
  (magit-glab--write key (format "/discussions/%s" discussion-id) "PUT"
                     `((resolved . ,(if resolved t :false)))
                     (lambda (_)
                       (magit-glab-refresh-mr key)
                       (when done (funcall done)))
                     (lambda (message)
                       (magit-glab-refresh-mr key)
                       (funcall (or failed #'magit-glab-default-errback) message))))

;;;###autoload
(defun magit-glab-toggle-resolved ()
  "Resolve the thread at point, or unresolve it if it is resolved."
  (interactive)
  (pcase-let ((`(,key . ,discussion) (magit-glab--discussion-or-error)))
    (unless (magit-glab-discussion-resolvable discussion)
      (user-error "This comment is not a thread that can be resolved"))
    (let ((resolve (not (magit-glab-discussion-resolved discussion))))
      (magit-glab--set-resolved key (magit-glab-discussion-id discussion) resolve
                                (lambda () (message (if resolve "Resolved" "Unresolved"))))
      (when resolve
        (magit-glab-next-thread)))))

;;;###autoload
(defun magit-glab-done ()
  "Reply `magit-glab-done-text' to the thread at point, and resolve it."
  (interactive)
  (pcase-let ((`(,key . ,discussion) (magit-glab--discussion-or-error)))
    (let ((spec (list :type 'reply :key key
                      :discussion-id (magit-glab-discussion-id discussion)
                      :resolve t :draft (magit-glab-reviewing-p key))))
      (magit-glab--send spec magit-glab-done-text
                        (lambda (what) (magit-glab--after-write key what))
                        #'magit-glab-default-errback)
      (magit-glab-next-thread))))

(provide 'magit-glab-compose)
;;; magit-glab-compose.el ends here
